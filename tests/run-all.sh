#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$root"
[[ $EUID != 0 ]] || {
    echo 'Run test suite as a regular user, not root.' >&2
    exit 1
}
printf '\n[1/13] Bash syntax\n'
bash -n bin/uir lib/*.sh tests/smoke.sh tests/integration/*.sh tests/unit/redaction.sh
printf '\n[2/13] ShellCheck\n'
if command -v shellcheck >/dev/null; then
    shellcheck -S warning bin/uir lib/*.sh tests/smoke.sh tests/integration/*.sh tests/unit/redaction.sh
else
    printf 'SKIP ShellCheck (install: sudo apt install shellcheck)\n'
fi
printf '\n[3/13] shfmt (diff-only)\n'
if command -v shfmt >/dev/null; then
    shfmt -d -i 4 bin/uir lib/*.sh tests/smoke.sh tests/integration/*.sh tests/unit/redaction.sh
else
    printf 'SKIP shfmt (install: sudo apt install shfmt)\n'
fi
printf '\n[4/13] Smoke tests\n'
bash tests/smoke.sh
printf '\n[5/13] Bats unit tests\n'
if command -v bats >/dev/null; then
    bats tests/unit/*.bats
else
    printf 'SKIP Bats (install: sudo apt install bats)\n'
fi
printf '\n[6/13] Non-destructive integration tests\n'
bash tests/integration/m3-store.sh
bash tests/integration/v1-workflow.sh
bash tests/unit/redaction.sh
printf '\n[7/13] Loopback HTTP probe integration tests\n'
bash tests/integration/http-probe.sh
printf '\n[8/13] TCP listener integration tests\n'
bash tests/integration/tcp-listener.sh
printf '\n[9/13] Targeted filesystem integration tests\n'
bash tests/integration/filesystem.sh
printf '\n[10/13] systemd dependency inspection integration tests\n'
bash tests/integration/dependencies.sh
printf '\n[11/13] Bounded process inspection integration tests\n'
bash tests/integration/processes.sh
printf '\n[12/13] Unit-scoped journal visibility integration tests\n'
bash tests/integration/journal-audit.sh
printf '\n[13/13] H07 export boundary and privacy checks\n'
bash tests/integration/h07-security.sh
printf '\nTest runner finished. Check any SKIP status before release.\n'
