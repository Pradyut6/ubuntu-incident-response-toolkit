
#!/usr/bin/env bash
set -euo pipefail
umask 077

LAB="$HOME/.local/share/uir-dependency-lab-012"
APP="/etc/systemd/system/uir-training-012-app.service"
DEP="/etc/systemd/system/uir-training-012-dependency.service"

APP_NAME="uir-training-012-app.service"
DEP_NAME="uir-training-012-dependency.service"

# Verify we are not running as root
if [[ "$(id -u)" -eq 0 ]]; then
    echo "STOP: Run as your normal user."
    exit 1
fi

# Refuse to overwrite any existing training resources
for path in "$LAB" "$APP" "$DEP"; do
    if [[ -e "$path" || -L "$path" ]]; then
        echo "STOP: Existing resource: $path"
        exit 1
    fi
done

# Check systemd for existing units
for unit in "$APP_NAME" "$DEP_NAME"; do
    if [[ "$(systemctl show "$unit" \
        -p LoadState --value)" != "not-found" ]]; then
        echo "STOP: Existing unit: $unit"
        exit 1
    fi
done

mkdir -m 700 "$LAB"

# Dependency deliberately fails with exit status 1
sudo tee "$DEP" >/dev/null <<EOF
[Unit]
Description=UIR INC-012 Disposable Dependency Service

[Service]
Type=oneshot
ExecStart=/usr/bin/false
RemainAfterExit=yes
Restart=no
NoNewPrivileges=yes
MemoryMax=64M
TasksMax=16
EOF

# Application requires successful dependency startup
sudo tee "$APP" >/dev/null <<EOF
[Unit]
Description=UIR INC-012 Dependent Application Service
Requires=$DEP_NAME
After=$DEP_NAME

[Service]
Type=exec
User=$(id -un)
ExecStart=/usr/bin/sleep infinity
Restart=no
NoNewPrivileges=yes
PrivateTmp=yes
MemoryMax=64M
TasksMax=16
EOF

sudo systemctl daemon-reload

echo "PASS: INC-012 dependency lab created."
echo "Both services remain stopped."
