#!/usr/bin/env bash
# Opt-in, bounded journal visibility metadata. Never persists MESSAGE or argv.
# An absence of stream entries is not proof that application logging is broken.

uir::collect::journal_audit() {
    local service="$1" minutes="$2" json="$3" diagnostics="$4"
    local unit="$service" now status=observed outcome=unknown rc=0
    local raw err summary records=0 streams=0 others=0
    if ! uir::validate::profile "$service" || [[ "$service" == host ]] ||
        ! uir::validate::integer "$minutes" 1 60; then
        return 2
    fi
    if [[ "$unit" != *.service && "$unit" != *.socket ]]; then unit+='.service'; fi
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    raw="$(mktemp "${json}.journal.XXXXXXXX")" || return 5
    err="$(mktemp "${json}.stderr.XXXXXXXX")" || {
        rm -f -- "$raw"
        return 5
    }
    summary="$(mktemp "${json}.summary.XXXXXXXX")" || {
        rm -f -- "$raw" "$err"
        return 5
    }
    chmod 600 -- "$raw" "$err" "$summary"
    # Limited to 100 records in the requested window, 12 seconds and 1 MiB output.
    # A unit-scoped query only. No unrestricted host journal is queried.
    if ! (
        ulimit -f 1024
        timeout --kill-after=1s 12s journalctl \
            --no-pager --output=json --unit="$unit" \
            --since="${minutes} minutes ago" --lines=100 --quiet >"$raw" 2>"$err"
    ); then
        rc=1
        status=partial
        outcome=query_failed
    elif [[ -s "$err" ]]; then
        rc=1
        status=partial
        outcome=visibility_limited
    fi
    if ((rc == 0)); then
        if jq -s '{records:length,streams:([.[]|select(._TRANSPORT == "stdout")]|length)}' \
            "$raw" >"$summary" 2>/dev/null &&
            jq -e '.records >= 0 and .records <= 100 and .streams >= 0 and .streams <= .records' \
                "$summary" >/dev/null; then
            records="$(jq -r '.records' "$summary")"
            streams="$(jq -r '.streams' "$summary")"
            others=$((records - streams))
            if ((records == 0)); then
                outcome=no_entries_observed
            elif ((streams == 0)); then
                outcome=no_stream_entries_observed
            else
                outcome=stream_entries_observed
            fi
        else
            rc=1
            status=partial
            outcome=invalid_journal_json
        fi
    fi
    # No raw journal message, identifier, path, PID or stderr enters JSON or diagnostics.
    if ! jq -n --arg time "$now" --arg unit "$unit" \
        --arg status "$status" --arg outcome "$outcome" \
        --argjson window "$minutes" --argjson records "$records" \
        --argjson streams "$streams" --argjson others "$others" \
        '{checked_at:$time,unit:$unit,status:$status,outcome:$outcome,
          window_minutes:$window,record_limit:100,records_seen:$records,
          stdout_transport_entries:$streams,other_transport_entries:$others,
          scope:"unit_scoped_metadata_only",
          caution:"No stream entries observed does not prove a logging failure; journal permissions and application behavior affect visibility."}' \
        >"$json"; then
        rm -f -- "$raw" "$err" "$summary"
        return 5
    fi
    printf '[Journal audit status=%s outcome=%s records=%s stream_entries=%s]\n' \
        "$status" "$outcome" "$records" "$streams" >>"$diagnostics"
    rm -f -- "$raw" "$err" "$summary"
    return "$rc"
}
