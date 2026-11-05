#!/usr/bin/env bash
# Non-invasive environment preflight. Never prints or stores journal content.

uir::doctor::result() {
    local level="$1" item="$2" reason="$3"
    printf '  %-5s %-17s %s\n' "[$level]" "$item" "$reason"
}

uir::doctor() {
    local missing=0 warnings=0 cmd
    local os_id='unknown' os_version='unknown' key value

    printf '%s - preflight\n' "$UIR_PRODUCT"
    printf '  Build: %s\n' "$UIR_VERSION"
    printf '  Checks are read-only. No system changes will be made.\n\n'

    # Read trusted OS metadata as data, not executable shell code.
    if [[ -r /etc/os-release ]]; then
        while IFS='=' read -r key value; do
            value="${value#\"}"
            value="${value%\"}"
            case "$key" in
            ID) os_id="$value" ;;
            VERSION_ID) os_version="$value" ;;
            esac
        done </etc/os-release
    fi
    if [[ "$os_id" == 'ubuntu' && "$os_version" == '24.04' ]]; then
        uir::doctor::result PASS platform 'Ubuntu 24.04 LTS detected'
    else
        uir::doctor::result WARN platform "Detected $os_id $os_version; target is Ubuntu 24.04 LTS"
        ((warnings += 1))
    fi

    if [[ -r /proc/sys/kernel/osrelease ]]; then
        local kernel_release=''
        read -r kernel_release </proc/sys/kernel/osrelease || true
        if [[ "${kernel_release,,}" == *microsoft* || "${kernel_release,,}" == *wsl* ]]; then
            uir::doctor::result WARN runtime 'WSL detected: suitable for CLI development, not destructive incident labs'
            ((warnings += 1))
        else
            uir::doctor::result PASS runtime 'No WSL kernel marker detected (VM isolation not independently verified)'
        fi
    fi

    if ((EUID == 0)); then
        uir::doctor::result WARN privileges 'Running as root; run uir as a regular user'
        ((warnings += 1))
    else
        uir::doctor::result PASS privileges 'Running without root privileges'
    fi

    # Commands needed by later collector/storage milestones.
    # Checking their presence now does not imply they are used by this build.
    for cmd in bash jq tar gzip timeout systemctl journalctl ip ss stat mktemp flock du sha256sum; do
        if command -v "$cmd" >/dev/null 2>&1; then
            uir::doctor::result PASS "$cmd" 'Available'
        else
            uir::doctor::result FAIL "$cmd" 'Missing required future dependency'
            ((missing += 1))
        fi
    done

    # Developer and scenario-specific tools are optional for the base CLI.
    for cmd in nginx ssh sshd curl shellcheck shfmt bats git; do
        if command -v "$cmd" >/dev/null 2>&1; then
            uir::doctor::result PASS "$cmd" 'Available'
        else
            uir::doctor::result WARN "$cmd" 'Not found (optional: lab scenario or developer quality tool)'
            ((warnings += 1))
        fi
    done

    if command -v journalctl >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1 && timeout 5s journalctl --no-pager --lines=1 --quiet >/dev/null 2>&1; then
            uir::doctor::result PASS journal-access 'Read attempt succeeded; visibility may still be restricted'
        else
            uir::doctor::result WARN journal-access 'Read failed or unavailable; check journal permissions/systemd'
            ((warnings += 1))
        fi
    fi

    printf '\nSummary: %s missing required command(s), %s warning(s).\n' "$missing" "$warnings"
    if ((missing > 0)); then
        printf 'Install missing dependencies on your Ubuntu VM, then rerun: ./bin/uir doctor\n'
        return 3
    fi
    printf 'Essential command presence checks passed; review warnings before live capture.\n'
    return 0
}
