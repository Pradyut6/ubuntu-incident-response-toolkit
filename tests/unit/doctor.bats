#!/usr/bin/env bats
setup() {
    UIR="$BATS_TEST_DIRNAME/../../bin/uir"
}

@test 'doctor reports prerequisite state on current host without crashing' {
    run "$UIR" doctor
    [[ "$status" -eq 0 || "$status" -eq 3 ]]
    [[ "$output" == *'Summary:'* ]]
    [[ "$output" == *'journal-access'* || "$output" == *'[FAIL] journalctl'* ]]
}

@test 'doctor reports missing dependencies when PATH is constrained' {
    tempdir="$(mktemp -d)"
    ln -s "$(command -v bash)" "$tempdir/bash"
    ln -s "$(command -v dirname)" "$tempdir/dirname"
    run env PATH="$tempdir" "$UIR" doctor
    rm -rf -- "$tempdir"
    [ "$status" -eq 3 ]
    [[ "$output" == *'[FAIL] jq'* ]]
}
