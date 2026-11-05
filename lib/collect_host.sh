#!/usr/bin/env bash
# Bounded host observations: each command has a time and file-size limit.
# Outputs are evidence, not a remediation action.

uir::collect::run() {
    local label="$1" out="$2"
    shift 2
    local status=0
    printf '\n--- %s [UTC %s] ---\n' "$label" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$out"
    # 10 seconds and 1 MiB file-size ceiling per subprocess.
    (
        ulimit -f 2048
        timeout 10s "$@"
    ) >>"$out" 2>&1 || status=$?
    printf '[%s exit=%s]\n' "$label" "$status" >>"$out"
    return "$status"
}

uir::collect::host() {
    local target="$1" diagnostics="$2" ts uname_value os_id osver hostid load1 load5 load15
    local mem_kib disk_avail disk_size inode_avail inode_total uptime_sec ip_out route_out status=0
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    uname_value="$(uname -r)"
    os_id="$(grep -E '^ID=' /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"')"
    osver="$(grep -E '^VERSION_ID=' /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"')"
    hostid="$(hostname | sha256sum | cut -c 1-12)"
    read -r load1 load5 load15 _ </proc/loadavg || return 5
    mem_kib="$(awk '$1=="MemAvailable:" {print $2}' /proc/meminfo)"
    disk_avail="$(df -P -B1 / | awk 'NR==2{print $4}')"
    disk_size="$(df -P -B1 / | awk 'NR==2{print $2}')"
    inode_avail="$(df -Pi / | awk 'NR==2{print $4}')"
    inode_total="$(df -Pi / | awk 'NR==2{print $2}')"
    uptime_sec="$(awk '{print int($1)}' /proc/uptime)"
    # IPs remain inside the private store; public exports are pseudonymized.
    ip_out="$(timeout 5s ip -brief addr 2>&1 | head -c 4000)" || ip_out='unavailable'
    route_out="$(timeout 5s ip route show 2>&1 | head -c 4000)" || route_out='unavailable'
    jq -n --arg ts "$ts" --arg host "$hostid" --arg os "$os_id" --arg ver "$osver" \
        --arg kernel "$uname_value" --arg ip "$ip_out" --arg route "$route_out" \
        --arg l1 "$load1" --arg l5 "$load5" --arg l15 "$load15" \
        --arg mem "$mem_kib" --arg dav "$disk_avail" --arg dsize "$disk_size" \
        --arg iav "$inode_avail" --arg isize "$inode_total" --arg uptime "$uptime_sec" \
        '{timestamp_utc:$ts,host_pseudonym:$host,os:{id:$os,version:$ver,kernel:$kernel},
      load:{one_min:($l1|tonumber),five_min:($l5|tonumber),fifteen_min:($l15|tonumber)},
      memory:{available_bytes:(($mem|tonumber)*1024)},
      disk:{root_available_bytes:($dav|tonumber),root_size_bytes:($dsize|tonumber),
      root_inodes_available:($iav|tonumber),root_inodes_total:($isize|tonumber)},
      uptime_seconds:($uptime|tonumber),network:{interfaces:$ip,routes:$route}}' >"$target"
    uir::collect::run 'uptime' "$diagnostics" uptime || status=1
    uir::collect::run 'free -b' "$diagnostics" free -b || status=1
    uir::collect::run 'df -P -B1 /' "$diagnostics" df -P -B1 / || status=1
    uir::collect::run 'df -Pi /' "$diagnostics" df -Pi / || status=1
    uir::collect::run 'ip -brief addr' "$diagnostics" ip -brief addr || status=1
    uir::collect::run 'ip route' "$diagnostics" ip route show || status=1
    uir::collect::run 'ss -lnt' "$diagnostics" ss -lnt || status=1
    return "$status"
}
