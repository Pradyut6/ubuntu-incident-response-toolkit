#!/usr/bin/env bash
# TCP listener observation. Host-level socket visibility is NOT service ownership.
# Fixed ss invocation; does not contact a network endpoint or capture process details.

uir::collect::tcp() {
    local port="$1" expected="$2" json="$3" diagnostics="$4"
    local now ss_output='' ss_rc=0 addresses addresses_json state outcome

    if ! uir::validate::integer "$port" 1 65535; then
        uir::error 'TCP listener port must be 1..65535'
        return 2
    fi
    if [[ -n "$expected" && "$expected" != 127.0.0.1 && "$expected" != 127.0.0.2 && "$expected" != ::1 ]]; then
        uir::error 'expected bind address must be 127.0.0.1, 127.0.0.2 or ::1'
        return 2
    fi
    port="$((10#$port))"
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if ! command -v ss >/dev/null 2>&1; then
        ss_rc=127
    else
        ss_output="$(LC_ALL=C timeout --kill-after=1s 8s ss -H -lnt "( sport = :$port )" 2>/dev/null)" || ss_rc=$?
    fi

    if ((ss_rc != 0)); then
        addresses_json='[]'
        state=unknown
        outcome=collector_error
    else
        # The 4th field from `ss -H -lnt` is Local Address:Port, without
        # a process name. Strip only the validated numeric port suffix.
        addresses="$(printf '%s\n' "$ss_output" | awk -v suffix=":$port" \
            'NF >= 5 { if (substr($4, length($4)-length(suffix)+1) == suffix) print substr($4, 1, length($4)-length(suffix)) }' |
            sed -e 's/^\[//' -e 's/\]$//' | LC_ALL=C sort -u)"
        addresses_json="$(printf '%s\n' "$addresses" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')" || return 5
        if [[ "$addresses_json" == '[]' ]]; then
            state=not_listening
        else
            state=listening
        fi
        outcome=observed
    fi

    jq -n --arg time "$now" --argjson port "$port" \
        --arg expected "$expected" --arg state "$state" \
        --arg outcome "$outcome" --argjson exitcode "$ss_rc" \
        --argjson addresses "$addresses_json" \
        '{checked_at:$time,protocol:"tcp",scope:"host",port:$port,
          expected_address:(if $expected=="" then null else $expected end),
          addresses:$addresses,state:$state,outcome:$outcome,ss_exit:$exitcode,
          expected_address_listening:(if $expected=="" or $outcome!="observed" then null
            else ($addresses|index($expected)!=null or
                  ($expected=="127.0.0.1" and ($addresses|index("0.0.0.0")!=null)) or
                  ($expected=="::1" and ($addresses|index("::")!=null))) end)}' \
        >"$json" || return 5
    printf '[TCP listener port=%s state=%s addresses=%s expected=%s ss_exit=%s]\n' \
        "$port" "$state" "$addresses_json" "${expected:-none}" "$ss_rc" >>"$diagnostics"
    ((ss_rc == 0))
}
