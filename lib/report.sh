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
                    "; disk available="+(.host.disk.root_available_bytes|tostring)+" bytes"+
                    (if .http_probe == null then "" else
                      "; HTTP 127.0.0.1:"+(.http_probe.port|tostring)+
                      " status="+(.http_probe.http_status|tostring)+
                      " outcome="+.http_probe.outcome end)+
                    (if .tcp_listener == null then "" else
                      "; TCP port="+(.tcp_listener.port|tostring)+
                      " state="+.tcp_listener.state+
                      " addresses="+(.tcp_listener.addresses|join(","))+
                      " expected_address_listening="+(.tcp_listener.expected_address_listening|tostring) end)+
                    (if .filesystem == null then "" else
                      "; filesystem status="+.filesystem.status+
                      " type="+(.filesystem.fs_type|tostring)+
                      " available_bytes="+(.filesystem.available_bytes|tostring)+
                      " inode_free="+(.filesystem.inodes_available|tostring) end)+
                    (if .processes == null then "" else
                      "; process_sample="+.processes.status+
                      " observed="+(.processes.observed_count|tostring)+
                      " metric="+.processes.cpu_metric end)+
                    (if .journal_audit == null then "" else
                      "; journal_audit="+.journal_audit.outcome+
                      " window_minutes="+(.journal_audit.window_minutes|tostring)+
                      " entries="+(.journal_audit.records_seen|tostring)+
                      " stream_entries="+(.journal_audit.stdout_transport_entries|tostring) end)+
                    (if .dependencies == null then "" else
                      "; dependencies="+.dependencies.outcome+
                      " inspected="+(.dependencies.inspected_count|tostring)+
                      " truncated="+(.dependencies.truncated|tostring) end)' "$snapshot"
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
            if jq -e '(.changes | has("http_status")) and (.http_target_comparable == false)' "$comparison" >/dev/null; then
                printf '\n**HTTP comparison caution:** probe targets differ or only one phase was probed; status values are not directly comparable.\n'
            fi
            if jq -e '(.changes | has("tcp_state")) and (.tcp_target_comparable == false)' "$comparison" >/dev/null; then
                printf '\n**TCP comparison caution:** port or expected address differs, or only one phase was inspected.\n'
            fi
            if jq -e '(.changes | has("dependency_outcome")) and (.dependencies_target_comparable == false)' "$comparison" >/dev/null; then
                printf '\n**Dependency comparison caution:** required-unit set differs, a phase is absent or inspection was partial; do not infer recovery.\n'
            fi
            if jq -e '(.changes | has("journal_outcome")) and (.journal_audit_comparable == false)' "$comparison" >/dev/null; then
                printf '\n**Journal comparison caution:** unit, window, or visibility differs, or only one phase was inspected.\n'
            fi
            if jq -e '(.changes | has("filesystem_status")) and (.filesystem_target_comparable == false)' "$comparison" >/dev/null; then
                printf '\n**Filesystem comparison caution:** directory fingerprint or filesystem type differs, or only one phase was inspected.\n'
            fi
        else
            printf 'Not yet generated; run `uir compare --incident %s` after both captures.\n' "$id"
        fi
        if [[ -f "$comparison" && ! -L "$comparison" ]] &&
            jq -e '(.changes | has("process_observations"))' "$comparison" >/dev/null; then
            printf '\n**Process comparison caution:** process lists are separate samples; PID identities can change. ps CPU percentages are lifetime averages, not instantaneous CPU usage.\n'
        fi
        printf '\n## Collection limitations\n\n'
        printf 'Journal audit counts only unit-scoped visible entries and cannot prove an application logging failure from absence alone. Process rankings use ps lifetime-average CPU and do not prove CPU-spike causation. Filesystem metrics describe the containing mount, not necessarily usage by the selected directory. Inode values may be unavailable. TCP listener observations are host-level and cannot establish socket ownership or HTTP health. Dependency inspection covers at most eight direct Requires= units; ordering and observed states do not prove causality. Collector results may be incomplete because of Ubuntu permissions, unavailable services, WSL differences or timeouts. Examine `snapshot.json` and `diagnostics.txt.gz`. An observed improvement does not prove causality.\n\n'
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
