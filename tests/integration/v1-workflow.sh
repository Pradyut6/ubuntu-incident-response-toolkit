#!/usr/bin/env bash
# Full non-destructive acceptance test: uses isolated temporary evidence.
set -euo pipefail
((EUID != 0)) || {
    echo 'Run tests as a non-root Linux user' >&2
    exit 1
}
PROJECT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
UIR="$PROJECT/bin/uir"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
export XDG_DATA_HOME="$T/data"
mkdir -m 700 "$XDG_DATA_HOME"
pass=0
ok() {
    printf 'PASS %02d: %s\n' "$((pass + 1))" "$1"
    ((pass += 1))
}
expect_error() {
    local code="$1" label="$2" actual=0
    shift 2
    "$@" >"$T/out" 2>&1 || actual=$?
    [[ "$actual" == "$code" ]] || {
        echo "FAIL: $label expected $code got $actual"
        cat "$T/out"
        exit 1
    }
    ok "$label"
}
assert() { "$@" || {
    printf 'FAILED assertion: %s\n' "$*" >&2
    exit 1
}; }

expect_error 5 'store is not implicit' "$UIR" incident create --id INC-007 --service nginx --severity high
"$UIR" init >/dev/null
ok 'init private data store'
R="$XDG_DATA_HOME/ubuntu-irt"
[[ "$(stat -c %a "$R")" == 700 && "$(stat -c %a "$R/config/settings.json")" == 600 ]] || exit 1
ok '0700/0600 permissions'
"$UIR" incident create --id INC-007 --service nginx --severity high --summary 'Lab-only Nginx problem' >/dev/null
ok 'create incident'
expect_error 5 'duplicate protected' "$UIR" incident create --id INC-007 --service nginx --severity low
expect_error 2 'traversal rejected' "$UIR" incident create --id ../escape --service nginx --severity high
expect_error 2 'command-looking service refused' "$UIR" incident create --id INC-008 --service 'nginx;touch /tmp/uir-pwned' --severity high
"$UIR" incident note --id INC-007 --kind hypothesis --text 'Nginx might have a bad port' >/dev/null
"$UIR" incident note --id INC-007 --kind root_cause --text 'Synthetic fixture password=secret-example-123 alice@example.org' >/dev/null
"$UIR" incident status --id INC-007 --value investigating >/dev/null
[[ "$("$UIR" incident show INC-007 | jq -r .status)" == investigating ]] || exit 1
ok 'operator notes and lifecycle status persist'
"$UIR" capture --incident INC-007 --phase before --minutes 1 >"$T/out"
assert jq -e '.phase=="before" and (.capture_status=="partial" or .capture_status=="complete")' "$R/incidents/INC-007/before/snapshot.json"
ok 'bounded before capture and explicit status'
expect_error 5 'immutable phase protected' "$UIR" capture --incident INC-007 --phase before
"$UIR" capture --incident INC-007 --phase after --minutes 1 >/dev/null
ok 'bounded after capture'
assert gzip -t "$R/incidents/INC-007/before/diagnostics.txt.gz"
assert gzip -t "$R/incidents/INC-007/after/journal.jsonl.gz"
ok 'gzip integrity'
"$UIR" compare --incident INC-007 >"$T/comparison.json"
assert jq -e '.changes.service_active.before != null and .changes.root_available_bytes.after != null' "$T/comparison.json"
ok 'structured before/after comparison'
"$UIR" incident search --text 'secret-example-123' >"$T/search.txt"
assert grep -q INC-007 "$T/search.txt"
ok 'literal searchable evidence and notes'
"$UIR" report --incident INC-007 >/dev/null
assert grep -q 'Not recorded' "$R/incidents/INC-007/report.md"
ok 'readable report does not invent conclusions'
"$UIR" export --incident INC-007 --preview >"$T/preview.txt"
[[ ! -e "$T/handoff.tar.gz" ]] || exit 1
ok 'export preview has no archive side effect'
"$UIR" export --incident INC-007 --output "$T/handoff.tar.gz" >/dev/null
assert tar -tzf "$T/handoff.tar.gz"
ok 'portable tar.gz generated'
mkdir -m 700 "$T/unpacked"
tar -xzf "$T/handoff.tar.gz" -C "$T/unpacked"
(cd "$T/unpacked" && sha256sum -c SHA256SUMS) >"$T/hashcheck"
ok 'handoff hashes independently verified'
if grep -R -F 'secret-example-123' "$T/unpacked" >/dev/null ||
    grep -R -F 'alice@example.org' "$T/unpacked" >/dev/null; then
    echo 'FAIL: seeded secret or email in export'
    exit 1
fi
ok 'seeded note secret + email removed from archive'
if find "$T/unpacked" -type l | grep -q . || tar -tf "$T/handoff.tar.gz" | grep -E '^/|\.\./'; then
    echo 'FAIL: archive includes symlink or traversal'
    exit 1
fi
ok 'archive path and symlink safety'
expect_error 5 'export overwrite refused' "$UIR" export --incident INC-007 --output "$T/handoff.tar.gz"
"$UIR" incident create --id INC-009 --service host --severity medium --summary 'CPU training observation' >/dev/null
"$UIR" capture --incident INC-009 --phase before --minutes 1 >/dev/null
jq -e '.service.unit=="host" and .service.active_state=="not_applicable" and .collector_results.service.exit==0' "$R/incidents/INC-009/before/snapshot.json" >/dev/null || exit 1
ok 'host-only collector never runs an unrestricted journal query'
"$UIR" retention set --days 1 --max-storage-mb 100 --capture-max-mb 5 >/dev/null
[[ "$("$UIR" retention status | jq -r .capture_max_mib)" == 5 ]] || exit 1
ok 'validated retention settings'
"$UIR" incident create --id INC-008 --service nginx --severity low >/dev/null
# Controlled fixture mutation: create an expired record for prune tests only.
file="$R/incidents/INC-008/incident.json"
jq '.created_at="2020-01-01T00:00:00Z"' "$file" >"$T/edit.json" && cp "$T/edit.json" "$file"
"$UIR" retention prune --dry-run >"$T/prune-preview.txt"
assert grep -q INC-008 "$T/prune-preview.txt"
[[ -d "$R/incidents/INC-008" ]] || exit 1
ok 'dry-run never deletes evidence'
"$UIR" retention prune --yes >"$T/prune-live.txt"
[[ ! -e "$R/incidents/INC-008" && -d "$R/incidents/INC-007" ]] || exit 1
ok 'explicit prune removes only expired record'
# A real diagnostic excerpt can compress to far more than 64 KiB; it must
# still be accepted within the configured per-capture evidence limits.
diag="$R/incidents/INC-007/before/diagnostics.txt.gz"
cp "$diag" "$T/diag-original.gz"
head -c 170000 /dev/urandom | base64 | gzip -n >"$diag"
[[ "$(stat -c %s "$diag")" -gt 65536 ]] || {
    echo 'FAIL: large gzip fixture too small'
    exit 1
}
"$UIR" export --incident INC-007 --preview >"$T/large-preview"
"$UIR" export --incident INC-007 --output "$T/large-evidence.tar.gz" >"$T/large-export"
cp "$T/diag-original.gz" "$diag"
ok 'compressed evidence larger than 64 KiB exports successfully'
# Corrupt gzip must not be exported, then restore it for clean test exit.
cp "$R/incidents/INC-007/before/journal.jsonl.gz" "$T/good.gz"
printf 'not gzip' >"$R/incidents/INC-007/before/journal.jsonl.gz"
expect_error 5 'corrupted gzip evidence rejected' "$UIR" export --incident INC-007 --preview
cp "$T/good.gz" "$R/incidents/INC-007/before/journal.jsonl.gz"
# Refuse tampered storage perms.
chmod 755 "$R"
expect_error 5 'unsafe permissions rejected' "$UIR" incident list
chmod 700 "$R"
printf '\n%d end-to-end integration checks passed.\n' "$pass"
