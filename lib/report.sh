#!/usr/bin/env bash
# Human-readable handoff from recorded observations and operator-authored notes.
uir::report::write() {
    local dir="$1" output="$2" meta id service summary severity status created
    meta="$dir/incident.json"
    local kind note phase snapshot comparison
    id="$(jq -r .incident_id "$meta")"
    service="$(jq -r .service "$meta")"
    summary="$(jq -r .summary "$meta")"
    severity="$(jq -r .severity "$meta")"
    status="$(jq -r .status "$meta")"
    created="$(jq -r .created_at "$meta")"
    {
        printf '# Incident %s — %s\n\n' "$id" "$summary"
        printf '> **Simulated lab incident or operator-created record.** The toolkit does not assert that a customer outage occurred.\n\n'
        printf '| Attribute | Value |\n| --- | --- |\n'
        printf '| Service | `%s` |\n| Severity | %s |\n| Status | %s |\n| Created (UTC) | %s |\n\n' \
            "$service" "$severity" "$status" "$created"
        printf '## Evidence timeline\n\n'
        for phase in before after; do
            snapshot="$dir/$phase/snapshot.json"
            if [[ -f "$snapshot" && ! -L "$snapshot" ]]; then
                jq -r --arg phase "$phase" \
                    '"- **"+$phase+"** ("+.captured_at+"): "+.capture_status+
                    "; service="+.service.active_state+" / "+.service.sub_state+
                    "; load="+(.host.load.one_min|tostring)+
                    "; disk available="+(.host.disk.root_available_bytes|tostring)+" bytes"' "$snapshot"
            else
                printf -- '- **%s:** no snapshot recorded\n' "$phase"
            fi
        done
        printf '\n## Operator notes and assessment\n\n'
        for kind in hypothesis root_cause remediation verification customer_update; do
            printf '### %s\n\n' "${kind//_/ }"
            note="$(jq -r --arg kind "$kind" '.notes[] | select(.kind == $kind) | "- ["+.at+"] "+.text' "$meta")"
            if [[ -n "$note" ]]; then printf '%s\n' "$note"; else printf '*Not recorded. Do not infer a root cause from service state alone.*\n'; fi
            printf '\n'
        done
        comparison="$dir/comparison.json"
        printf '## Before / after comparison\n\n'
        if [[ -f "$comparison" && ! -L "$comparison" ]]; then
            jq -r '.changes | to_entries[] | "- **"+.key+"**: "+(.value.before|tojson)+" → "+(.value.after|tojson)' "$comparison"
        else
            printf 'Not yet generated; run `uir compare --incident %s` after both captures.\n' "$id"
        fi
        printf '\n## Collection limitations\n\n'
        printf 'Collector results may be incomplete because of Ubuntu permissions, unavailable services, WSL differences or timeouts. Examine `snapshot.json` and `diagnostics.txt.gz`. An observed improvement does not prove causality.\n\n'
        printf '## Handoff and privacy\n\n'
        printf 'This report contains operator-entered text and may contain sensitive values. Treat it as private until the export sanitizer has run **and a human has inspected the archive**.\n'
    } >"$output"
}

uir::report::run() {
    [[ $# == 2 && "$1" == --incident ]] || {
        uir::error 'usage: report --incident INC-007'
        return 2
    }
    local id="$2" dir tmp
    uir::validate::incident_id "$id" || return 2
    dir="$(uir::store::locked_incident "$id")" || return $?
    uir::store::lock "$dir" || return $?
    tmp="$(mktemp "$dir/.report.XXXXXXXX")" || return 5
    if ! uir::report::write "$dir" "$tmp"; then
        rm -f -- "$tmp"
        return 5
    fi
    chmod 600 -- "$tmp"
    if [[ -e "$dir/report.md" || -L "$dir/report.md" ]]; then
        uir::store::private_file "$dir/report.md" || {
            rm -f -- "$tmp"
            return 5
        }
    fi
    mv -T -- "$tmp" "$dir/report.md" || return 5
    printf 'Saved report: %s\n' "$dir/report.md"
}
