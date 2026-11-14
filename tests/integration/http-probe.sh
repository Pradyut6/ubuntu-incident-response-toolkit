#!/usr/bin/env bash
# Offline HTTP collector acceptance: no root, no real services, no external network.
set -euo pipefail
((EUID != 0)) || {
    echo 'Run HTTP tests as a regular user' >&2
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
printf '503\n' >"$T/status"
python3 -u "$PROJECT/tests/fixtures/http_probe_server.py" "$T/port" "$T/status" >"$T/server.log" 2>&1 &
server_pid=$!
for _ in {1..50}; do
    [[ -s "$T/port" ]] && break
    kill -0 "$server_pid" 2>/dev/null || {
        cat "$T/server.log" >&2
        exit 1
    }
    sleep 0.1
done
[[ -s "$T/port" ]] || {
    echo 'FAIL: HTTP fixture not ready' >&2
    exit 1
}
port="$(cat "$T/port")"

# Exercise collector independently for all application response classes.
# shellcheck source=../../lib/validate.sh
source "$PROJECT/lib/validate.sh"
# shellcheck source=../../lib/collect_http.sh
source "$PROJECT/lib/collect_http.sh"
for code in 200 403 502 504; do
    printf '%s\n' "$code" >"$T/status"
    uir::collect::http "$port" "$T/probe.json" "$T/diagnostics.txt"
    jq -e --argjson code "$code" --arg outcome "$( ((code == 200)) && echo healthy || echo http_error)" \
        '.http_status == $code and .outcome == $outcome and .curl_exit == 0 and .duration_ms >= 0' \
        "$T/probe.json" >/dev/null
    printf 'PASS: HTTP %s preserved as observed response\n' "$code"
done

# Validate inputs before opening or creating an incident snapshot.
"$UIR" init >/dev/null
"$UIR" incident create --id INC-801 --service host --severity low >/dev/null
for bad in 0 65536 '127.0.0.1:80' '80/../../etc' '1;id' ''; do
    if "$UIR" capture --incident INC-801 --phase before --http-port "$bad" >"$T/rejected.txt" 2>&1; then
        echo "FAIL: accepted HTTP port: $bad" >&2
        exit 1
    fi
done
[[ ! -e "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-801/before" ]] || exit 1
printf 'PASS: invalid HTTP port input rejected before snapshot\n'
if "$UIR" capture --incident INC-801 --phase before --http-port "$port" --http-port "$port" >/dev/null 2>&1; then
    echo 'FAIL: duplicate HTTP flag accepted' >&2
    exit 1
fi
printf 'PASS: duplicate HTTP port option rejected\n'

# A service can be running while its endpoint returns a 5xx response.
printf '503\n' >"$T/status"
"$UIR" capture --incident INC-801 --phase before --http-port "$port" --minutes 1 >/dev/null
before="$XDG_DATA_HOME/ubuntu-irt/incidents/INC-801/before/snapshot.json"
jq -e --argjson port "$port" \
    '.http_probe.port==$port and .http_probe.http_status==503 and .http_probe.outcome=="http_error" and .collector_results.http.exit==0 and .capture_status=="complete"' \
    "$before" >/dev/null
printf '200\n' >"$T/status"
"$UIR" capture --incident INC-801 --phase after --http-port "$port" --minutes 1 >/dev/null
"$UIR" compare --incident INC-801 >"$T/comparison.json"
jq -e '.http_target_comparable == true and .changes.http_status.before==503 and .changes.http_status.after==200 and .changes.http_outcome.after=="healthy"' "$T/comparison.json" >/dev/null
"$UIR" report --incident INC-801 >/dev/null
grep -q 'HTTP 127.0.0.1:' "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-801/report.md"
if grep -R -q 'SECRET_RESPONSE_BODY_SHOULD_NEVER_BE_STORED' "$XDG_DATA_HOME/ubuntu-irt"; then
    echo 'FAIL: HTTP response body leaked into private evidence' >&2
    exit 1
fi
printf 'PASS: immutable before/after HTTP 503 -> 200 comparison and report\n'

"$UIR" export --incident INC-801 --output "$T/handoff.tar.gz" >/dev/null
mkdir -m 700 "$T/unpacked"
tar -xzf "$T/handoff.tar.gz" -C "$T/unpacked"
(cd "$T/unpacked" && sha256sum -c SHA256SUMS) >"$T/hashcheck"
if grep -R -q 'SECRET_RESPONSE_BODY_SHOULD_NEVER_BE_STORED' "$T/unpacked"; then
    echo 'FAIL: response body leaked into handoff' >&2
    exit 1
fi
printf 'PASS: HTTP evidence survived redacted export with valid manifest\n'

# Probes from different ports or absent phases must not claim a fair recovery comparison.
"$UIR" incident create --id INC-802 --service host --severity low >/dev/null
"$UIR" capture --incident INC-802 --phase before --http-port "$port" --minutes 1 >/dev/null
"$UIR" capture --incident INC-802 --phase after --minutes 1 >/dev/null
"$UIR" compare --incident INC-802 >"$T/unequal.json"
jq -e '.http_target_comparable == false and .changes.http_status.after == null' "$T/unequal.json" >/dev/null
"$UIR" report --incident INC-802 >/dev/null
grep -q 'HTTP comparison caution' "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-802/report.md"
printf 'PASS: incomplete probe pair explicitly marked not comparable\n'

# Timeout is an observation, not a crashed collector.
printf 'slow\n' >"$T/status"
uir::collect::http "$port" "$T/timeout.json" "$T/diagnostics.txt"
jq -e '.http_status==null and .outcome=="timeout" and .curl_exit==28' "$T/timeout.json" >/dev/null
printf 'PASS: bounded HTTP timeout recorded without body\n'

# A probe refused at the transport layer is not reported as HTTP 200.
kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
server_pid=''
uir::collect::http "$port" "$T/connection.json" "$T/diagnostics.txt"
jq -e '.http_status==null and (.outcome=="transport_error" or .outcome=="timeout") and .curl_exit!=0' "$T/connection.json" >/dev/null
printf 'PASS: unreachable endpoint recorded without invented HTTP status\n'
printf 'All HTTP probe integration checks passed.\n'
