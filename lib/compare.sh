#!/usr/bin/env bash
# Structured pre/post observations. Differences do not prove causation.

uir::compare::run() {
    local id='' dir before after tmp
    [[ $# == 2 && "$1" == --incident ]] || {
        uir::error 'usage: compare --incident INC-007'
        return 2
    }
    id="$2"
    uir::validate::incident_id "$id" || return 2
    dir="$(uir::store::locked_incident "$id")" || return $?
    for before in "$dir/before/snapshot.json" "$dir/after/snapshot.json"; do
        uir::store::private_dir "${before%/*}" || return $?
        uir::store::private_file "$before" || return $?
        jq -e --arg id "$id" 'type=="object" and .incident_id==$id and .schema_version==1' "$before" >/dev/null || return 5
    done
    before="$dir/before/snapshot.json"
    after="$dir/after/snapshot.json"
    # Explicit numeric comparisons. Journal text alone is not a stable metric.
    tmp="$(mktemp "$dir/.comparison.XXXXXXXX")" || return 5
    if ! jq -n --slurpfile a "$before" --slurpfile b "$after" \
        '{schema_version:1,incident_id:$a[0].incident_id,generated_at:(now|todateiso8601),
      warning:"Observed changes only; correlation does not establish root cause.",
      before:{captured_at:$a[0].captured_at,status:$a[0].capture_status},
      after:{captured_at:$b[0].captured_at,status:$b[0].capture_status},
      changes:{service_active:{before:$a[0].service.active_state,after:$b[0].service.active_state},
      service_load:{before:$a[0].service.load_state,after:$b[0].service.load_state},
      service_sub:{before:$a[0].service.sub_state,after:$b[0].service.sub_state},
      listening_default_ports:{before:$a[0].service.listening_default_ports,after:$b[0].service.listening_default_ports},
      memory_available_bytes:{before:$a[0].host.memory.available_bytes,after:$b[0].host.memory.available_bytes},
      root_available_bytes:{before:$a[0].host.disk.root_available_bytes,after:$b[0].host.disk.root_available_bytes},
      one_min_load:{before:$a[0].host.load.one_min,after:$b[0].host.load.one_min}}}' >"$tmp"; then
        rm -f -- "$tmp"
        return 5
    fi
    chmod 600 -- "$tmp"
    if [[ -e "$dir/comparison.json" || -L "$dir/comparison.json" ]]; then
        uir::store::private_file "$dir/comparison.json" || {
            rm -f -- "$tmp"
            return 5
        }
    fi
    mv -T -- "$tmp" "$dir/comparison.json" || return 5
    jq . "$dir/comparison.json"
}
