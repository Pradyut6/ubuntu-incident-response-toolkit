#!/usr/bin/env bash
# Root-free systemd dependency tests, using a PATH-local systemctl fixture.
set -euo pipefail
((EUID != 0)) || {
    echo 'Run dependency tests as a regular user' >&2
    exit 1
}
PROJECT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
UIR="$PROJECT/bin/uir"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
export XDG_DATA_HOME="$T/data"
mkdir -m 700 "$XDG_DATA_HOME" "$T/fakebin"
cat >"$T/fakebin/systemctl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1-}" == show && $# -ge 2 ]] || exit 4
unit="$2"
shift 2
property='' value_only=0
while (($#)); do
    case "$1" in
    -p) property="${property:+$property,}$2"; shift 2 ;;
    --property=*) property="${1#--property=}"; shift ;;
    --value) value_only=1; shift ;;
    *) exit 4 ;;
    esac
done
IFS=',' read -r -a props <<< "$property"
for p in "${props[@]}"; do
    case "$p" in
    Requires)
        case "${UIR_DEP_FIXTURE_STATE:-failed}" in
        real_units) data='sysinit.target system.slice' ;;
        unsafe) data='uir-training-012-dependency.service --inject.service' ;;
        many) data='uir-a.service uir-b.service uir-c.service uir-d.service uir-e.service uir-f.service uir-g.service uir-h.service uir-i.service uir-j.service' ;;
        none) data='' ;;
        *) data='uir-training-012-dependency.service' ;;
        esac ;;
    After) data='uir-training-012-dependency.service basic.target' ;;
    LoadState) data=loaded ;;
    ActiveState)
        if [[ "$unit" == uir-training-012-app.service ]]; then
            if [[ "${UIR_DEP_FIXTURE_STATE:-failed}" == healthy ]]; then data=active; else data=inactive; fi
        elif [[ "${UIR_DEP_FIXTURE_STATE:-failed}" == failed && "$unit" == uir-training-012-dependency.service ]]; then
            data=failed
        else
            data=active
        fi ;;
    SubState)
        if [[ "$unit" == uir-training-012-app.service ]]; then
            if [[ "${UIR_DEP_FIXTURE_STATE:-failed}" == healthy ]]; then data=running; else data=dead; fi
        elif [[ "${UIR_DEP_FIXTURE_STATE:-failed}" == failed && "$unit" == uir-training-012-dependency.service ]]; then
            data=failed
        else
            data=exited
        fi ;;
    Result)
        # Real target/slice units may not expose a Result property.
        if [[ "${UIR_DEP_FIXTURE_STATE:-failed}" == real_units && "$unit" != *.service ]]; then continue; fi
        if [[ "$unit" == uir-training-012-dependency.service && "${UIR_DEP_FIXTURE_STATE:-failed}" == failed ]]; then data=exit-code; else data=success; fi ;;
    FragmentPath) data=/etc/systemd/system/uir-training-012-app.service ;;
    ActiveEnterTimestamp) data='' ;;
    Id) data="$unit" ;;
    *) data='' ;;
    esac
    if ((value_only)); then printf '%s\n' "$data"; else printf '%s=%s\n' "$p" "$data"; fi
done
STUB
chmod 700 "$T/fakebin/systemctl"
export PATH="$T/fakebin:$PATH"
"$UIR" init >/dev/null
"$UIR" incident create --id INC-831 --service uir-training-012-app --severity medium >/dev/null
"$UIR" incident create --id INC-832 --service host --severity low >/dev/null

# Disallow host-only dependency inspection, duplicate options and unexpected args.
if "$UIR" capture --incident INC-832 --phase before --dependencies >"$T/reject" 2>&1; then
    echo 'FAIL: host dependency inspection accepted' >&2
    exit 1
fi
if "$UIR" capture --incident INC-831 --phase before --dependencies --dependencies >"$T/reject" 2>&1; then
    echo 'FAIL: duplicate option accepted' >&2
    exit 1
fi
[[ ! -e "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-831/before" ]]
printf 'PASS: unsafe dependency CLI options rejected before snapshot\n'

export UIR_DEP_FIXTURE_STATE=failed
"$UIR" capture --incident INC-831 --phase before --dependencies --minutes 1 >/dev/null
before="$XDG_DATA_HOME/ubuntu-irt/incidents/INC-831/before/snapshot.json"
jq -e '.capture_status=="complete" and .collector_results.dependencies.exit==0 and
  .dependencies.status=="observed" and .dependencies.outcome=="dependency_failed" and
  .dependencies.required_units[0].unit=="uir-training-012-dependency.service" and
  .dependencies.required_units[0].active_state=="failed" and
  .dependencies.required_units[0].ordered_after==true' "$before" >/dev/null
printf 'PASS: failed required service recorded with ordering relationship\n'

export UIR_DEP_FIXTURE_STATE=healthy
"$UIR" capture --incident INC-831 --phase after --dependencies --minutes 1 >/dev/null
"$UIR" compare --incident INC-831 >"$T/comparison.json"
jq -e '.dependencies_target_comparable==true and
    .changes.dependency_outcome.before=="dependency_failed" and
    .changes.dependency_outcome.after=="all_active" and
    .changes.service_active.before=="inactive" and
    .changes.service_active.after=="active"' "$T/comparison.json" >/dev/null
"$UIR" report --incident INC-831 >/dev/null
grep -Fq 'dependencies=all_active' "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-831/report.md"
if "$UIR" capture --incident INC-831 --phase before --dependencies >/dev/null 2>&1; then
    echo 'FAIL: immutable dependency snapshot overwritten' >&2
    exit 1
fi
printf 'PASS: dependency before/after recovery, report and snapshot immutability\n'

"$UIR" export --incident INC-831 --output "$T/handoff.tar.gz" >/dev/null
mkdir -m 700 "$T/unpacked"
tar -xzf "$T/handoff.tar.gz" -C "$T/unpacked"
(cd "$T/unpacked" && sha256sum -c SHA256SUMS) >"$T/hashcheck"
jq -e '.dependencies.outcome=="all_active"' "$T/unpacked/after/snapshot.json" >/dev/null
printf 'PASS: dependency observations survive sanitized, hashed export\n'

# Exercise the collector separately against hostile/oversized Requires= data.
# shellcheck source=../../lib/validate.sh
source "$PROJECT/lib/validate.sh"
# shellcheck source=../../lib/collect_dependencies.sh
source "$PROJECT/lib/collect_dependencies.sh"
export UIR_DEP_FIXTURE_STATE=unsafe
if uir::collect::dependencies uir-training-012-app "$T/unsafe.json" "$T/unsafe.log"; then
    echo 'FAIL: invalid dependency name did not mark partial' >&2
    exit 1
fi
jq -e '.status=="partial" and .invalid_unit_names==1 and .inspected_count==1 and
    .required_units[0].unit=="uir-training-012-dependency.service"' "$T/unsafe.json" >/dev/null
printf 'PASS: unsafe unit names skipped without being passed to systemctl\n'
export UIR_DEP_FIXTURE_STATE=many
uir::collect::dependencies uir-training-012-app "$T/many.json" "$T/many.log" || true
jq -e '.status=="partial" and .truncated==true and .requires_total==10 and
    .inspected_count==8 and (.required_units|length)==8' "$T/many.json" >/dev/null
printf 'PASS: direct dependency inspection capped at eight units\n'
export UIR_DEP_FIXTURE_STATE=none
uir::collect::dependencies uir-training-012-app "$T/none.json" "$T/none.log"
jq -e '.status=="observed" and .outcome=="no_requires" and
   .requires_total==0 and (.required_units|length)==0' "$T/none.json" >/dev/null
printf 'PASS: empty direct dependency list represented accurately\n'
export UIR_DEP_FIXTURE_STATE=real_units
uir::collect::dependencies uir-training-012-app "$T/real-units.json" "$T/real-units.log"
jq -e '.status=="observed" and .outcome=="all_active" and .requires_total==2 and
    .inspected_count==2 and .invalid_unit_names==0 and (.required_units|length)==2 and
    ([.required_units[].unit] | sort)==["sysinit.target","system.slice"] and
    ([.required_units[].result] | all(.=="not_applicable"))' "$T/real-units.json" >/dev/null
printf 'PASS: target and slice dependencies inspected without spurious failures\n'
printf 'All systemd dependency integration checks passed.\n'
