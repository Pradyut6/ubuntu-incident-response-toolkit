#!/usr/bin/env bash
# Root-free portable M3 acceptance checks; uses a new temporary data directory.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
UIR="$ROOT/bin/uir"
if ((EUID == 0)); then
    printf 'Run M3 store checks as a regular user, not root.\n' >&2
    exit 1
fi
for cmd in jq stat mktemp sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf 'Missing test dependency: %s\n' "$cmd" >&2
        exit 1
    }
done
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
export XDG_DATA_HOME="$WORK"
passes=0
pass() {
    printf 'PASS: %s\n' "$1"
    ((passes += 1))
}
expect_status() {
    local name="$1" expected="$2" actual=0
    shift 2
    "$@" >"$WORK/out" 2>&1 || actual=$?
    if ((actual != expected)); then
        printf 'FAIL: %s expected exit=%s got exit=%s\n' "$name" "$expected" "$actual" >&2
        cat "$WORK/out" >&2
        exit 1
    fi
    pass "$name"
}

expect_status 'reject create before init' 5 "$UIR" incident create --id INC-007 --service nginx --severity high
[[ ! -e "$WORK/ubuntu-irt" ]] || {
    printf 'Unexpected data directory\n' >&2
    exit 1
}
expect_status 'init creates private store' 0 "$UIR" init
[[ "$(stat -c '%a' "$WORK/ubuntu-irt")" == 700 && "$(stat -c '%a' "$WORK/ubuntu-irt/config/settings.json")" == 600 ]] || exit 1
pass 'store permissions 0700 and settings 0600'
expect_status 'init is idempotent' 0 "$UIR" init
expect_status 'create incident' 0 "$UIR" incident create --id INC-007 --service nginx --severity high --summary 'Nginx down'
[[ "$(stat -c '%a' "$WORK/ubuntu-irt/incidents/INC-007/incident.json")" == 600 ]] || exit 1
pass 'incident metadata file 0600'
expect_status 'list persisted record' 0 "$UIR" incident list
grep -q 'INC-007' "$WORK/out" || exit 1
expect_status 'show persisted JSON' 0 "$UIR" incident show INC-007
jq -e '.incident_id == "INC-007" and .service == "nginx"' "$WORK/out" >/dev/null
pass 'metadata content matches input'
original="$(sha256sum "$WORK/ubuntu-irt/incidents/INC-007/incident.json")"
expect_status 'refuse duplicate ID' 5 "$UIR" incident create --id INC-007 --service ssh --severity low
[[ "$original" == "$(sha256sum "$WORK/ubuntu-irt/incidents/INC-007/incident.json")" ]] || exit 1
pass 'duplicate attempt preserves original file'
expect_status 'reject traversal ID' 2 "$UIR" incident create --id ../escape --service nginx --severity high
expect_status 'reject command in service' 2 "$UIR" incident create --id INC-008 --service "\$(touch $WORK/pwned)" --severity high
[[ ! -e "$WORK/pwned" ]] || exit 1
pass 'injected command never executed'
expect_status 'reject unexpected init arguments' 2 "$UIR" init --unexpected
expect_status 'reject invalid severity' 2 "$UIR" incident create --id INC-008 --service nginx --severity huge
mkdir "$WORK/target"
ln -s "$WORK/target" "$WORK/ubuntu-irt/incidents/INC-008"
expect_status 'reject symlinked incident directory' 5 "$UIR" incident create --id INC-008 --service nginx --severity low
[[ ! -e "$WORK/target/incident.json" ]] || exit 1
pass 'symlink target unchanged'
chmod 755 "$WORK/ubuntu-irt"
expect_status 'refuse insecure directory mode' 5 "$UIR" incident list
chmod 700 "$WORK/ubuntu-irt"
printf '{broken\n' >"$WORK/ubuntu-irt/incidents/INC-007/incident.json"
expect_status 'detect corrupted metadata' 5 "$UIR" incident show INC-007

printf '\nAll %d M3 storage integration checks passed.\n' "$passes"
