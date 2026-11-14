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

# Filesystem probes accept an existing, canonical directory only. No wildcard,
# symlink component, control character or non-ASCII path is accepted. The
# measured path is hashed before storage; this is not an atomic race guard.
uir::validate::filesystem_path() {
    local input="$1" canonical
    if ((${#input} < 1 || ${#input} > 384)) ||
        [[ ! "$input" =~ ^/[a-zA-Z0-9._/-]*$ ]] ||
        [[ "$input" != / && "$input" == */ ]] ||
        [[ ! -d "$input" || -L "$input" ]]; then
        uir::error 'filesystem path must be an existing canonical absolute directory'
        return 2
    fi
    canonical="$(realpath -e -- "$input" 2>/dev/null)" || return 2
    if [[ "$canonical" != "$input" ]]; then
        uir::error 'filesystem path must not contain symlinks, dot or traversal components'
        return 2
    fi
}

# Allow only conventional, bounded systemd unit names returned from Requires=.
# No paths, shell metacharacters, leading option markers or escaped unit names.
uir::validate::dependency_unit() {
    ((${#1} >= 1 && ${#1} <= 128)) &&
        [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.@:-]*\.(service|socket|target|mount|timer|path|slice)$ ]] &&
        [[ "$1" != *'..'* ]]
}
