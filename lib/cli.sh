#!/usr/bin/env bash
# Explicit, stable CLI; no dynamic evaluation of user-controlled input.

uir::usage() {
    cat <<'USAGE'
Ubuntu Incident Response Toolkit (uir) — Bash CLI v1.0 release candidate

Usage:
  uir --help | --version
  uir doctor
  uir init
  uir incident create --id INC-007 --service nginx --severity high [--summary TEXT]
  uir incident list
  uir incident show INC-007
  uir incident note --id INC-007 --kind root_cause --text TEXT
  uir incident status --id INC-007 --value investigating|resolved|closed
  uir incident search [--id INC-007] [--service nginx] [--severity high]
                      [--since YYYY-MM-DD] [--text 'literal error']
  uir capture --incident INC-007 --phase before|after [--minutes 15]
  uir compare --incident INC-007
  uir report --incident INC-007
  uir export --incident INC-007 --preview
  uir export --incident INC-007 --output ./INC-007-handoff.tar.gz
  uir retention status
  uir retention set [--days 30] [--max-storage-mb 500] [--capture-max-mb 10]
  uir retention prune --dry-run | --yes

Supported capture profiles: host, nginx, ssh, ssh.socket, and uir-* training units.
Each incident has one immutable before and one immutable after snapshot.
Host diagnostic collection is read-only; manual service repairs are NOT automated.
No telemetry, remote access, background monitoring, or GUI is included in v1.0.

Exit codes: 0 successful; 2 argument error; 3 dependency missing;
            5 unsafe store/collection error. Partial capture is marked in JSON.
Safety: run as a regular user on Ubuntu 24.04, never with sudo ./bin/uir.
        Use a disposable VM for deliberate faults. Review exports before sharing.
USAGE
}

uir::error() { printf 'uir: %s\n' "$*" >&2; }

uir::main() {
    if (($# == 0)); then
        uir::usage
        return 0
    fi
    local cmd="$1" action
    shift
    case "$cmd" in
    --help | -h | help)
        (($# == 0)) || {
            uir::error 'help does not accept arguments'
            return 2
        }
        uir::usage
        ;;
    --version | -V)
        (($# == 0)) || {
            uir::error '--version does not accept arguments'
            return 2
        }
        printf 'uir %s\n' "$UIR_VERSION"
        ;;
    doctor)
        (($# == 0)) || {
            uir::error 'doctor does not accept arguments'
            return 2
        }
        uir::doctor
        ;;
    init)
        (($# == 0)) || {
            uir::error 'init does not accept arguments'
            return 2
        }
        uir::store::init
        ;;
    incident)
        (($# >= 1)) || {
            uir::error 'usage: incident create|list|show|note|status|search'
            return 2
        }
        action="$1"
        shift
        case "$action" in
        create) uir::store::create "$@" ;;
        list)
            (($# == 0)) || return 2
            uir::store::list
            ;;
        show)
            (($# == 1)) || return 2
            uir::store::show "$1"
            ;;
        note) uir::store::note "$@" ;;
        status) uir::store::status "$@" ;;
        search) uir::search::run "$@" ;;
        *)
            uir::error "unknown incident subcommand: $action"
            return 2
            ;;
        esac
        ;;
    capture) uir::capture::run "$@" ;;
    compare) uir::compare::run "$@" ;;
    report) uir::report::run "$@" ;;
    export) uir::export::run "$@" ;;
    retention)
        (($# >= 1)) || {
            uir::error 'usage: retention status|set|prune'
            return 2
        }
        action="$1"
        shift
        case "$action" in
        status)
            (($# == 0)) || return 2
            uir::retention::status
            ;;
        set) uir::retention::set "$@" ;;
        prune) uir::retention::prune "$@" ;;
        *)
            uir::error "unknown retention subcommand: $action"
            return 2
            ;;
        esac
        ;;
    *)
        uir::error "unknown command: '$cmd' (try: uir --help)"
        return 2
        ;;
    esac
}
