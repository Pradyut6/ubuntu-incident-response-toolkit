#!/usr/bin/env bash
# Explicit-only retention. Never prune exports or anything outside incidents/.

uir::retention::status() {
    local root usage
    root="$(uir::store::root)" || return $?
    uir::store::ready "$root" || return $?
    usage="$(du -sb -- "$root/incidents" | awk '{print $1}')"
    jq --argjson bytes "$usage" '{retention_days,max_storage_mib,capture_max_mib,
      incident_store_bytes:$bytes,automatic_pruning:false}' "$root/config/settings.json"
}

uir::retention::set() {
    local days='' max='' capture='' root file existing_days existing_max existing_capture
    local seen_days=0 seen_max=0 seen_capture=0
    while (($# > 0)); do
        case "$1" in
        --days)
            (($# >= 2 && !seen_days)) || return 2
            days="$2"
            seen_days=1
            shift 2
            ;;
        --max-storage-mb)
            (($# >= 2 && !seen_max)) || return 2
            max="$2"
            seen_max=1
            shift 2
            ;;
        --capture-max-mb)
            (($# >= 2 && !seen_capture)) || return 2
            capture="$2"
            seen_capture=1
            shift 2
            ;;
        *)
            uir::error "unexpected retention setting: $1"
            return 2
            ;;
        esac
    done
    if ((!seen_days && !seen_max && !seen_capture)); then
        uir::error 'usage: retention set [--days 30] [--max-storage-mb 500] [--capture-max-mb 10]'
        return 2
    fi
    uir::store::require_regular_user || return $?
    root="$(uir::store::root)" || return $?
    uir::store::ready "$root" || return $?
    file="$root/config/settings.json"
    existing_days="$(jq -r .retention_days "$file")"
    existing_max="$(jq -r .max_storage_mib "$file")"
    existing_capture="$(jq -r .capture_max_mib "$file")"
    [[ -n "$days" ]] || days="$existing_days"
    [[ -n "$max" ]] || max="$existing_max"
    [[ -n "$capture" ]] || capture="$existing_capture"
    if ! uir::validate::integer "$days" 1 3650 ||
        ! uir::validate::integer "$max" 10 10240 ||
        ! uir::validate::integer "$capture" 1 100 || ((10#$capture > 10#$max)); then
        uir::error 'invalid limits: days 1..3650, store 10..10240 MiB, capture 1..100 MiB <= store'
        return 2
    fi
    jq --argjson days "$((10#$days))" --argjson max "$((10#$max))" --argjson capture "$((10#$capture))" \
        '.retention_days=$days | .max_storage_mib=$max | .capture_max_mib=$capture' "$file" |
        uir::store::replace_json "$file" || return 5
    uir::retention::status
}

uir::retention::prune() {
    local option="${1:-}" root settings days cap usage now list path id created epoch bytes
    local reason count=0 deleted=0
    local -a targets=()
    [[ $# == 1 && ("$option" == --dry-run || "$option" == --yes) ]] || {
        uir::error 'usage: retention prune --dry-run | --yes'
        return 2
    }
    uir::store::require_regular_user || return $?
    root="$(uir::store::root)" || return $?
    uir::store::ready "$root" || return $?
    settings="$root/config/settings.json"
    days="$(jq -r .retention_days "$settings")"
    cap="$(jq -r .max_storage_mib "$settings")"
    usage="$(du -sb -- "$root/incidents" | awk '{print $1}')"
    now="$(date -u +%s)"
    list="$(mktemp "$root/.prune.XXXXXXXX")" || return 5
    # Validate every candidate before deciding to delete anything.
    for path in "$root"/incidents/*; do
        [[ -e "$path" || -L "$path" ]] || continue
        id="${path##*/}"
        if ! uir::validate::incident_id "$id" || ! uir::store::private_dir "$path" ||
            ! uir::store::metadata_valid "$path/incident.json" "$id"; then
            rm -f -- "$list"
            uir::error 'pruning aborted: unsafe incident record'
            return 5
        fi
        if find -P "$path" -type l -print -quit | grep -q .; then
            rm -f -- "$list"
            uir::error 'pruning aborted: symlink found inside incident'
            return 5
        fi
        created="$(jq -r .created_at "$path/incident.json")"
        epoch="$(date -u -d "$created" +%s 2>/dev/null)" || {
            rm -f -- "$list"
            return 5
        }
        bytes="$(du -sb -- "$path" | awk '{print $1}')"
        printf '%s\t%s\t%s\n' "$epoch" "$id" "$bytes" >>"$list"
    done
    sort -n -o "$list" "$list"
    printf 'Retention plan (days=%s, max_storage=%s MiB, current=%s bytes):\n' "$days" "$cap" "$usage"
    while IFS=$'\t' read -r epoch id bytes; do
        [[ -n "$id" ]] || continue
        reason=''
        if ((now - epoch > days * 86400)); then
            reason='expired'
        elif ((usage > cap * 1048576)); then
            reason='over-quota (oldest first)'
        fi
        if [[ -n "$reason" ]]; then
            printf '  %s  %s  %s bytes\n' "$id" "$reason" "$bytes"
            targets+=("$id")
            ((count += 1))
            ((usage = usage - bytes))
        fi
    done <"$list"
    rm -f -- "$list"
    if ((count == 0)); then
        printf 'No incidents eligible for pruning.\n'
        return 0
    fi
    if [[ "$option" == --dry-run ]]; then
        printf '%s incident(s) would be deleted. No changes made.\n' "$count"
        return 0
    fi
    # Precise IDs plus validated dir/files; deletion never follows symlinks.
    for id in "${targets[@]}"; do
        path="$root/incidents/$id"
        uir::store::private_dir "$path" || return 5
        uir::store::metadata_valid "$path/incident.json" "$id" || return 5
        if find -P "$path" -type l -print -quit | grep -q .; then
            uir::error 'prune aborted because the tree changed'
            return 5
        fi
        rm -rf -- "$path" || {
            uir::error "failed to prune $id"
            return 5
        }
        printf 'Pruned %s\n' "$id"
        ((deleted += 1))
    done
    printf 'Deleted %s incident(s); exported archives are unaffected.\n' "$deleted"
}
