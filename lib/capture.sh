#!/usr/bin/env bash
# Snapshot collection. One immutable before/after phase per incident.

uir::capture::run() {
    local id='' phase='' requested_service='' minutes='15' dir root service tmp status=complete
    local stage_bytes total_bytes limit_mib max_mib now host_rc=0 service_rc=0
    local have_id=0 have_phase=0 have_service=0 have_minutes=0
    while (($# > 0)); do
        case "$1" in
        --incident)
            (($# >= 2 && !have_id)) || return 2
            id="$2"
            have_id=1
            shift 2
            ;;
        --phase)
            (($# >= 2 && !have_phase)) || return 2
            phase="$2"
            have_phase=1
            shift 2
            ;;
        --service)
            (($# >= 2 && !have_service)) || return 2
            requested_service="$2"
            have_service=1
            shift 2
            ;;
        --minutes)
            (($# >= 2 && !have_minutes)) || return 2
            minutes="$2"
            have_minutes=1
            shift 2
            ;;
        *)
            uir::error "unexpected capture argument: $1"
            return 2
            ;;
        esac
    done
    if ! uir::validate::incident_id "$id" || ! uir::validate::phase "$phase" ||
        ! uir::validate::integer "$minutes" 1 60; then
        uir::error 'usage: capture --incident INC-007 --phase before|after [--service nginx] [--minutes 1..60]'
        return 2
    fi
    uir::store::require_regular_user || return $?
    uir::store::require_jq || return $?
    dir="$(uir::store::locked_incident "$id")" || return $?
    service="$(jq -r .service "$dir/incident.json")" || return 5
    if [[ -n "$requested_service" && "$requested_service" != "$service" ]]; then
        uir::error "service must match the incident record ($service)"
        return 2
    fi
    if ! uir::validate::profile "$service"; then
        uir::error 'capture requires a supported host/Nginx/SSH/uir-* training profile'
        return 2
    fi
    uir::store::lock "$dir" || return $?
    if [[ -e "$dir/$phase" || -L "$dir/$phase" ]]; then
        uir::error "$phase snapshot already exists: snapshots are immutable"
        return 5
    fi
    root="$(uir::store::root)"
    local free_bytes
    free_bytes="$(df -P -B1 "$dir" | awk 'NR==2 {print $4}')"
    if [[ ! "$free_bytes" =~ ^[0-9]+$ ]] || ((free_bytes < 32 * 1048576)); then
        uir::error 'at least 32 MiB of free filesystem space is required before capture'
        return 5
    fi
    max_mib="$(jq -r .max_storage_mib "$root/config/settings.json")"
    limit_mib="$(jq -r .capture_max_mib "$root/config/settings.json")"
    tmp="$(mktemp -d "$dir/.capture.${phase}.XXXXXXXX")" || return 5
    chmod 700 -- "$tmp"
    # Ownership of this freshly-created private directory is assured by mktemp;
    # failed collectors are recorded as partial, but no half-written stage survives.
    if ! uir::collect::host "$tmp/host.json" "$tmp/diagnostics.raw"; then host_rc=1; fi
    if ! uir::collect::service "$service" "$tmp/service.json" "$tmp/diagnostics.raw" "$tmp/journal.raw" "$minutes"; then service_rc=1; fi
    if [[ ! -s "$tmp/host.json" || ! -s "$tmp/service.json" ]]; then
        uir::error 'essential structured collector failed: no snapshot published'
        rm -rf -- "$tmp"
        return 5
    fi
    if ((host_rc != 0 || service_rc != 0)); then status=partial; fi
    # The journal may be unreadable or empty. Its absence must not be invented.
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if ! jq -n --slurpfile host "$tmp/host.json" --slurpfile service "$tmp/service.json" \
        --arg id "$id" --arg phase "$phase" --arg time "$now" --arg status "$status" \
        --argjson window "$minutes" --argjson host_rc "$host_rc" --argjson service_rc "$service_rc" \
        '{schema_version:1,incident_id:$id,phase:$phase,captured_at:$time,capture_status:$status,
        journal_window_minutes:$window,collector_results:{host:{exit:$host_rc},service:{exit:$service_rc}},
        host:$host[0],service:$service[0]}' >"$tmp/snapshot.json"; then
        uir::error 'could not serialize snapshot'
        rm -rf -- "$tmp"
        return 5
    fi
    # Keep raw diagnostics out of permanent storage: redact before compression.
    if ! uir::sanitize::local <"$tmp/diagnostics.raw" | gzip -n -9 >"$tmp/diagnostics.txt.gz" ||
        ! uir::sanitize::local <"$tmp/journal.raw" | gzip -n -9 >"$tmp/journal.jsonl.gz"; then
        uir::error 'redaction/compression failed'
        rm -rf -- "$tmp"
        return 5
    fi
    rm -f -- "$tmp/host.json" "$tmp/service.json" "$tmp/diagnostics.raw" "$tmp/journal.raw"
    stage_bytes="$(du -sb -- "$tmp" | awk '{print $1}')"
    total_bytes="$(du -sb -- "$root/incidents" | awk '{print $1}')"
    if ((stage_bytes > limit_mib * 1048576 || total_bytes > max_mib * 1048576)); then
        uir::error "capture exceeds per-capture limit ($limit_mib MiB) or store cap ($max_mib MiB)"
        rm -rf -- "$tmp"
        return 5
    fi
    chmod 600 -- "$tmp/snapshot.json" "$tmp/diagnostics.txt.gz" "$tmp/journal.jsonl.gz"
    if ! mv -T -- "$tmp" "$dir/$phase"; then
        uir::error 'could not publish snapshot'
        rm -rf -- "$tmp"
        return 5
    fi
    # Metadata update is a separate atomic write. If it fails, the snapshot
    # stays visible and reportable rather than silently disappearing.
    if ! jq --arg phase "$phase" --arg when "$now" --arg status "$status" \
        '.captures[$phase] = {captured_at:$when,status:$status} | .updated_at = $when' \
        "$dir/incident.json" | uir::store::replace_json "$dir/incident.json"; then
        uir::error 'snapshot saved, but incident index update failed; inspect manually'
        return 5
    fi
    printf 'Saved %s snapshot for %s: %s (%s)\n' "$phase" "$id" "$dir/$phase" "$status"
    [[ "$status" == complete ]] || printf 'WARNING: partial collection; inspect collector_results and diagnostic warnings.\n'
}
