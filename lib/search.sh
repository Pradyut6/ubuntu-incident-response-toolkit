#!/usr/bin/env bash
# Literal search across validated incident metadata and saved bounded evidence.
uir::search::run() {
    local service='' severity='' since='' text='' id='' root dir meta match path
    local have_service=0 have_severity=0 have_since=0 have_text=0 have_id=0 found=0
    while (($# > 0)); do
        case "$1" in
        --service)
            (($# >= 2 && !have_service)) || return 2
            service="$2"
            have_service=1
            shift 2
            ;;
        --severity)
            (($# >= 2 && !have_severity)) || return 2
            severity="$2"
            have_severity=1
            shift 2
            ;;
        --since)
            (($# >= 2 && !have_since)) || return 2
            since="$2"
            have_since=1
            shift 2
            ;;
        --text)
            (($# >= 2 && !have_text)) || return 2
            text="$2"
            have_text=1
            shift 2
            ;;
        --id)
            (($# >= 2 && !have_id)) || return 2
            id="$2"
            have_id=1
            shift 2
            ;;
        *)
            uir::error "unknown search option: $1"
            return 2
            ;;
        esac
    done
    if [[ -n "$id" ]] && ! uir::validate::incident_id "$id"; then
        uir::error 'invalid ID'
        return 2
    fi
    if [[ -n "$service" ]] && ! uir::validate::service "$service"; then
        uir::error 'invalid service'
        return 2
    fi
    if [[ -n "$severity" ]] && ! uir::validate::severity "$severity"; then
        uir::error 'invalid severity'
        return 2
    fi
    if [[ -n "$since" ]] && ! uir::validate::date "$since"; then
        uir::error 'invalid --since date (YYYY-MM-DD)'
        return 2
    fi
    if ((${#text} > 200)) || [[ "$text" =~ [[:cntrl:]] ]]; then
        uir::error 'unsafe search text'
        return 2
    fi
    root="$(uir::store::root)" || return $?
    uir::store::ready "$root" || return $?
    printf 'ID\tSERVICE\tSEVERITY\tSTATUS\tCREATED_UTC\tSUMMARY\n'
    for dir in "$root"/incidents/*; do
        [[ -e "$dir" || -L "$dir" ]] || continue
        local dirid="${dir##*/}"
        uir::validate::incident_id "$dirid" || {
            uir::error 'unexpected incident directory'
            return 5
        }
        uir::store::private_dir "$dir" || return $?
        meta="$dir/incident.json"
        uir::store::metadata_valid "$meta" "$dirid" || return $?
        match="$(jq -r --arg service "$service" --arg severity "$severity" \
            --arg since "$since" --arg id "$id" \
            '(.incident_id == $id or $id == "") and (.service == $service or $service == "") and
          (.severity == $severity or $severity == "") and ((.created_at[0:10] >= $since) or $since == "")' "$meta")"
        [[ "$match" == true ]] || continue
        if [[ -n "$text" ]]; then
            match=0
            if grep -Fi -- "$text" "$meta" >/dev/null; then match=1; fi
            if ((!match)); then
                for path in "$dir"/{before,after}/{diagnostics.txt.gz,journal.jsonl.gz}; do
                    [[ -e "$path" || -L "$path" ]] || continue
                    uir::store::private_dir "${path%/*}" || return $?
                    uir::store::evidence_file "$path" || return $?
                    if ! gzip -t -- "$path"; then
                        uir::error "corrupt gzip: $path"
                        return 5
                    fi
                    # grep consumes entire stream; no execution of match text.
                    if gzip -cd -- "$path" | grep -Fi -- "$text" >/dev/null; then
                        match=1
                        break
                    fi
                done
            fi
            ((match)) || continue
        fi
        jq -r '[.incident_id,.service,.severity,.status,.created_at,.summary] | @tsv' "$meta"
        ((found += 1))
    done
    if ((!found)); then printf '(no matching incidents)\n'; fi
}
