#!/usr/bin/env bash
# Offline, root-free local TCP socket probe tests. Never changes firewall or WSL config.
set -euo pipefail
((EUID != 0)) || {
    echo 'Run TCP listener tests as a regular user' >&2
    exit 1
}
PROJECT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
UIR="$PROJECT/bin/uir"
T="$(mktemp -d)"
server_pid=''
cleanup() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -rf -- "$T"
}
trap cleanup EXIT
export XDG_DATA_HOME="$T/data"
mkdir -m 700 "$XDG_DATA_HOME"
"$UIR" init >/dev/null
"$UIR" incident create --id INC-811 --service host --severity low >/dev/null
# Select an unused ephemeral localhost TCP port, then leave it unbound for before.
port="$(
    python3 - <<'PY2'
import socket
with socket.socket() as s:
    s.bind(('127.0.0.1', 0))
    print(s.getsockname()[1])
PY2
)"

# Validate before any capture directories can be created.
for bad in 0 65536 '1;id' '127.0.0.1:80' ''; do
    if "$UIR" capture --incident INC-811 --phase before --listen-port "$bad" >"$T/bad.log" 2>&1; then
        echo "FAIL: accepted TCP port $bad" >&2
        exit 1
    fi
done
if "$UIR" capture --incident INC-811 --phase before --expect-address 127.0.0.1 >/dev/null 2>&1; then
    echo 'FAIL: accepted expected address without listen port' >&2
    exit 1
fi
if "$UIR" capture --incident INC-811 --phase before --listen-port "$port" --expect-address '8.8.8.8' >/dev/null 2>&1; then
    echo 'FAIL: accepted nonloopback expected address' >&2
    exit 1
fi
if "$UIR" capture --incident INC-811 --phase before --listen-port "$port" --listen-port "$port" >/dev/null 2>&1; then
    echo 'FAIL: accepted duplicate listener port' >&2
    exit 1
fi
[[ ! -e "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-811/before" ]]
printf 'PASS: invalid listener options rejected before snapshot\n'

"$UIR" capture --incident INC-811 --phase before --listen-port "$port" --expect-address 127.0.0.1 --minutes 1 >/dev/null
before="$XDG_DATA_HOME/ubuntu-irt/incidents/INC-811/before/snapshot.json"
jq -e --argjson port "$port" '.tcp_listener.port==$port and .tcp_listener.scope=="host" and .tcp_listener.state=="not_listening" and .tcp_listener.expected_address_listening==false and .collector_results.tcp.exit==0' "$before" >/dev/null
printf 'PASS: offline port captured as not listening\n'

python3 -u -m http.server "$port" --bind 127.0.0.1 --directory "$T" >"$T/http.log" 2>&1 &
server_pid=$!
ready=0
for _ in {1..50}; do
    if ss -H -lnt "( sport = :$port )" | grep -Fq "127.0.0.1:$port"; then
        ready=1
        break
    fi
    kill -0 "$server_pid" 2>/dev/null || {
        cat "$T/http.log" >&2
        exit 1
    }
    sleep 0.1
done
[[ "$ready" == 1 ]] || {
    echo 'FAIL: test socket not listening' >&2
    exit 1
}
"$UIR" capture --incident INC-811 --phase after --listen-port "$port" --expect-address 127.0.0.1 --minutes 1 >/dev/null
after="$XDG_DATA_HOME/ubuntu-irt/incidents/INC-811/after/snapshot.json"
jq -e '.tcp_listener.state=="listening" and .tcp_listener.expected_address_listening==true and .tcp_listener.addresses==["127.0.0.1"]' "$after" >/dev/null
"$UIR" compare --incident INC-811 >"$T/comparison.json"
jq -e '.tcp_target_comparable==true and .changes.tcp_expected_address_listening.before==false and .changes.tcp_expected_address_listening.after==true' "$T/comparison.json" >/dev/null
"$UIR" report --incident INC-811 >/dev/null
grep -q 'TCP port=' "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-811/report.md"
printf 'PASS: local listener recovery recorded and compared\n'

# Check a wrong loopback target, without modifying any service binding.
# shellcheck source=../../lib/validate.sh
source "$PROJECT/lib/validate.sh"
# shellcheck source=../../lib/collect_tcp.sh
source "$PROJECT/lib/collect_tcp.sh"
uir::collect::tcp "$port" 127.0.0.2 "$T/wrong.json" "$T/diagnostics.txt"
jq -e '.state=="listening" and .expected_address_listening==false and .addresses==["127.0.0.1"]' "$T/wrong.json" >/dev/null
printf 'PASS: incorrect expected binding distinguished from open port\n'

"$UIR" export --incident INC-811 --output "$T/handoff.tar.gz" >/dev/null
mkdir -m 700 "$T/unpacked"
tar -xzf "$T/handoff.tar.gz" -C "$T/unpacked"
(cd "$T/unpacked" && sha256sum -c SHA256SUMS) >"$T/hashcheck"
jq -e '.tcp_listener.addresses == ["[REDACTED_IPv4]"]' "$T/unpacked/after/snapshot.json" >/dev/null
if grep -Fq '127.0.0.1' "$T/unpacked/after/snapshot.json"; then
    echo 'FAIL: raw loopback address leaked into public snapshot' >&2
    exit 1
fi
printf 'PASS: TCP listener evidence exported, redacted and hashed\n'
printf 'All TCP listener integration checks passed.\n'
