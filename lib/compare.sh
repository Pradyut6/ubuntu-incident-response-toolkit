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
      changes:({service_active:{before:$a[0].service.active_state,after:$b[0].service.active_state},
      service_load:{before:$a[0].service.load_state,after:$b[0].service.load_state},
      service_sub:{before:$a[0].service.sub_state,after:$b[0].service.sub_state},
      listening_default_ports:{before:$a[0].service.listening_default_ports,after:$b[0].service.listening_default_ports},
      memory_available_bytes:{before:$a[0].host.memory.available_bytes,after:$b[0].host.memory.available_bytes},
      root_available_bytes:{before:$a[0].host.disk.root_available_bytes,after:$b[0].host.disk.root_available_bytes},
      one_min_load:{before:$a[0].host.load.one_min,after:$b[0].host.load.one_min}} +
      (if ($a[0].http_probe != null or $b[0].http_probe != null) then
        {http_target:{before:($a[0].http_probe | if . == null then null else {host,port,path} end),
                      after:($b[0].http_probe | if . == null then null else {host,port,path} end)},
         http_status:{before:$a[0].http_probe.http_status,after:$b[0].http_probe.http_status},
         http_outcome:{before:$a[0].http_probe.outcome,after:$b[0].http_probe.outcome}}
       else {} end) +
      (if ($a[0].tcp_listener != null or $b[0].tcp_listener != null) then
         {tcp_target:{before:($a[0].tcp_listener | if . == null then null else {protocol,port,expected_address} end),
                      after:($b[0].tcp_listener | if . == null then null else {protocol,port,expected_address} end)},
          tcp_addresses:{before:$a[0].tcp_listener.addresses,after:$b[0].tcp_listener.addresses},
          tcp_state:{before:$a[0].tcp_listener.state,after:$b[0].tcp_listener.state},
          tcp_expected_address_listening:{before:$a[0].tcp_listener.expected_address_listening,
                                          after:$b[0].tcp_listener.expected_address_listening}}
       else {} end) +
      (if ($a[0].filesystem != null or $b[0].filesystem != null) then
        {filesystem_target:{before:$a[0].filesystem.target_sha256,after:$b[0].filesystem.target_sha256},
         filesystem_status:{before:$a[0].filesystem.status,after:$b[0].filesystem.status},
         filesystem_type:{before:$a[0].filesystem.fs_type,after:$b[0].filesystem.fs_type},
         filesystem_available_bytes:{before:$a[0].filesystem.available_bytes,after:$b[0].filesystem.available_bytes},
         filesystem_used_percent:{before:$a[0].filesystem.used_percent,after:$b[0].filesystem.used_percent},
         filesystem_inodes_available:{before:$a[0].filesystem.inodes_available,after:$b[0].filesystem.inodes_available},
         filesystem_inodes_used_percent:{before:$a[0].filesystem.inodes_used_percent,after:$b[0].filesystem.inodes_used_percent}}
       else {} end) +
      (if ($a[0].dependencies != null or $b[0].dependencies != null) then
        {dependency_outcome:{before:$a[0].dependencies.outcome,after:$b[0].dependencies.outcome},
         dependency_status:{before:$a[0].dependencies.status,after:$b[0].dependencies.status},
         dependency_required_units:{before:$a[0].dependencies.required_units,
                                    after:$b[0].dependencies.required_units}}
       else {} end) +
      (if ($a[0].processes != null or $b[0].processes != null) then
        {process_observations:{before:$a[0].processes.top,after:$b[0].processes.top},
         process_status:{before:$a[0].processes.status,after:$b[0].processes.status}}
       else {} end) +
      (if ($a[0].journal_audit != null or $b[0].journal_audit != null) then
        {journal_outcome:{before:$a[0].journal_audit.outcome,after:$b[0].journal_audit.outcome},
         journal_records_seen:{before:$a[0].journal_audit.records_seen,after:$b[0].journal_audit.records_seen},
         journal_stream_entries:{before:$a[0].journal_audit.stdout_transport_entries,
                                 after:$b[0].journal_audit.stdout_transport_entries}}
       else {} end)),
      journal_audit_comparable:(if $a[0].journal_audit == null and $b[0].journal_audit == null then null else
        ($a[0].journal_audit != null and $b[0].journal_audit != null and
         $a[0].journal_audit.unit == $b[0].journal_audit.unit and
         $a[0].journal_audit.window_minutes == $b[0].journal_audit.window_minutes and
         $a[0].journal_audit.status == "observed" and $b[0].journal_audit.status == "observed") end),
      processes_comparable:(if $a[0].processes == null and $b[0].processes == null then null
        else ($a[0].processes != null and $b[0].processes != null and
              $a[0].processes.status == "observed" and $b[0].processes.status == "observed") end),
      dependencies_target_comparable:(if ($a[0].dependencies == null and $b[0].dependencies == null) then null else
        ($a[0].dependencies != null and $b[0].dependencies != null and
         $a[0].dependencies.unit == $b[0].dependencies.unit and
         (($a[0].dependencies.required_units | map(.unit) | sort) ==
          ($b[0].dependencies.required_units | map(.unit) | sort)) and
         $a[0].dependencies.truncated == false and $b[0].dependencies.truncated == false and
         $a[0].dependencies.status == "observed" and $b[0].dependencies.status == "observed") end),
      filesystem_target_comparable:(if ($a[0].filesystem == null and $b[0].filesystem == null) then null else
        ($a[0].filesystem != null and $b[0].filesystem != null and
         $a[0].filesystem.target_sha256 == $b[0].filesystem.target_sha256 and
         $a[0].filesystem.fs_type == $b[0].filesystem.fs_type and
         $a[0].filesystem.status == "observed" and
         $b[0].filesystem.status == "observed") end),
      tcp_target_comparable:(if ($a[0].tcp_listener == null and $b[0].tcp_listener == null) then null else
        ($a[0].tcp_listener != null and $b[0].tcp_listener != null and
         $a[0].tcp_listener.protocol == $b[0].tcp_listener.protocol and
         $a[0].tcp_listener.port == $b[0].tcp_listener.port and
         $a[0].tcp_listener.expected_address == $b[0].tcp_listener.expected_address) end),
      http_target_comparable:(if ($a[0].http_probe == null and $b[0].http_probe == null) then null else
        ($a[0].http_probe != null and $b[0].http_probe != null and
         $a[0].http_probe.host == $b[0].http_probe.host and
         $a[0].http_probe.port == $b[0].http_probe.port and
         $a[0].http_probe.path == $b[0].http_probe.path) end)}' >"$tmp"; then
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
