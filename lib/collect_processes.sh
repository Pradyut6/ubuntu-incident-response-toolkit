#!/usr/bin/env bash
# Read-only top-process snapshot. ps %CPU is a lifetime average, not instantaneous use.
# Deliberately never obtains command lines, environment variables, or process arguments.

uir::collect::processes() {
    local json="$1" diagnostics="$2" now raw rows line pid cpu mem rss comm count=0 failures=0
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    raw="$(mktemp "${json}.ps.XXXXXXXX")" || return 5
    rows="$(mktemp "${json}.rows.XXXXXXXX")" || {
        rm -f -- "$raw"
        return 5
    }
    chmod 600 -- "$raw" "$rows"

    # 128 KiB file-size ceiling, 5-second deadline; no command line or argv fields.
    if ! (
        ulimit -f 256
        LC_ALL=C timeout --kill-after=1s 5s ps \
            -eo pid=,pcpu=,pmem=,rss=,comm= --sort=-pcpu >"$raw"
    ) 2>>"$diagnostics"; then
        failures=1
    else
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            read -r pid cpu mem rss comm <<<"$line"
            if [[ ! "$pid" =~ ^[0-9]{1,10}$ || ! "$cpu" =~ ^[0-9]{1,3}(\.[0-9]{1,2})?$ ||
                ! "$mem" =~ ^[0-9]{1,3}(\.[0-9]{1,2})?$ || ! "$rss" =~ ^[0-9]{1,12}$ ||
                ! "$comm" =~ ^[a-zA-Z0-9_.:+-]{1,32}$ ]]; then
                failures=1
                break
            fi
            # The short-lived ps sampler may report implausibly high lifetime CPU.
            [[ "$comm" == ps ]] && continue
            if ! jq -nc --arg name "$comm" --argjson pid "$pid" \
                --arg cpu "$cpu" --arg mem "$mem" --arg rss "$rss" \
                '{pid:$pid,command:$name,cpu_percent:($cpu|tonumber),
                  memory_percent:($mem|tonumber),rss_bytes:(($rss|tonumber)*1024)}' >>"$rows"; then
                failures=1
                break
            fi
            ((count += 1))
            if ((count >= 8)); then break; fi
        done <"$raw"
        if ((count == 0)); then failures=1; fi
    fi
    rm -f -- "$raw"
    local status=observed
    if ((failures != 0)); then status=partial; fi
    if ! jq -n --slurpfile rows "$rows" --arg time "$now" --arg status "$status" \
        --argjson count "$count" \
        '{checked_at:$time,status:$status,scope:"host_top_processes",
          cpu_metric:"ps_lifetime_average_percent_not_instantaneous",
          max_processes:8,observed_count:$count,top:$rows}' >"$json"; then
        rm -f -- "$rows"
        return 5
    fi
    rm -f -- "$rows"
    printf '[Process inspection status=%s count=%d cpu_metric=ps_lifetime_average]\n' \
        "$status" "$count" >>"$diagnostics"
    [[ "$status" == observed ]]
}
