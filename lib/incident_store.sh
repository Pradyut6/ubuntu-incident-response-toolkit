#!/usr/bin/env bash
# Private local evidence store. All runtime state lives outside the source tree.

uir::store::root() {
    local base="${XDG_DATA_HOME:-${HOME:-}/.local/share}"
    if [[ -z "${XDG_DATA_HOME:-}" && -z "${HOME:-}" ]]; then
        uir::error 'HOME is unset and XDG_DATA_HOME is not provided'
        return 5
    fi
    printf '%s/ubuntu-irt\n' "$base"
}

uir::store::require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        uir::error 'jq is required for incident metadata; install it with: sudo apt install jq'
        return 3
    fi
}

uir::store::require_regular_user() {
    if ((EUID == 0)); then
        uir::error 'refusing to manage incident data as root; run as a regular user'
        return 5
    fi
}

uir::store::private_dir() {
    local path="$1" mode owner
    if [[ -L "$path" || ! -d "$path" ]]; then
        uir::error "expected a real private directory: $path"
        return 5
    fi
    mode="$(stat -c '%a' -- "$path")" || return 5
    owner="$(stat -c '%u' -- "$path")" || return 5
    if [[ "$mode" != 700 || "$owner" != "$EUID" ]]; then
        uir::error "unsafe directory owner or mode at $path (need current user and 0700)"
        return 5
    fi
}

uir::store::private_file() {
    local path="$1" mode owner size links
    if [[ -L "$path" || ! -f "$path" ]]; then
        uir::error "expected a real private file: $path"
        return 5
    fi
    mode="$(stat -c '%a' -- "$path")" || return 5
    owner="$(stat -c '%u' -- "$path")" || return 5
    if [[ "$mode" != 600 || "$owner" != "$EUID" ]]; then
        uir::error "unsafe file owner or mode at $path (need current user and 0600)"
        return 5
    fi
    size="$(stat -c '%s' -- "$path")" || return 5
    links="$(stat -c '%h' -- "$path")" || return 5
    if ((size > 65536 || links != 1)); then
        uir::error "unsafe metadata file size or hard-link count at $path"
        return 5
    fi
}

# The parent of the app root may be an XDG data location that doesn't exist yet.
# Create missing components privately. Never change permissions on existing parents.
uir::store::make_path() {
    local target="$1" fragment part=''
    local -a segments
    uir::validate::absolute_path "$target" || return $?
    IFS='/' read -r -a segments <<<"${target#/}"
    for fragment in "${segments[@]}"; do
        part+="/$fragment"
        if [[ ! -d "$part" ]]; then
            mkdir -m 700 -- "$part" || {
                uir::error "cannot create directory: $part"
                return 5
            }
        fi
        if [[ -L "$part" || ! -d "$part" ]]; then
            uir::error "unsafe data directory: $part"
            return 5
        fi
    done
}

uir::store::settings_valid() {
    local path="$1"
    uir::store::private_file "$path" || return $?
    if ! jq -e '
        type == "object" and .schema_version == 1 and
        (.retention_days | type == "number" and floor == . and . >= 1 and . <= 3650) and
        (.max_storage_mib | type == "number" and floor == . and . >= 10 and . <= 10240) and
        (.capture_max_mib | type == "number" and floor == . and . >= 1 and . <= 100) and
        .capture_max_mib <= .max_storage_mib
    ' "$path" >/dev/null 2>&1; then
        uir::error "invalid or corrupted settings JSON: $path"
        return 5
    fi
}

uir::store::ready() {
    local root="$1"
    uir::validate::absolute_path "$root" || return $?
    uir::store::private_dir "$root" || return $?
    uir::store::private_dir "$root/config" || return $?
    uir::store::private_dir "$root/incidents" || return $?
    uir::store::settings_valid "$root/config/settings.json" || return $?
}

uir::store::init() {
    local root settings tmp
    uir::store::require_regular_user || return $?
    uir::store::require_jq || return $?
    root="$(uir::store::root)" || return $?
    uir::validate::absolute_path "$root" || return $?

    # Never follow a pre-existing symlink or replace an invalid store/config.
    uir::store::make_path "$root" || return $?
    uir::store::private_dir "$root" || return $?
    uir::store::make_path "$root/config" || return $?
    uir::store::make_path "$root/incidents" || return $?
    uir::store::private_dir "$root/config" || return $?
    uir::store::private_dir "$root/incidents" || return $?

    settings="$root/config/settings.json"
    if [[ -e "$settings" || -L "$settings" ]]; then
        uir::store::settings_valid "$settings" || return $?
        printf 'Incident data store already initialized: %s\n' "$root"
        return 0
    fi

    tmp="$(mktemp "$root/config/.settings.XXXXXXXX")" || {
        uir::error 'could not create private settings staging file'
        return 5
    }
    if ! jq -n '{schema_version:1,retention_days:30,max_storage_mib:500,capture_max_mib:10}' >"$tmp"; then
        rm -f -- "$tmp"
        uir::error 'could not write settings JSON'
        return 5
    fi
    # Preserve 0600. Avoid replacing a settings file created by another process.
    if [[ -e "$settings" || -L "$settings" ]]; then
        rm -f -- "$tmp"
        uir::error 'settings appeared during initialization; retry after inspecting the store'
        return 5
    fi
    # Atomic exclusive publication via hard link (fails if the destination exists).
    if ! ln -- "$tmp" "$settings"; then
        rm -f -- "$tmp"
        uir::error 'could not publish settings without overwriting an existing file'
        return 5
    fi
    rm -f -- "$tmp"
    uir::store::ready "$root" || return $?
    printf 'Initialized private incident data store: %s\n' "$root"
}

uir::store::metadata_valid() {
    local path="$1" id="$2"
    uir::store::private_file "$path" || return $?
    if ! jq -e --arg id "$id" '
        type == "object" and
        .schema_version == 1 and
        .incident_id == $id and
        (.service | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9_.@-]{0,63}$") and (contains("..") | not)) and
        (.severity | IN("low", "medium", "high", "critical")) and
        (.status | IN("open", "investigating", "resolved", "closed")) and
        (.notes | type == "array" and length <= 100 and all(.[]; (type == "object") and (.kind | IN("hypothesis", "root_cause", "remediation", "verification", "customer_update")) and (.text | type == "string" and length >= 1 and length <= 2000) and (.at | type == "string"))) and
        (.summary | type == "string" and length >= 1 and length <= 240 and (test("[[:cntrl:]]") | not)) and
        (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
        (.updated_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    ' "$path" >/dev/null 2>&1; then
        uir::error "invalid or corrupted incident metadata: $path"
        return 5
    fi
}

uir::store::incident_dir() {
    local id="$2" dir="$1/incidents/$2"
    uir::validate::incident_id "$id" || {
        uir::error 'incident ID must match INC- followed by 3 to 6 digits'
        return 2
    }
    uir::store::private_dir "$dir" || return $?
    printf '%s\n' "$dir"
}

uir::store::create() {
    local id='' service='' severity='' summary='Not supplied' root path tmp now
    local have_id=0 have_service=0 have_severity=0 have_summary=0
    uir::store::require_regular_user || return $?
    uir::store::require_jq || return $?
    while (($# > 0)); do
        case "$1" in
        --id)
            if ((have_id)) || (($# < 2)); then
                uir::error 'duplicate or missing --id'
                return 2
            fi
            id="$2"
            have_id=1
            shift 2
            ;;
        --service)
            if ((have_service)) || (($# < 2)); then
                uir::error 'duplicate or missing --service'
                return 2
            fi
            service="$2"
            have_service=1
            shift 2
            ;;
        --severity)
            if ((have_severity)) || (($# < 2)); then
                uir::error 'duplicate or missing --severity'
                return 2
            fi
            severity="$2"
            have_severity=1
            shift 2
            ;;
        --summary)
            if ((have_summary)) || (($# < 2)); then
                uir::error 'duplicate or missing --summary'
                return 2
            fi
            summary="$2"
            have_summary=1
            shift 2
            ;;
        *)
            uir::error "unexpected incident create argument: $1"
            return 2
            ;;
        esac
    done
    if ((!have_id || !have_service || !have_severity)); then
        uir::error 'usage: uir incident create --id INC-007 --service nginx --severity high [--summary TEXT]'
        return 2
    fi
    if ! uir::validate::incident_id "$id"; then
        uir::error 'incident ID must match INC- followed by 3 to 6 digits'
        return 2
    fi
    if ! uir::validate::service "$service"; then
        uir::error 'invalid service name: use a systemd-style name, not a path or command'
        return 2
    fi
    if ! uir::validate::severity "$severity"; then
        uir::error 'severity must be low, medium, high or critical'
        return 2
    fi
    if ! uir::validate::summary "$summary"; then
        uir::error 'summary must contain 1-240 characters and no control characters'
        return 2
    fi
    root="$(uir::store::root)" || return $?
    uir::store::ready "$root" || {
        uir::error 'initialize the store first with: uir init'
        return 5
    }
    path="$root/incidents/$id"
    if [[ -e "$path" || -L "$path" ]]; then
        uir::error "incident already exists or path is unsafe: $id"
        return 5
    fi
    if ! mkdir -m 700 -- "$path"; then
        uir::error "could not create incident directory: $id"
        return 5
    fi
    # The timestamp is creation time, NOT an operator-supplied event time.
    now="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" || {
        rmdir -- "$path" 2>/dev/null || true
        uir::error 'could not obtain UTC creation timestamp'
        return 5
    }
    tmp="$(mktemp "$path/.incident.XXXXXXXX")" || {
        rmdir -- "$path" 2>/dev/null || true
        uir::error 'could not stage incident metadata'
        return 5
    }
    if ! jq -n --arg id "$id" --arg service "$service" --arg severity "$severity" \
        --arg summary "$summary" --arg now "$now" \
        '{schema_version:1,incident_id:$id,service:$service,severity:$severity,
          status:"open",summary:$summary,created_at:$now,updated_at:$now,notes:[],captures:{}}' >"$tmp"; then
        rm -f -- "$tmp"
        rmdir -- "$path" 2>/dev/null || true
        uir::error 'could not serialize incident metadata'
        return 5
    fi
    if ! ln -- "$tmp" "$path/incident.json"; then
        rm -f -- "$tmp"
        rmdir -- "$path" 2>/dev/null || true
        uir::error 'could not publish incident metadata without overwriting an existing file'
        return 5
    fi
    rm -f -- "$tmp"
    uir::store::metadata_valid "$path/incident.json" "$id" || return $?
    printf 'Created incident %s (service=%s, severity=%s)\n' "$id" "$service" "$severity"
}

uir::store::show() {
    local id="$1" root path
    uir::store::require_jq || return $?
    if ! uir::validate::incident_id "$id"; then
        uir::error 'incident ID must match INC- followed by 3 to 6 digits'
        return 2
    fi
    root="$(uir::store::root)" || return $?
    uir::store::ready "$root" || return $?
    path="$(uir::store::incident_dir "$root" "$id")" || return $?
    uir::store::metadata_valid "$path/incident.json" "$id" || return $?
    jq . "$path/incident.json"
}

uir::store::list() {
    local root path id file
    local found=0
    uir::store::require_jq || return $?
    root="$(uir::store::root)" || return $?
    uir::store::ready "$root" || return $?
    # nullglob avoids accidental processing of an unmatched glob.
    local -a dirs=("$root"/incidents/*)
    if [[ ! -e "${dirs[0]}" && ! -L "${dirs[0]}" ]]; then
        printf 'No incidents found.\n'
        return 0
    fi
    # Validate everything before displaying anything (no misleading partial listing).
    for path in "${dirs[@]}"; do
        id="${path##*/}"
        if ! uir::validate::incident_id "$id"; then
            uir::error "unexpected entry in incident directory: $id"
            return 5
        fi
        uir::store::private_dir "$path" || return $?
        uir::store::metadata_valid "$path/incident.json" "$id" || return $?
        ((found += 1))
    done
    printf 'ID\tSERVICE\tSEVERITY\tSTATUS\tCREATED_UTC\tSUMMARY\n'
    for path in "${dirs[@]}"; do
        file="$path/incident.json"
        jq -r '[.incident_id,.service,.severity,.status,.created_at,.summary] | @tsv' "$file"
    done
    ((found > 0))
}

# All mutating operations take an exclusive lock in the private incident dir.
# Readers validate the metadata before use. A hostile process running under the
# same UNIX UID can still race Bash path checks: storage must be user-controlled.
uir::store::locked_incident() {
    local id="$1" root dir
    uir::validate::incident_id "$id" || {
        uir::error 'invalid incident ID'
        return 2
    }
    root="$(uir::store::root)" || return $?
    uir::store::ready "$root" || return $?
    dir="$(uir::store::incident_dir "$root" "$id")" || return $?
    uir::store::metadata_valid "$dir/incident.json" "$id" || return $?
    printf '%s\n' "$dir"
}

uir::store::lock() {
    local dir="$1" lock="$1/.uir.lock"
    if [[ -L "$lock" || (-e "$lock" && ! -f "$lock") ]]; then
        uir::error 'unsafe incident lock file'
        return 5
    fi
    # Caller keeps FD 9 open for the duration of the operation.
    exec 9>>"$lock" || return 5
    chmod 600 -- "$lock" || return 5
    if [[ "$(stat -c '%h' -- "$lock")" != 1 ]]; then
        uir::error 'unsafe lock file link count'
        return 5
    fi
    flock -x -w 10 9 || {
        uir::error 'incident is busy'
        return 5
    }
}

uir::store::replace_json() {
    local file="$1" tmp
    uir::store::private_file "$file" || return $?
    tmp="$(mktemp "${file}.tmp.XXXXXXXX")" || return 5
    if ! cat >"$tmp"; then
        rm -f -- "$tmp"
        return 5
    fi
    if ! jq -e 'type == "object"' "$tmp" >/dev/null 2>&1; then
        rm -f -- "$tmp"
        uir::error 'invalid replacement JSON'
        return 5
    fi
    chmod 600 -- "$tmp" || {
        rm -f -- "$tmp"
        return 5
    }
    mv -T -- "$tmp" "$file"
}

uir::store::note() {
    local id='' kind='' note='' dir now
    while (($# > 0)); do
        case "$1" in
        --id)
            (($# >= 2)) || return 2
            id="$2"
            shift 2
            ;;
        --kind)
            (($# >= 2)) || return 2
            kind="$2"
            shift 2
            ;;
        --text)
            (($# >= 2)) || return 2
            note="$2"
            shift 2
            ;;
        *)
            uir::error "unknown note argument: $1"
            return 2
            ;;
        esac
    done
    uir::validate::incident_id "$id" && uir::validate::kind "$kind" && uir::validate::note "$note" || {
        uir::error 'usage: incident note --id INC-007 --kind hypothesis|root_cause|remediation|verification|customer_update --text TEXT (1-2000 characters)'
        return 2
    }
    uir::store::require_regular_user || return $?
    dir="$(uir::store::locked_incident "$id")" || return $?
    uir::store::lock "$dir" || return $?
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if ! jq --arg kind "$kind" --arg note "$note" --arg now "$now" \
        'if (.notes|length) >= 100 then error("note limit") else .notes += [{kind:$kind,text:$note,at:$now}] | .updated_at = $now end' \
        "$dir/incident.json" | uir::store::replace_json "$dir/incident.json"; then
        uir::error 'failed to save note (maximum 100 notes or 64 KiB metadata)'
        return 5
    fi
    uir::store::metadata_valid "$dir/incident.json" "$id" || return $?
    printf 'Recorded %s note for %s\n' "$kind" "$id"
}

uir::store::status() {
    local id='' value='' dir now
    while (($# > 0)); do
        case "$1" in
        --id)
            (($# >= 2)) || return 2
            id="$2"
            shift 2
            ;;
        --value)
            (($# >= 2)) || return 2
            value="$2"
            shift 2
            ;;
        *)
            uir::error "unknown status argument: $1"
            return 2
            ;;
        esac
    done
    uir::validate::incident_id "$id" && uir::validate::status "$value" || {
        uir::error 'usage: incident status --id INC-007 --value open|investigating|resolved|closed'
        return 2
    }
    uir::store::require_regular_user || return $?
    dir="$(uir::store::locked_incident "$id")" || return $?
    uir::store::lock "$dir" || return $?
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq --arg value "$value" --arg now "$now" '.status = $value | .updated_at = $now' "$dir/incident.json" |
        uir::store::replace_json "$dir/incident.json" || return 5
    printf '%s status: %s\n' "$id" "$value"
}

# Unlike JSON metadata (<=64 KiB), gzip evidence is intentionally allowed to
# approach the configured 10 MiB default capture ceiling. Still reject unsafe
# filesystem objects and impossible evidence sizes.
uir::store::evidence_file() {
    local path="$1" mode owner size links
    if [[ -L "$path" || ! -f "$path" ]]; then
        uir::error "unsafe evidence file: $path"
        return 5
    fi
    mode="$(stat -c '%a' -- "$path")" || return 5
    owner="$(stat -c '%u' -- "$path")" || return 5
    size="$(stat -c '%s' -- "$path")" || return 5
    links="$(stat -c '%h' -- "$path")" || return 5
    if [[ "$mode" != 600 || "$owner" != "$EUID" || "$links" != 1 ]] || ((size > 12 * 1048576)); then
        uir::error "unsafe evidence owner, mode, link count or size: $path"
        return 5
    fi
}
