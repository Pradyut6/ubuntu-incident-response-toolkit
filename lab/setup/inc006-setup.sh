
#!/usr/bin/env bash
set -euo pipefail
umask 077

LAB="$HOME/.local/share/uir-disk-lab-006"
MNT="$LAB/fs"

# Refuse to overwrite existing training data
if [[ -e "$LAB" || -L "$LAB" ]]; then
    echo "STOP: INC-006 lab already exists."
    exit 1
fi

if [[ "$(id -u)" -eq 0 ]]; then
    echo "STOP: Run this script as your normal user."
    exit 1
fi

# Create private training directories
mkdir -m 700 "$LAB"
mkdir -m 700 "$MNT"

# Mount only a 16 MiB memory-backed filesystem
if ! sudo mount -t tmpfs \
    -o "size=16m,uid=$(id -u),gid=$(id -g),mode=0700,nosuid,nodev,noexec" \
    tmpfs "$MNT"; then

    rmdir "$MNT" "$LAB"
    echo "STOP: tmpfs mount failed."
    exit 1
fi

# Verify the mount really is tmpfs
if ! mountpoint -q "$MNT" ||
   [[ "$(findmnt -n -o FSTYPE --mountpoint "$MNT")" != "tmpfs" ]]; then
    echo "STOP: Unexpected mount state. Inspect before continuing."
    exit 1
fi

echo "PASS: Isolated 16 MiB tmpfs created."
df -h "$MNT"