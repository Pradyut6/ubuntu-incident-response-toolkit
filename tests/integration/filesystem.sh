#!/usr/bin/env bash
# Offline, no-root filesystem probe. Never mounts, deletes or fills any filesystem.
set -euo pipefail
((EUID != 0)) || {
    echo 'Run filesystem probe tests as a regular user' >&2
    exit 1
}
PROJECT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
UIR="$PROJECT/bin/uir"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
export XDG_DATA_HOME="$T/data"
mkdir -m 700 "$XDG_DATA_HOME" "$T/target"
"$UIR" init >/dev/null
"$UIR" incident create --id INC-821 --service host --severity low >/dev/null
"$UIR" incident create --id INC-822 --service host --severity low >/dev/null

# Reject malformed paths, traversal and symlink components before creating evidence.
ln -s "$T/target" "$T/alias"
for invalid in '' 'relative' '/definitely-not-a-UIRT-path-821' "$T/target/../target" "$T/alias" '/tmp/a;id' "$T/target/"; do
    if "$UIR" capture --incident INC-821 --phase before --fs-path "$invalid" >"$T/rejected.log" 2>&1; then
        echo "FAIL: accepted invalid filesystem selection" >&2
        exit 1
    fi
done
if "$UIR" capture --incident INC-821 --phase before --fs-path "$T/target" --fs-path "$T/target" >/dev/null 2>&1; then
    echo 'FAIL: duplicate --fs-path accepted' >&2
    exit 1
fi
[[ ! -e "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-821/before" ]]
printf 'PASS: unsafe filesystem target paths rejected before snapshot\n'

# GNU stat can report an ext4 filesystem type as "ext2/ext3".
"$UIR" incident create --id INC-823 --service host --severity low >/dev/null
mkdir -m 700 "$T/fakebin"
cat >"$T/fakebin/stat" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == -f && "${2-}" == -c && "${3-}" == '%S %b %f %a %c %d %T' ]]; then
    printf '%s\n' '4096 1000 400 300 100 80 ext2/ext3'
else
    exec /usr/bin/stat "$@"
fi
EOF
chmod 700 "$T/fakebin/stat"
PATH="$T/fakebin:$PATH" "$UIR" capture --incident INC-823 --phase before --fs-path "$T/target" --minutes 1 >/dev/null
jq -e '.capture_status=="complete" and .filesystem.status=="observed" and
       .filesystem.fs_type=="ext2/ext3" and .filesystem.size_bytes==4096000' \
    "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-823/before/snapshot.json" >/dev/null
printf 'PASS: Ubuntu ext4 filesystem label with slash accepted\n'

# Independently verify TCP and filesystem diagnostics coexist.
"$UIR" incident create --id INC-824 --service host --severity low >/dev/null
"$UIR" capture --incident INC-824 --phase before --fs-path "$T/target" \
    --listen-port 18111 --expect-address 127.0.0.1 --minutes 1 >/dev/null
mixed="$XDG_DATA_HOME/ubuntu-irt/incidents/INC-824/before"
jq -e '.capture_status=="complete" and .filesystem.status=="observed" and
       .tcp_listener.protocol=="tcp" and .collector_results.filesystem.exit==0 and
       .collector_results.tcp.exit==0' "$mixed/snapshot.json" >/dev/null
if ! gzip -cd "$mixed/diagnostics.txt.gz" | grep -Fq '[TCP listener port=18111'; then
    echo 'FAIL: TCP diagnostic lost during combined filesystem capture' >&2
    exit 1
fi
printf 'PASS: TCP and filesystem diagnostics coexist in one capture\n'

"$UIR" capture --incident INC-821 --phase before --fs-path "$T/target" --minutes 1 >/dev/null
before="$XDG_DATA_HOME/ubuntu-irt/incidents/INC-821/before/snapshot.json"
jq -e '.capture_status=="complete" and .collector_results.filesystem.exit==0 and
      .filesystem.status=="observed" and .filesystem.scope=="selected_directory_filesystem" and
      (.filesystem.target_sha256|test("^[0-9a-f]{64}$")) and
      (.filesystem.size_bytes>0) and (.filesystem.available_bytes>=0) and
      (.filesystem.used_bytes>=0) and (.filesystem.used_percent>=0) and
      (.filesystem.inodes_total==null or .filesystem.inodes_total>0)' "$before" >/dev/null
if grep -Fq "$T/target" "$before"; then
    echo 'FAIL: private filesystem target path leaked into snapshot' >&2
    exit 1
fi
printf 'PASS: targeted filesystem metrics captured without raw path\n'

# Write only a small file within a disposable test directory, never fill a mount.
printf 'small harmless fixture\n' >"$T/target/fixture.txt"
"$UIR" capture --incident INC-821 --phase after --fs-path "$T/target" --minutes 1 >/dev/null
"$UIR" compare --incident INC-821 >"$T/comparison.json"
jq -e '.filesystem_target_comparable==true and
      .changes.filesystem_status.before=="observed" and .changes.filesystem_status.after=="observed" and
      .changes.filesystem_target.before==.changes.filesystem_target.after and
      .changes.filesystem_available_bytes.before>=0 and
      .changes.filesystem_inodes_available.after>=0' "$T/comparison.json" >/dev/null
"$UIR" report --incident INC-821 >/dev/null
grep -Fq 'filesystem status=observed' "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-821/report.md"
if "$UIR" capture --incident INC-821 --phase before --fs-path "$T/target" >/dev/null 2>&1; then
    echo 'FAIL: immutable before snapshot overwritten' >&2
    exit 1
fi
printf 'PASS: filesystem before/after comparison and immutable snapshots\n'

"$UIR" capture --incident INC-822 --phase before --fs-path "$T/target" --minutes 1 >/dev/null
"$UIR" capture --incident INC-822 --phase after --minutes 1 >/dev/null
"$UIR" compare --incident INC-822 >"$T/incomplete.json"
jq -e '.filesystem_target_comparable==false and .changes.filesystem_status.after==null' "$T/incomplete.json" >/dev/null
"$UIR" report --incident INC-822 >/dev/null
grep -Fq 'Filesystem comparison caution' "$XDG_DATA_HOME/ubuntu-irt/incidents/INC-822/report.md"
printf 'PASS: unmatched filesystem probe phases are marked not comparable\n'

"$UIR" export --incident INC-821 --output "$T/handoff.tar.gz" >/dev/null
mkdir -m 700 "$T/unpacked"
tar -xzf "$T/handoff.tar.gz" -C "$T/unpacked"
(cd "$T/unpacked" && sha256sum -c SHA256SUMS) >"$T/hashcheck"
jq -e '.filesystem.status=="observed" and (.filesystem.target_sha256|test("^[0-9a-f]{64}$"))' \
    "$T/unpacked/after/snapshot.json" >/dev/null
if grep -R -Fq "$T/target" "$T/unpacked"; then
    echo 'FAIL: filesystem target leaked into public archive' >&2
    exit 1
fi
printf 'PASS: filesystem metrics exported with verified hashes and no raw target path\n'
printf 'All filesystem probe integration checks passed.\n'
