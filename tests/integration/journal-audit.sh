#!/usr/bin/env bash
# Non-destructive journal metadata tests: no real service changes or unrestricted queries.
set -euo pipefail
((EUID != 0)) || {
    echo 'Run journal tests as a regular user' >&2
    exit 1
}
PROJECT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
UIR="$PROJECT/bin/uir"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
export XDG_DATA_HOME="$T/data"
export UIR_JOURNAL_TEST_LOG="$T/journal-args.txt"
mkdir -m 700 "$XDG_DATA_HOME" "$T/fakebin"
cat >"$T/fakebin/journalctl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$UIR_JOURNAL_TEST_LOG"
# Existing service collector stores messages separately; keep that fixture clean.
if [[ " $* " == *" --lines=300 "* ]]; then
    printf '%s\n' '{"_TRANSPORT":"journal","MESSAGE":"systemd metadata"}'
    exit 0
fi
case "${UIR_JOURNAL_TEST_MODE:-before}" in
before)
    printf '%s\n' '{"_TRANSPORT":"journal","MESSAGE":"SECRET_APPLICATION_TOKEN=should_not_be_retained"}' ;;
after)
    printf '%s\n' '{"_TRANSPORT":"stdout","MESSAGE":"SECRET_APPLICATION_TOKEN=should_not_be_retained"}' \
        '{"_TRANSPORT":"journal","MESSAGE":"manager started service"}' ;;
empty) : ;;
fail) echo 'no permission' >&2; exit 4 ;;
invalid) echo 'not-json' ;;
esac
STUB
chmod 700 "$T/fakebin/journalctl"
export PATH="$T/fakebin:$PATH"
"$UIR" init >/dev/null
"$UIR" incident create --id INC-851 --service uir-journal-training --severity low >/dev/null
"$UIR" incident create --id INC-852 --service host --severity low >/dev/null
"$UIR" incident create --id INC-853 --service uir-journal-training --severity low >/dev/null
"$UIR" incident create --id INC-854 --service uir-journal-training --severity low >/dev/null
"$UIR" incident create --id INC-855 --service uir-journal-training --severity low >/dev/null
if "$UIR" capture --incident INC-851 --phase before --journal-audit --journal-audit >/dev/null 2>&1; then
    echo 'FAIL: duplicate journal flag accepted' >&2
    exit 1
fi
if "$UIR" capture --incident INC-852 --phase before --journal-audit >/dev/null 2>&1; then
    echo 'FAIL: host-only journal audit accepted' >&2
    exit 1
fi
if "$UIR" capture --incident INC-851 --phase before --journal-audit 'foo' >/dev/null 2>&1; then
    echo 'FAIL: arbitrary journal argument accepted' >&2
    exit 1
fi
[[ ! -e "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-851/before" ]]
printf 'PASS: unsafe journal audit options rejected before snapshot\n'
export UIR_JOURNAL_TEST_MODE=before
"$UIR" capture --incident INC-851 --phase before --journal-audit --minutes 1 >/dev/null
first="$XDG_DATA_HOME/ubuntu-irt/incidents/INC-851/before/snapshot.json"
jq -e '.journal_audit.status=="observed" and .journal_audit.outcome=="no_stream_entries_observed" and
 .journal_audit.records_seen==1 and .journal_audit.stdout_transport_entries==0 and
 .journal_audit.record_limit==100 and .journal_audit.window_minutes==1 and
 .collector_results.journal_audit.exit==0' "$first" >/dev/null
if grep -q 'SECRET_APPLICATION_TOKEN' "$first"; then
    echo 'FAIL: message was stored' >&2
    exit 1
fi
# Validate command arguments; the underlying service collector also makes its own scoped journal request.
if grep -v -- '--unit=uir-journal-training.service' "$UIR_JOURNAL_TEST_LOG" | grep -q '.'; then
    echo 'FAIL: unscoped journal request' >&2
    exit 1
fi
printf 'PASS: systemd-only entries counted without claiming logging failure or storing messages\n'
export UIR_JOURNAL_TEST_MODE=after
"$UIR" capture --incident INC-851 --phase after --journal-audit --minutes 1 >/dev/null
"$UIR" compare --incident INC-851 >"$T/comparison.json"
jq -e '.journal_audit_comparable==true and
 .changes.journal_stream_entries.before==0 and .changes.journal_stream_entries.after==1 and
 .changes.journal_outcome.after=="stream_entries_observed"' "$T/comparison.json" >/dev/null
"$UIR" report --incident INC-851 >/dev/null
grep -Fq 'journal_audit=stream_entries_observed' "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-851/report.md"
if "$UIR" capture --incident INC-851 --phase before --journal-audit >/dev/null 2>&1; then
    echo 'FAIL: immutable snapshot overwritten' >&2
    exit 1
fi
printf 'PASS: bounded before/after journal visibility compared and immutable\n'
"$UIR" export --incident INC-851 --output "$T/handoff.tar.gz" >/dev/null
mkdir -m 700 "$T/unpacked"
tar -xzf "$T/handoff.tar.gz" -C "$T/unpacked"
(cd "$T/unpacked" && sha256sum -c SHA256SUMS) >/dev/null
jq -e '.journal_audit.stdout_transport_entries==1' "$T/unpacked/after/snapshot.json" >/dev/null
if grep -R -q 'SECRET_APPLICATION_TOKEN' "$T/unpacked"; then
    echo 'FAIL: secret appeared in handoff' >&2
    exit 1
fi
printf 'PASS: journal metadata exported with checksums and no raw messages\n'
export UIR_JOURNAL_TEST_MODE=empty
"$UIR" capture --incident INC-853 --phase before --journal-audit --minutes 1 >/dev/null
jq -e '.journal_audit.status=="observed" and .journal_audit.outcome=="no_entries_observed" and
 .journal_audit.records_seen==0' "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-853/before/snapshot.json" >/dev/null
printf 'PASS: empty journal window classified without inventing messages\n'
export UIR_JOURNAL_TEST_MODE=fail
"$UIR" capture --incident INC-854 --phase before --journal-audit --minutes 1 >/dev/null
jq -e '.journal_audit.status=="partial" and .journal_audit.outcome=="query_failed" and
 .collector_results.journal_audit.exit==1 and .capture_status=="partial"' \
    "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-854/before/snapshot.json" >/dev/null
printf 'PASS: journal query failure recorded as partial\n'
export UIR_JOURNAL_TEST_MODE=invalid
"$UIR" capture --incident INC-855 --phase before --journal-audit --minutes 1 >/dev/null
jq -e '.journal_audit.status=="partial" and .journal_audit.outcome=="invalid_journal_json" and
 .collector_results.journal_audit.exit==1' "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-855/before/snapshot.json" >/dev/null
printf 'PASS: malformed journal JSON recorded as partial\n'
printf 'All journal visibility integration checks passed.\n'
