#!/usr/bin/env bash
# Allowlisted, sanitized handoff archive. Never upload automatically.

# Enforce the real expanded size, not gzip -l's ISIZE metadata.
# gzip -l reports only the final member size for concatenated gzip files.
# Stop decoding after the first byte past the 12 MiB evidence limit.
uir::export::inflate_limited() {
    local source="$1" dest="$2" limit=$((12 * 1048576)) bytes
    if ! (
        set -o pipefail
        LC_ALL=C timeout --kill-after=1s 20s gzip -cd -- "$source" |
            head -c "$((limit + 1))" >"$dest"
    ); then
        return 5
    fi
    bytes="$(stat -c %s -- "$dest")" || return 5
    [[ "$bytes" =~ ^[0-9]+$ ]] && ((bytes <= limit))
}

# Remove high-risk machine/network identifiers from public snapshot metadata.
# The original private snapshot remains unchanged for local troubleshooting.
uir::export::scrub_snapshot_metadata() {
    local file="$1" tmp
    tmp="$(mktemp "${file}.tmp.XXXXXXXX")" || return 5
    if ! jq '
        if (.host | type) == "object" then
            .host.host_pseudonym = "[REDACTED_HOST_ID]" |
            .host.network = {interfaces:"[REDACTED_NETWORK_METADATA]",routes:"[REDACTED_NETWORK_METADATA]"}
        else . end |
        if (.tcp_listener | type) == "object" then
            .tcp_listener.addresses |= (if type=="array" then
                map(if type=="string" and contains(":") then "[REDACTED_IPv6]" else . end)
                else . end) |
            .tcp_listener.expected_address |= (if type=="string" and contains(":")
                then "[REDACTED_IPv6]" else . end)
        else . end
    ' "$file" >"$tmp"; then
        rm -f -- "$tmp"
        return 5
    fi
    mv -T -- "$tmp" "$file"
}

uir::export::scrub_comparison_metadata() {
    local file="$1" tmp
    tmp="$(mktemp "${file}.tmp.XXXXXXXX")" || return 5
    if ! jq '
        def mask6: if type=="string" and contains(":") then "[REDACTED_IPv6]" else . end;
        if (.changes | type)=="object" then
            if (.changes.tcp_addresses | type)=="object" then
                .changes.tcp_addresses.before |= (if type=="array" then map(mask6) else . end) |
                .changes.tcp_addresses.after |= (if type=="array" then map(mask6) else . end)
            else . end |
            if (.changes.tcp_target | type)=="object" then
                .changes.tcp_target.before.expected_address |= mask6 |
                .changes.tcp_target.after.expected_address |= mask6
            else . end
        else . end
    ' "$file" >"$tmp"; then
        rm -f -- "$tmp"
        return 5
    fi
    mv -T -- "$tmp" "$file"
}

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
                    # Preview must verify evidence without an unbounded gzip -t.
                    # Actual export verifies it with inflate_limited when staging.
                    if ((preview)); then
                        local check_tmp
                        check_tmp="$(mktemp "$dir/.export-check.XXXXXXXX")" || return 5
                        if ! uir::export::inflate_limited "$source_path" "$check_tmp"; then
                            rm -f -- "$check_tmp"
                            uir::error 'corrupt or oversized gzip evidence'
                            return 5
                        fi
                        rm -f -- "$check_tmp"
                    fi
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
    for phase in before after; do
        [[ -d "$dir/$phase" ]] || continue
        mkdir -m 700 -- "$stage/$phase"
        if ! uir::sanitize::public_file "$dir/$phase/snapshot.json" "$stage/$phase/snapshot.json" ||
            ! uir::export::scrub_snapshot_metadata "$stage/$phase/snapshot.json" ||
            ! jq -e 'type=="object"' "$stage/$phase/snapshot.json" >/dev/null 2>&1; then
            uir::error 'sanitization rendered snapshot JSON invalid'
            rm -rf -- "$stage"
            return 5
        fi
        for source in diagnostics.txt.gz journal.jsonl.gz; do
            local decompressed
            decompressed="$(mktemp "$stage/.inflated.XXXXXXXX")" || {
                rm -rf -- "$stage"
                return 5
            }
            if ! uir::export::inflate_limited "$dir/$phase/$source" "$decompressed"; then
                uir::error 'evidence decompression failed or exceeded 12 MiB'
                rm -rf -- "$stage"
                return 5
            fi
            if ! uir::sanitize::public <"$decompressed" | gzip -n -9 >"$stage/$phase/$source"; then
                rm -rf -- "$stage"
                uir::error 'could not sanitize and recompress evidence'
                return 5
            fi
            rm -f -- "$decompressed"
        done
        if ! gzip -cd -- "$stage/$phase/journal.jsonl.gz" | jq -c . >/dev/null; then
            uir::error 'sanitized journal no longer contains valid JSON Lines'
            rm -rf -- "$stage"
            return 5
        fi
    done
    if [[ -f "$dir/comparison.json" ]]; then
        if ! uir::sanitize::public_file "$dir/comparison.json" "$stage/comparison.json" ||
            ! uir::export::scrub_comparison_metadata "$stage/comparison.json" ||
            ! jq -e 'type == "object" and .schema_version == 1' "$stage/comparison.json" >/dev/null 2>&1; then
            uir::error 'sanitization rendered comparison JSON invalid'
            rm -rf -- "$stage"
            return 5
        fi
    fi
    # Render from the sanitized staging data, not from the private originals.
    # Otherwise the report can reintroduce unredacted IPv6/socket metadata.
    if ! uir::report::write "$stage" "$stage/report.md" ||
        ! uir::sanitize::public <"$stage/report.md" >"$stage/report.sanitized"; then
        rm -rf -- "$stage"
        return 5
    fi
    mv -T -- "$stage/report.sanitized" "$stage/report.md" || {
        rm -rf -- "$stage"
        return 5
    }
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
