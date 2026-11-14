#!/usr/bin/env bash
# H07 security regression: bounded decompression, privacy of exported metadata,
# and honest comparability for failed filesystem collections.
set -euo pipefail
((EUID != 0)) || {
    echo 'Run H07 checks as an ordinary user' >&2
    exit 1
}
PROJECT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
UIR="$PROJECT/bin/uir"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
export XDG_DATA_HOME="$T/data"
mkdir -m 700 "$XDG_DATA_HOME" "$T/target"
"$UIR" init >/dev/null
"$UIR" incident create --id INC-871 --service host --severity low >/dev/null
"$UIR" capture --incident INC-871 --phase before --fs-path "$T/target" --minutes 1 >/dev/null
"$UIR" capture --incident INC-871 --phase after --fs-path "$T/target" --minutes 1 >/dev/null
DIR="$XDG_DATA_HOME/ubuntu-irt/incidents/INC-871"
DIAG="$DIR/before/diagnostics.txt.gz"
cp -- "$DIAG" "$T/original.gz"

# Concatenated gzip members: gzip -l reports 8 MiB, real output is 16 MiB.
python3 - "$DIAG" <<'PY'
import gzip, sys
with open(sys.argv[1], 'wb') as out:
    for _ in range(2):
        out.write(gzip.compress(b'X' * (8 * 1024 * 1024), mtime=0))
PY
reported="$(gzip -l "$DIAG" | awk 'NR==2 {print $2}')"
[[ "$reported" == 8388608 ]] || {
    echo 'FAIL: gzip fixture unexpected size' >&2
    exit 1
}
if "$UIR" export --incident INC-871 --preview >"$T/preview-out" 2>&1; then
    echo 'FAIL: preview accepted an oversized concatenated gzip stream' >&2
    exit 1
fi
if "$UIR" export --incident INC-871 --output "$T/oversized.tar.gz" >"$T/out" 2>&1; then
    echo 'FAIL: concatenated gzip output bypassed 12 MiB bound' >&2
    exit 1
fi
[[ ! -e "$T/oversized.tar.gz" ]] || {
    echo 'FAIL: rejected export created an archive' >&2
    exit 1
}
printf 'PASS: concatenated gzip members cannot bypass actual decompressed-byte limit\n'
cp -- "$T/original.gz" "$DIAG"

# Inject only synthetic network metadata into a disposable private snapshot.
SNAP="$DIR/before/snapshot.json"
jq '.host.network.interfaces="inet6 2001:db8::1234/64" |
    .host.network.routes="2001:db8::/64 via fe80::1" |
    .host.host_pseudonym="known-host-synthetic" |
    .tcp_listener={addresses:["2001:db8::1234","127.0.0.1"],expected_address:"::1"}' \
    "$SNAP" >"$T/changed.json"
cat "$T/changed.json" >"$SNAP"
"$UIR" compare --incident INC-871 >"$T/comparison-private.json"
"$UIR" export --incident INC-871 --output "$T/accepted.tar.gz" >/dev/null
mkdir -m 700 "$T/unpacked"
tar -xzf "$T/accepted.tar.gz" -C "$T/unpacked"
(cd "$T/unpacked" && sha256sum -c SHA256SUMS >/dev/null)
jq -e '.host.network.interfaces=="[REDACTED_NETWORK_METADATA]" and
  .host.host_pseudonym=="[REDACTED_HOST_ID]" and
  .tcp_listener.addresses[0]=="[REDACTED_IPv6]" and
  .tcp_listener.addresses[1]=="[REDACTED_IPv4]" and
  .tcp_listener.expected_address=="[REDACTED_IPv6]"' \
    "$T/unpacked/before/snapshot.json" >/dev/null
if grep -R -nE '2001:db8|fe80::1|known-host-synthetic' "$T/unpacked"; then
    echo 'FAIL: public archive leaks synthetic machine/network metadata' >&2
    exit 1
fi
printf 'PASS: public snapshot omits host identifiers and raw IPv6 endpoint metadata\n'
printf 'PASS: normal archive exported with verified SHA-256 manifest\n'

# A failed filesystem probe with the same target must not be called comparable.
AFTER="$DIR/after/snapshot.json"
jq '.filesystem.status="collector_error" | .filesystem.stat_exit=5' "$AFTER" >"$T/changed.json"
cat "$T/changed.json" >"$AFTER"
"$UIR" compare --incident INC-871 >"$T/comparison-partial.json"
jq -e '.filesystem_target_comparable==false and .changes.filesystem_status.after=="collector_error"' \
    "$T/comparison-partial.json" >/dev/null
printf 'PASS: failed filesystem collection is not labeled comparable\n'
printf 'All H07 security integration checks passed.\n'
