#!/usr/bin/env bash
# Root-free, offline process sample verification using a PATH-local ps fixture.
set -euo pipefail
((EUID != 0)) || {
    echo 'Run process tests as a regular user' >&2
    exit 1
}
PROJECT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
UIR="$PROJECT/bin/uir"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
export XDG_DATA_HOME="$T/data"
mkdir -m 700 "$XDG_DATA_HOME" "$T/fakebin"
export UIR_PROCESS_TEST_ARGS="$T/ps-args.txt"
cat >"$T/fakebin/ps" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"$UIR_PROCESS_TEST_ARGS"
[[ "$*" == '-eo pid=,pcpu=,pmem=,rss=,comm= --sort=-pcpu' ]] || exit 4
case "${UIR_PROCESS_TEST_MODE:-before}" in
fail) exit 7 ;;
after)
    printf '%s\n' '234 1.2 0.4 2048 python3' '123 0.5 0.2 1024 nginx' ;;
bad)
    printf '%s\n' '123 99.0 0.2 1024 secret;argument' ;;
*)
    printf '%s\n' '999 800.0 0.0 2000 ps' '234 50.5 0.4 2048 python3' '123 12.2 0.2 1024 nginx' \
        '345 5.0 0.1 500 bash' '346 4.0 0.1 500 bash' '347 3.0 0.1 500 bash' \
        '348 2.0 0.1 500 bash' '349 1.0 0.1 500 bash' '350 0.5 0.1 500 bash' \
        '351 0.3 0.1 500 bash' ;;
esac
STUB
chmod 700 "$T/fakebin/ps"
export PATH="$T/fakebin:$PATH"
"$UIR" init >/dev/null
"$UIR" incident create --id INC-841 --service host --severity low >/dev/null
"$UIR" incident create --id INC-842 --service host --severity low >/dev/null
"$UIR" incident create --id INC-843 --service host --severity low >/dev/null

if "$UIR" capture --incident INC-841 --phase before --processes --processes >"$T/reject" 2>&1; then
    echo 'FAIL: duplicate process flag accepted' >&2
    exit 1
fi
if "$UIR" capture --incident INC-841 --phase before --processes malicious >"$T/reject" 2>&1; then
    echo 'FAIL: unexpected process argument accepted' >&2
    exit 1
fi
[[ ! -e "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-841/before" ]]
printf 'PASS: duplicate/unsafe process flags rejected before snapshot\n'

export UIR_PROCESS_TEST_MODE=before
"$UIR" capture --incident INC-841 --phase before --processes --minutes 1 >/dev/null
before="$XDG_DATA_HOME/ubuntu-irt/incidents/INC-841/before/snapshot.json"
jq -e '.capture_status=="complete" and .collector_results.processes.exit==0 and
  .processes.status=="observed" and .processes.observed_count==8 and
  (.processes.top | all(.command != "ps")) and .processes.top[0].command=="python3" and .processes.top[0].cpu_percent==50.5 and
  .processes.top[0].rss_bytes==2097152 and .processes.cpu_metric=="ps_lifetime_average_percent_not_instantaneous"' "$before" >/dev/null
if grep -Eq -- 'args=|cmdline|command=' "$UIR_PROCESS_TEST_ARGS"; then
    echo 'FAIL: process command-line arguments requested' >&2
    exit 1
fi
printf 'PASS: top eight processes sampled without command lines or arguments\n'

export UIR_PROCESS_TEST_MODE=after
"$UIR" capture --incident INC-841 --phase after --processes --minutes 1 >/dev/null
"$UIR" compare --incident INC-841 >"$T/comparison.json"
jq -e '.processes_comparable==true and .changes.process_observations.before[0].cpu_percent==50.5 and
 .changes.process_observations.after[0].cpu_percent==1.2' "$T/comparison.json" >/dev/null
"$UIR" report --incident INC-841 >/dev/null
grep -Fq 'ps lifetime-average CPU' "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-841/report.md"
if "$UIR" capture --incident INC-841 --phase before --processes >/dev/null 2>&1; then
    echo 'FAIL: immutable process snapshot overwritten' >&2
    exit 1
fi
printf 'PASS: independent process samples compared with explicit causality caution\n'

"$UIR" capture --incident INC-842 --phase before --processes --minutes 1 >/dev/null
"$UIR" capture --incident INC-842 --phase after --minutes 1 >/dev/null
"$UIR" compare --incident INC-842 >"$T/mismatch.json"
jq -e '.processes_comparable==false and .changes.process_status.after==null' "$T/mismatch.json" >/dev/null
printf 'PASS: unmatched process samples marked not comparable\n'

"$UIR" export --incident INC-841 --output "$T/handoff.tar.gz" >/dev/null
mkdir -m 700 "$T/unpacked"
tar -xzf "$T/handoff.tar.gz" -C "$T/unpacked"
(cd "$T/unpacked" && sha256sum -c SHA256SUMS) >"$T/hashes"
jq -e '.processes.top[0].command=="python3"' "$T/unpacked/before/snapshot.json" >/dev/null
printf 'PASS: process metadata exported and hashes verified\n'

export UIR_PROCESS_TEST_MODE=fail
"$UIR" capture --incident INC-843 --phase before --processes --minutes 1 >/dev/null
jq -e '.capture_status=="partial" and .collector_results.processes.exit==1 and
 .processes.status=="partial" and .processes.observed_count==0 and (.processes.top|length)==0' \
    "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-843/before/snapshot.json" >/dev/null
printf 'PASS: failed process command recorded as partial, without invented observations\n'
printf 'All process inspection integration checks passed.\n'
