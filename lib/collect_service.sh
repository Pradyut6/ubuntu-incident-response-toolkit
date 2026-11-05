#!/usr/bin/env bash
# Ubuntu service collectors; no sudo and no config editing.

uir::collect::service() {
    local service="$1" json="$2" diagnostics="$3" journal="$4" minutes="$5"
    local unit active substate state result fragment active_enter ports status=0 journal_status=0
    if ! uir::validate::profile "$service"; then
        uir::error 'unsupported service profile: allowed host, nginx, ssh, ssh.socket, uir-* training units'
        return 2
    fi
    if [[ "$service" == host ]]; then
        jq -n '{unit:"host",active_state:"not_applicable",sub_state:"not_applicable",
          load_state:"not_applicable",result:"not_applicable",
          active_enter_timestamp:"not_applicable",fragment_path:"not_applicable",
          listening_default_ports:[]}' >"$json"
        printf '\n[host-only profile: no unrestricted journal collection]\n' >>"$diagnostics"
        : >"$journal"
        return 0
    fi
    unit="$service"
    if [[ "$unit" != *.service && "$unit" != *.socket ]]; then unit+='.service'; fi
    active="$(timeout 8s systemctl show "$unit" -p ActiveState --value 2>/dev/null)" || {
        active='unknown'
        status=1
    }
    substate="$(timeout 8s systemctl show "$unit" -p SubState --value 2>/dev/null)" || {
        substate='unknown'
        status=1
    }
    state="$(timeout 8s systemctl show "$unit" -p LoadState --value 2>/dev/null)" || {
        state='unknown'
        status=1
    }
    result="$(timeout 8s systemctl show "$unit" -p Result --value 2>/dev/null)" || result='unavailable'
    active_enter="$(timeout 8s systemctl show "$unit" -p ActiveEnterTimestamp --value 2>/dev/null)" || active_enter='unavailable'
    fragment="$(timeout 8s systemctl show "$unit" -p FragmentPath --value 2>/dev/null)" || fragment='unavailable'
    ports='[]'
    # Only link the listener to the daemon for common service ports. A port
    # being open does not prove that the expected application is responding.
    local port=0
    case "$unit" in nginx.service) port=80 ;; ssh.service | ssh.socket) port=22 ;; esac
    if ((port > 0)); then
        if timeout 8s ss -H -lnt "( sport = :$port )" 2>/dev/null | grep -q .; then ports="[$port]"; fi
    fi
    jq -n --arg unit "$unit" --arg active "$active" --arg sub "$substate" \
        --arg load "$state" --arg result "$result" --arg since "$active_enter" \
        --arg fragment "$fragment" --argjson ports "$ports" \
        '{unit:$unit,active_state:$active,sub_state:$sub,load_state:$load,result:$result,
      active_enter_timestamp:$since,fragment_path:$fragment,listening_default_ports:$ports}' >"$json" || return 5
    uir::collect::run "systemctl show $unit" "$diagnostics" systemctl show "$unit" \
        --property=Id,LoadState,ActiveState,SubState,Result,FragmentPath,ActiveEnterTimestamp || status=1
    if [[ "$unit" == nginx.service ]] && command -v nginx >/dev/null 2>&1; then
        uir::collect::run 'nginx -t (no changes)' "$diagnostics" nginx -t || status=1
    fi
    if [[ "$unit" == ssh.service || "$unit" == ssh.socket ]]; then
        uir::collect::run 'ssh.socket status' "$diagnostics" systemctl show ssh.socket \
            --property=LoadState,ActiveState,SubState || status=1
    fi
    : >"$journal"
    # --lines bounds records; --since bounds age. Run under ordinary user:
    # incomplete group permissions are reported, never masked by sudo.
    (
        ulimit -f 4096
        timeout 12s journalctl --no-pager --output=json --unit="$unit" \
            --since="${minutes} minutes ago" --lines=300 --quiet
    ) >"$journal" 2>"${journal}.err" || journal_status=$?
    if ((journal_status > 0)); then
        printf '[journalctl failed exit=%s for %s]\n' "$journal_status" "$unit" >>"$diagnostics"
        cat "${journal}.err" >>"$diagnostics"
        status=1
    elif [[ -s "${journal}.err" ]]; then
        printf '[journalctl warnings for %s]\n' "$unit" >>"$diagnostics"
        cat "${journal}.err" >>"$diagnostics"
        status=1
    fi
    rm -f -- "${journal}.err"
    if [[ "$active" == unknown || "$state" == unknown || "$state" == not-found ]]; then status=1; fi
    return "$status"
}
