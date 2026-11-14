
#!/usr/bin/env bash
set -euo pipefail
umask 077

LAB="$HOME/.local/share/uir-logging-lab-011"
UNIT="/etc/systemd/system/uir-training-011.service"
SERVICE="uir-training-011.service"

if [[ -e "$LAB" || -L "$LAB" ||
      -e "$UNIT" || -L "$UNIT" ]]; then
    echo "STOP: Training resources already exist."
    exit 1
fi

if [[ "$(systemctl show "$SERVICE" \
    -p LoadState --value)" != "not-found" ]]; then
    echo "STOP: Training unit already loaded."
    exit 1
fi

mkdir -m 700 "$LAB"

# Disposable application with identifiable log messages
cat > "$LAB/app.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'UIR-INC-011-APP-STARTED stdout\n'
printf 'UIR-INC-011-APP-READY stderr\n' >&2

exec /usr/bin/sleep 3600
EOF

chmod 700 "$LAB/app.sh"

# Deliberately suppress application output
sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=UIR INC-011 Isolated Logging Training Service

[Service]
Type=simple
User=$(id -un)
ExecStart=/usr/bin/bash $LAB/app.sh
StandardOutput=null
StandardError=null
Restart=no
NoNewPrivileges=yes
PrivateTmp=yes
MemoryMax=64M
TasksMax=16
RuntimeMaxSec=1h
EOF

sudo systemctl daemon-reload

echo "PASS: INC-011 training environment created."
echo "Service remains stopped."
