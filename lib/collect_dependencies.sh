#!/usr/bin/env bash
# Opt-in, read-only, bounded inspection of direct systemd Requires= dependencies.
# Requires= and After= describe configuration, not a proven incident root cause.

uir::collect::dependencies() {
    local service="$1" json="$2" diagnostics="$3" unit requires='' after='' now
    local -a required=()
    local dep details load active sub result ordered count=0 inspected=0 invalid=0 failures=0
    local max_units=8 truncated=false outcome=all_active status=observed rows

    uir::validate::profile "$service" && [[ "$service" != host ]] || return 2
    unit="$service"
    if [[ "$unit" != *.service && "$unit" != *.socket ]]; then unit+='.service'; fi
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if ! requires="$(LC_ALL=C timeout --kill-after=1s 5s systemctl show "$unit" -p Requires --value 2>/dev/null)"; then
        failures=1
    fi
    if ! after="$(LC_ALL=C timeout --kill-after=1s 5s systemctl show "$unit" -p After --value 2>/dev/null)"; then
        failures=1
    fi
    # Never expand an arbitrarily large property returned by a service manager.
    if ((${#requires} > 8192 || ${#after} > 8192)); then
        requires="${requires:0:8192}"
        after="${after:0:8192}"
        truncated=true
        failures=1
    fi
    read -r -a required <<<"$requires"
    count=${#required[@]}
    rows="$(mktemp "${json}.rows.XXXXXXXX")" || return 5

    for dep in "${required[@]}"; do
        if ((inspected >= max_units)); then
            truncated=true
            break
        fi
        # The property is an external value, not an authorization to inspect arbitrary names.
        if ! uir::validate::dependency_unit "$dep"; then
            ((invalid += 1))
            failures=1
            continue
        fi
        ((inspected += 1))
        details="$(LC_ALL=C timeout --kill-after=1s 5s systemctl show "$dep" \
            -p LoadState -p ActiveState -p SubState -p Result 2>/dev/null)" || {
            details=''
            failures=1
        }
        load=unknown active=unknown sub=unknown result=unknown
        while IFS='=' read -r key value; do
            case "$key" in
            LoadState) load="$value" ;;
            ActiveState) active="$value" ;;
            SubState) sub="$value" ;;
            Result) result="$value" ;;
            esac
        done <<<"$details"
        # Result is a service-specific property; targets and slices may omit it.
        # A missing Result on these units is not a collection failure.
        if [[ "$dep" != *.service && "$dep" != *.socket && "$result" == unknown ]]; then
            result=not_applicable
        fi
        for key in load active sub result; do
            # Status values are metadata, never commands or free-form journal text.
            local v="${!key}"
            if [[ ! "$v" =~ ^[a-zA-Z0-9_.-]{1,64}$ ]]; then
                printf -v "$key" '%s' unknown
                failures=1
            fi
        done
        if [[ "$active" == unknown || "$load" == unknown || "$sub" == unknown || "$result" == unknown ]]; then
            failures=1
        fi
        if [[ "$active" == failed || "$load" == not-found ]]; then
            outcome=dependency_failed
        elif [[ "$active" != active && "$outcome" != dependency_failed ]]; then
            outcome=not_all_active
        fi
        ordered=false
        if [[ " $after " == *" $dep "* ]]; then ordered=true; fi
        jq -nc --arg unit "$dep" --arg load "$load" --arg active "$active" \
            --arg sub "$sub" --arg result "$result" --argjson ordered "$ordered" \
            '{unit:$unit,load_state:$load,active_state:$active,sub_state:$sub,
              result:$result,ordered_after:$ordered}' >>"$rows" || {
            rm -f -- "$rows"
            return 5
        }
    done

    if ((count == 0 && failures == 0)); then outcome=no_requires; fi
    if ((failures != 0)) || [[ "$truncated" == true ]]; then
        status=partial
        # Incomplete evidence cannot establish that all dependencies are active.
        if [[ "$outcome" == all_active || "$outcome" == no_requires ]]; then outcome=unknown; fi
    fi
    if ! jq -n --slurpfile rows "$rows" --arg unit "$unit" --arg time "$now" \
        --arg status "$status" --arg outcome "$outcome" --argjson total "$count" \
        --argjson checked "$inspected" --argjson skipped "$invalid" \
        --argjson truncated "$truncated" \
        '{checked_at:$time,unit:$unit,status:$status,outcome:$outcome,
          requires_total:$total,inspected_count:$checked,invalid_unit_names:$skipped,
          truncated:$truncated,required_units:$rows}' >"$json"; then
        rm -f -- "$rows"
        return 5
    fi
    rm -f -- "$rows"
    printf '[Dependency inspection unit=%s status=%s outcome=%s requires=%d inspected=%d truncated=%s]\n' \
        "$unit" "$status" "$outcome" "$count" "$inspected" "$truncated" >>"$diagnostics"
    [[ "$status" == observed ]]
}
