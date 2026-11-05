#!/usr/bin/env bash
# Validation helpers: never execute or source user-controlled values.

uir::validate::incident_id() {
    [[ "$1" =~ ^INC-[0-9]{3,6}$ ]]
}

uir::validate::service() {
    # Simple systemd-style service identifier (not an arbitrary unit/path/command).
    ((${#1} >= 1 && ${#1} <= 64)) &&
        [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.@-]*$ ]] &&
        [[ "$1" != *'..'* ]]
}

uir::validate::severity() {
    case "$1" in
    low | medium | high | critical) return 0 ;;
    *) return 1 ;;
    esac
}

uir::validate::summary() {
    ((${#1} >= 1 && ${#1} <= 240)) && [[ ! "$1" =~ [[:cntrl:]] ]]
}

# Guard against path traversal and symlinks anywhere in the chosen data path.
# This is a Bash path validation check, NOT an atomic anti-race guarantee.
uir::validate::absolute_path() {
    local input="$1" fragment part=''
    local -a segments
    if [[ "$input" != /* || "$input" == '/' || "$input" == */ ]]; then
        uir::error 'data home must be an absolute directory path without a trailing slash'
        return 5
    fi
    IFS='/' read -r -a segments <<<"${input#/}"
    for fragment in "${segments[@]}"; do
        if [[ -z "$fragment" || "$fragment" == '.' || "$fragment" == '..' ]]; then
            uir::error 'data home contains an empty, dot or traversal path component'
            return 5
        fi
        part+="/$fragment"
        if [[ -L "$part" ]]; then
            uir::error "refusing symlink in data path: $part"
            return 5
        fi
        if [[ -e "$part" && ! -d "$part" ]]; then
            uir::error "not a directory in data path: $part"
            return 5
        fi
    done
}

uir::validate::phase() {
    [[ "$1" == before || "$1" == after ]]
}

uir::validate::kind() {
    case "$1" in
    hypothesis | root_cause | remediation | verification | customer_update) return 0 ;;
    *) return 1 ;;
    esac
}

uir::validate::status() {
    case "$1" in
    open | investigating | resolved | closed) return 0 ;;
    *) return 1 ;;
    esac
}

uir::validate::integer() {
    [[ "$1" =~ ^[0-9]{1,6}$ ]] && ((10#$1 >= $2 && 10#$1 <= $3))
}

uir::validate::date() {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] &&
        [[ "$(date -u -d "$1" +%F 2>/dev/null)" == "$1" ]]
}

uir::validate::note() {
    ((${#1} >= 1 && ${#1} <= 2000)) && [[ ! "$1" =~ [[:cntrl:]] ]]
}

uir::validate::profile() {
    # Explicit allowlist for host service diagnosis; never trust an arbitrary
    # supplied name as an executable. Training units are namespaced to uir-.
    case "$1" in
    host | nginx | nginx.service | ssh | ssh.service | ssh.socket) return 0 ;;
    uir-*) [[ "$1" =~ ^uir-[a-zA-Z0-9_-]{1,50}(\.service)?$ ]] ;;
    *) return 1 ;;
    esac
}
