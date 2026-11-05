#!/usr/bin/env bats
# Requires jq and an unprivileged user. Works without root or active systemd.
setup() {
    UIR="$BATS_TEST_DIRNAME/../../bin/uir"
    WORK="$(mktemp -d)"
    export XDG_DATA_HOME="$WORK"
}

teardown() {
    rm -rf -- "$WORK"
}

@test 'init creates a validated private store with strict modes' {
    run "$UIR" init
    [ "$status" -eq 0 ]
    [ "$(stat -c '%a' "$WORK/ubuntu-irt")" = 700 ]
    [ "$(stat -c '%a' "$WORK/ubuntu-irt/config")" = 700 ]
    [ "$(stat -c '%a' "$WORK/ubuntu-irt/incidents")" = 700 ]
    [ "$(stat -c '%a' "$WORK/ubuntu-irt/config/settings.json")" = 600 ]
    [ "$(jq -r .retention_days "$WORK/ubuntu-irt/config/settings.json")" = 30 ]
}

@test 'init is idempotent and does not rewrite settings' {
    "$UIR" init
    checksum="$(sha256sum "$WORK/ubuntu-irt/config/settings.json")"
    run "$UIR" init
    [ "$status" -eq 0 ]
    [ "$checksum" = "$(sha256sum "$WORK/ubuntu-irt/config/settings.json")" ]
}

@test 'incident creation requires explicit initialization' {
    run "$UIR" incident create --id INC-007 --service nginx --severity high
    [ "$status" -eq 5 ]
    [ ! -d "$WORK/ubuntu-irt" ]
}

@test 'metadata persists as JSON across independent CLI invocations' {
    "$UIR" init
    run "$UIR" incident create --id INC-007 --service nginx --severity high --summary 'Nginx service unavailable'
    [ "$status" -eq 0 ]
    path="$WORK/ubuntu-irt/incidents/INC-007/incident.json"
    [ "$(stat -c '%a' "$WORK/ubuntu-irt/incidents/INC-007")" = 700 ]
    [ "$(stat -c '%a' "$path")" = 600 ]
    [ "$(jq -r .service "$path")" = nginx ]
    run "$UIR" incident show INC-007
    [ "$status" -eq 0 ]
    [[ "$output" == *'Nginx service unavailable'* ]]
    run "$UIR" incident list
    [ "$status" -eq 0 ]
    [[ "$output" == *'INC-007'* ]]
}

@test 'duplicate incident creation never overwrites the original' {
    "$UIR" init
    "$UIR" incident create --id INC-007 --service nginx --severity high
    checksum="$(sha256sum "$WORK/ubuntu-irt/incidents/INC-007/incident.json")"
    run "$UIR" incident create --id INC-007 --service ssh --severity low
    [ "$status" -eq 5 ]
    [ "$checksum" = "$(sha256sum "$WORK/ubuntu-irt/incidents/INC-007/incident.json")" ]
}

@test 'path traversal in incident id is rejected' {
    "$UIR" init
    run "$UIR" incident create --id '../outside' --service nginx --severity high
    [ "$status" -eq 2 ]
    [ ! -e "$WORK/outside" ]
}

@test 'command substitution in service is rejected and never evaluated' {
    "$UIR" init
    run "$UIR" incident create --id INC-007 --service "\$(touch $WORK/pwned)" --severity high
    [ "$status" -eq 2 ]
    [ ! -e "$WORK/pwned" ]
}

@test 'malicious-looking summary is safely stored as literal JSON data' {
    "$UIR" init
    run "$UIR" incident create --id INC-007 --service nginx --severity high --summary "\$(touch $WORK/pwned)"
    [ "$status" -eq 0 ]
    [ ! -e "$WORK/pwned" ]
    [[ "$(jq -r .summary "$WORK/ubuntu-irt/incidents/INC-007/incident.json")" == *'$(touch'* ]]
}

@test 'invalid severity and control characters are rejected' {
    "$UIR" init
    run "$UIR" incident create --id INC-007 --service nginx --severity absurd
    [ "$status" -eq 2 ]
    run "$UIR" incident create --id INC-007 --service nginx --severity high --summary $'line1\nline2'
    [ "$status" -eq 2 ]
}

@test 'root of data store cannot be a symlink' {
    mkdir "$WORK/target"
    ln -s "$WORK/target" "$WORK/ubuntu-irt"
    run "$UIR" init
    [ "$status" -eq 5 ]
    [ ! -e "$WORK/target/config" ]
}

@test 'incident directory cannot be a symlink' {
    "$UIR" init
    mkdir "$WORK/target"
    ln -s "$WORK/target" "$WORK/ubuntu-irt/incidents/INC-007"
    run "$UIR" incident create --id INC-007 --service nginx --severity high
    [ "$status" -eq 5 ]
    [ ! -e "$WORK/target/incident.json" ]
}

@test 'symlink in ancestor data path is refused' {
    mkdir "$WORK/real"
    ln -s "$WORK/real" "$WORK/link"
    export XDG_DATA_HOME="$WORK/link/nested"
    run "$UIR" init
    [ "$status" -eq 5 ]
    [ ! -d "$WORK/real/nested" ]
}

@test 'relative XDG_DATA_HOME path is refused' {
    export XDG_DATA_HOME='relative/somewhere'
    run "$UIR" init
    [ "$status" -eq 5 ]
}

@test 'unsafe permissions are detected instead of silently changed' {
    "$UIR" init
    chmod 755 "$WORK/ubuntu-irt"
    run "$UIR" incident list
    [ "$status" -eq 5 ]
}

@test 'corrupt settings are refused without being overwritten' {
    "$UIR" init
    chmod 600 "$WORK/ubuntu-irt/config/settings.json"
    printf '%s\n' '{broken' >"$WORK/ubuntu-irt/config/settings.json"
    run "$UIR" init
    [ "$status" -eq 5 ]
    [ "$(cat "$WORK/ubuntu-irt/config/settings.json")" = '{broken' ]
}

@test 'corrupt incident metadata is detected on show and list' {
    "$UIR" init
    "$UIR" incident create --id INC-007 --service nginx --severity high
    printf '%s\n' '{broken' >"$WORK/ubuntu-irt/incidents/INC-007/incident.json"
    run "$UIR" incident show INC-007
    [ "$status" -eq 5 ]
    run "$UIR" incident list
    [ "$status" -eq 5 ]
}

@test 'newly created incident has an ISO 8601 UTC timestamp' {
    "$UIR" init
    "$UIR" incident create --id INC-007 --service nginx --severity high
    timestamp="$(jq -r .created_at "$WORK/ubuntu-irt/incidents/INC-007/incident.json")"
    [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}
