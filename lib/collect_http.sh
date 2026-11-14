#!/usr/bin/env bash
# Optional, explicitly requested, loopback-only HTTP observation.
# Never follows redirects, loads .curlrc, sends credentials, or records bodies.

uir::collect::http() {
    local port="$1" json="$2" diagnostics="$3"
    local checked_at output='' curl_exit=0 http_code=0 elapsed='0' outcome=collector_error

    # Defense in depth: never permit arbitrary destinations or a nonnumeric port.
    if ! uir::validate::integer "$port" 1 65535; then
        uir::error 'invalid HTTP port (expected 1..65535)'
        return 2
    fi
    # Normalize decimal string for jq and URL generation.
    port="$((10#$port))"
    checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if ! command -v curl >/dev/null 2>&1; then
        outcome=collector_unavailable
        curl_exit=127
    else
        # -q MUST be curl's first argument: ignore any user .curlrc.
        # Do not use -f: 4xx and 5xx are observations, not collection failures.
        # Output is limited to numeric status and duration; response data discarded.
        output="$(LC_ALL=C timeout --kill-after=1s 8s curl -q \
            --noproxy '*' --proxy '' --globoff --max-redirs 0 \
            --connect-timeout 2 --max-time 6 --silent \
            --output /dev/null --write-out '%{http_code} %{time_total}' \
            -- "http://127.0.0.1:${port}/" 2>/dev/null)" || curl_exit=$?

        if [[ "$output" =~ ^([0-9]{3})[[:space:]]([0-9]+([.][0-9]+)?)$ ]]; then
            http_code="${BASH_REMATCH[1]}"
            elapsed="${BASH_REMATCH[2]}"
            if ((curl_exit == 0)) && ((10#$http_code >= 200 && 10#$http_code <= 299)); then
                outcome=healthy
            elif ((curl_exit == 0)) && ((10#$http_code >= 100 && 10#$http_code <= 599)); then
                outcome=http_error
            elif ((curl_exit == 28 || curl_exit == 124 || curl_exit == 137)); then
                outcome=timeout
            else
                outcome=transport_error
            fi
        elif ((curl_exit == 28 || curl_exit == 124 || curl_exit == 137)); then
            outcome=timeout
        else
            outcome=collector_error
        fi
    fi

    # A transport or HTTP error is still a successfully recorded observation.
    # Only failure of the probe mechanism itself makes collection partial.
    jq -n --arg time "$checked_at" --argjson port "$port" \
        --arg code "$http_code" --arg elapsed "$elapsed" \
        --arg outcome "$outcome" --argjson exitcode "$curl_exit" \
        '{checked_at:$time,host:"127.0.0.1",port:$port,path:"/",
          http_status:(if $code=="000" then null else ($code|tonumber) end),
          outcome:$outcome,curl_exit:$exitcode,
          duration_ms:(($elapsed|tonumber)*1000|round)}' >"$json" || return 5
    printf '[HTTP probe 127.0.0.1:%s status=%s outcome=%s curl_exit=%s]\n' \
        "$port" "$http_code" "$outcome" "$curl_exit" >>"$diagnostics"
    [[ "$outcome" != collector_unavailable && "$outcome" != collector_error ]]
}
