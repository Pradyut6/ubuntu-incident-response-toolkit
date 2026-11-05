#!/usr/bin/env bats
setup() { UIR="$BATS_TEST_DIRNAME/../../bin/uir"; }
@test 'help displays implemented commands' {
    run "$UIR" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'incident search'* ]]
    [[ "$output" == *'retention prune'* ]]
}
@test 'no-argument invocation displays help' {
    run "$UIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Usage:'* ]]
}
@test 'version is predictable' {
    run "$UIR" --version
    [ "$status" -eq 0 ]
    [ "$output" = 'uir 1.0.0-rc1' ]
}
@test 'unknown command is rejected, not executed' {
    run "$UIR" 'hello;touch /tmp/uir-unsafe'
    [ "$status" -eq 2 ]
    [[ "$output" == *'unknown command'* ]]
}
@test 'capture has required explicit arguments' {
    run "$UIR" capture
    [ "$status" -eq 2 ]
    [[ "$output" == *'usage: capture'* ]]
}
@test 'export requires explicit incident and destination or preview' {
    run "$UIR" export
    [ "$status" -eq 2 ]
}
@test 'unexpected arguments are rejected' {
    run "$UIR" doctor --some-option
    [ "$status" -eq 2 ]
}
