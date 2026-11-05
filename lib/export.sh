#!/usr/bin/env bash
# Allowlisted, sanitized handoff archive. Never upload automatically.

uir::export::validate_destination() {
    local output="$1" parent base
    if [[ "$output" != /* ]]; then
        output="$PWD/${output#./}"
    fi
    base="${output##*/}"
    parent="${output%/*}"
    if [[ ! "$base" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,100}\.tar\.gz$ ]]; then
        uir::error 'output must have a safe basename ending in .tar.gz'
        return 2
    fi
    uir::validate::absolute_path "$parent" || return $?
    [[ -d "$parent" && ! -L "$parent" ]] || {
        uir::error 'export parent directory is invalid'
        return 5
    }
    if [[ -e "$output" || -L "$output" ]]; then
        uir::error 'export destination already exists; refusing to overwrite'
        return 5
    fi
    printf '%s\n' "$output"
}

uir::export::run() {
    local id='' output='' preview=0 dir root phase source stage archive size source_path
    local have_id=0 have_output=0
    while (($# > 0)); do
        case "$1" in
        --incident)
            (($# >= 2 && !have_id)) || return 2
            id="$2"
            have_id=1
            shift 2
            ;;
        --output)
            (($# >= 2 && !have_output)) || return 2
            output="$2"
            have_output=1
            shift 2
            ;;
        --preview)
            preview=1
            shift
            ;;
        *)
            uir::error "unknown export argument: $1"
            return 2
            ;;
        esac
    done
    if ! uir::validate::incident_id "$id" || ((!preview && !have_output)); then
        uir::error 'usage: export --incident INC-007 --preview | export --incident INC-007 --output ./INC-007-handoff.tar.gz'
        return 2
    fi
    dir="$(uir::store::locked_incident "$id")" || return $?
    for phase in before after; do
        if [[ -e "$dir/$phase" || -L "$dir/$phase" ]]; then
            uir::store::private_dir "$dir/$phase" || return $?
            for source in snapshot.json diagnostics.txt.gz journal.jsonl.gz; do
                source_path="$dir/$phase/$source"
                if [[ "$source" == *.gz ]]; then
                    uir::store::evidence_file "$source_path" || return $?
                else
                    uir::store::private_file "$source_path" || return $?
                fi
                if [[ "$source" == *.gz ]]; then
                    gzip -t -- "$source_path" || {
                        uir::error 'corrupt evidence archive'
                        return 5
                    }
                else
                    jq -e --arg id "$id" 'type=="object" and .incident_id==$id' "$source_path" >/dev/null || return 5
                fi
            done
        fi
    done
    if [[ -e "$dir/comparison.json" || -L "$dir/comparison.json" ]]; then
        uir::store::private_file "$dir/comparison.json" || return $?
        jq -e 'type=="object" and .schema_version==1' "$dir/comparison.json" >/dev/null || return 5
    fi
    if ((preview)); then
        printf 'Handoff preview for %s (data not exported):\n' "$id"
        printf '  incident.json (public-redacted)\n  report.md (public-redacted)\n  SHA256SUMS\n'
        for phase in before after; do
            if [[ -d "$dir/$phase" ]]; then
                printf '  %s/{snapshot.json,diagnostics.txt.gz,journal.jsonl.gz} (public-redacted)\n' "$phase"
            fi
        done
        [[ ! -f "$dir/comparison.json" ]] || printf '  comparison.json (public-redacted)\n'
        printf 'WARNING: Automated redaction is incomplete by design; review the archive manually before sharing.\n'
        return 0
    fi
    output="$(uir::export::validate_destination "$output")" || return $?
    root="$(uir::store::root)"
    stage="$(mktemp -d "$root/.export.XXXXXXXX")" || return 5
    chmod 700 -- "$stage"
    uir::sanitize::public_file "$dir/incident.json" "$stage/incident.json"
    if ! jq -e 'type=="object"' "$stage/incident.json" >/dev/null 2>&1; then
        uir::error 'sanitization rendered incident JSON invalid'
        rm -rf -- "$stage"
        return 5
    fi
    uir::report::write "$dir" "$stage/report.md" || {
        rm -rf -- "$stage"
        return 5
    }
    # The generated report is sanitized after rendering, too.
    uir::sanitize::public <"$stage/report.md" >"$stage/report.sanitized"
    mv -T -- "$stage/report.sanitized" "$stage/report.md"
    for phase in before after; do
        [[ -d "$dir/$phase" ]] || continue
        mkdir -m 700 -- "$stage/$phase"
        uir::sanitize::public_file "$dir/$phase/snapshot.json" "$stage/$phase/snapshot.json"
        if ! jq -e 'type=="object"' "$stage/$phase/snapshot.json" >/dev/null 2>&1; then
            uir::error 'sanitization rendered snapshot JSON invalid'
            rm -rf -- "$stage"
            return 5
        fi
        for source in diagnostics.txt.gz journal.jsonl.gz; do
            local decompressed
            decompressed="$(gzip -l -- "$dir/$phase/$source" | awk 'NR==2 {print $2}')"
            if [[ ! "$decompressed" =~ ^[0-9]+$ ]] || ((decompressed > 12 * 1048576)); then
                uir::error 'suspicious or oversized decompressed input; refusing export'
                rm -rf -- "$stage"
                return 5
            fi
            if ! gzip -cd -- "$dir/$phase/$source" | uir::sanitize::public | gzip -n -9 >"$stage/$phase/$source"; then
                rm -rf -- "$stage"
                uir::error 'could not sanitize and recompress evidence'
                return 5
            fi
        done
        if ! gzip -cd -- "$stage/$phase/journal.jsonl.gz" | jq -c . >/dev/null; then
            uir::error 'sanitized journal no longer contains valid JSON Lines'
            rm -rf -- "$stage"
            return 5
        fi
    done
    if [[ -f "$dir/comparison.json" ]]; then
        uir::sanitize::public_file "$dir/comparison.json" "$stage/comparison.json"
    fi
    printf 'Ubuntu Incident Response Toolkit — sanitized export\nIncident: %s\nRedaction policy: %s\n' \
        "$id" "$UIR_REDACTION_POLICY" >"$stage/README.txt"
    printf 'NOT A GUARANTEE OF ANONYMITY. Review contents for remaining secrets before sharing.\n' >>"$stage/README.txt"
    # Enumerate staged files only; never recursively archive untrusted source dirs.
    (cd -- "$stage" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 -r sha256sum >SHA256SUMS) || {
        rm -rf -- "$stage"
        return 5
    }
    archive="$(mktemp "${output}.tmp.XXXXXXXX")" || {
        rm -rf -- "$stage"
        return 5
    }
    if ! tar -C "$stage" -czf "$archive" -- .; then
        rm -f -- "$archive"
        rm -rf -- "$stage"
        return 5
    fi
    size="$(stat -c %s "$archive")"
    if ((size > 25 * 1048576)); then
        uir::error 'export exceeds 25 MiB safety limit'
        rm -f -- "$archive"
        rm -rf -- "$stage"
        return 5
    fi
    chmod 600 -- "$archive"
    if ! ln -- "$archive" "$output"; then
        uir::error 'could not publish archive without overwriting destination'
        rm -f -- "$archive"
        rm -rf -- "$stage"
        return 5
    fi
    rm -f -- "$archive"
    rm -rf -- "$stage"
    printf 'Exported %s (%s bytes)\n' "$output" "$size"
    printf 'IMPORTANT: Inspect and verify archive contents before uploading or sharing.\n'
}
