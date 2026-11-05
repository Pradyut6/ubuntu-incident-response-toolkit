#!/usr/bin/env bash
# Portable smoke checks for development environments without Bats.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CLI="$ROOT/bin/uir"
passes=0

check() {
    local name="$1" expected="$2" match="$3" actual output
    shift 3
    actual=0
    output="$("$CLI" "$@" 2>&1)" || actual=$?
    if [[ "$actual" != "$expected" || "$output" != *"$match"* ]]; then
        printf 'FAIL: %s\n  wanted status=%s and substring=%q\n  got status=%s\n  output: %s\n' \
            "$name" "$expected" "$match" "$actual" "$output" >&2
        exit 1
    fi
    printf 'PASS: %s\n' "$name"
    ((passes += 1))
}

check 'help' 0 'Usage:' --help
check 'default help' 0 'Usage:'
check 'version' 0 'uir 1.0.0-rc1' --version
check 'unknown command' 2 'unknown command' totally-unknown
check 'capture requires arguments' 2 'usage: capture' capture
check 'reject unexpected doctor args' 2 'does not accept arguments' doctor --other
check 'reject unexpected version args' 2 'does not accept arguments' --version extra

# Runs on non-Ubuntu too: it must print a diagnostic rather than crash.
doctor_exit=0
doctor_output="$("$CLI" doctor 2>&1)" || doctor_exit=$?
if [[ "$doctor_exit" != 0 && "$doctor_exit" != 3 ]]; then
    printf 'FAIL: doctor exited unexpectedly with %s\n%s\n' "$doctor_exit" "$doctor_output" >&2
    exit 1
fi
if [[ "$doctor_output" != *'Summary:'* || "$doctor_output" != *'journal-access'* && "$doctor_output" != *'[FAIL] journalctl'* ]]; then
    printf 'FAIL: doctor result missing expected checks\n%s\n' "$doctor_output" >&2
    exit 1
fi
printf 'PASS: doctor emits a summary and journal check (status=%s)\n' "$doctor_exit"
((passes += 1))

# Essential dependency failure path: a constrained PATH with only the Bash executable.
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
ln -s -- "$(command -v bash)" "$work/bash"
ln -s -- "$(command -v dirname)" "$work/dirname"
missing_exit=0
missing_output="$(PATH="$work" "$CLI" doctor 2>&1)" || missing_exit=$?
if [[ "$missing_exit" != 3 || "$missing_output" != *'[FAIL] jq'* ]]; then
    printf 'FAIL: simulated dependency failure was not detected\n%s\n' "$missing_output" >&2
    exit 1
fi
printf 'PASS: doctor detects missing required programs\n'
((passes += 1))

# Hostile command text must be treated as data, not executable shell.
attack="\$(touch $work/uir-should-not-run)"
check 'shell-like command rejected' 2 'unknown command' "$attack"
if [[ -e "$work/uir-should-not-run" ]]; then
    printf 'FAIL: shell-like command caused side effects\n' >&2
    exit 1
fi

# Preflight must not initialize state or create evidence directories.
new_home="$work/absent-home"
HOME="$new_home" "$CLI" doctor >/dev/null 2>&1 || {
    status=$?
    if ((status != 3)); then
        printf 'FAIL: doctor returned unexpected status %s\n' "$status" >&2
        exit 1
    fi
}
if [[ -e "$new_home" ]]; then
    printf 'FAIL: doctor created persistent state in HOME\n' >&2
    exit 1
fi
printf 'PASS: doctor creates no HOME state\n'
((passes += 1))

printf '\nAll %s portable smoke checks passed.\n' "$passes"
