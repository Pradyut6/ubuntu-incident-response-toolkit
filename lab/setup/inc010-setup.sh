
#!/usr/bin/env bash
set -euo pipefail
umask 077

LAB="$HOME/.local/share/uir-network-lab-010"
UNIT="/etc/systemd/system/uir-training-010.service"
SERVICE="uir-training-010.service"
PORT=18110

PYTHON="$(command -v python3)"

# Refuse existing lab resources
if [[ -e "$LAB" || -L "$LAB" ||
      -e "$UNIT" || -L "$UNIT" ]]; then
    echo "STOP: INC-010 resources already exist."
    exit 1
fi

if [[ "$(systemctl show "$SERVICE" \
    -p LoadState --value)" != "not-found" ]]; then
    echo "STOP: Training service already exists."
    exit 1
fi

if [[ -n "$(ss -H -lnt "( sport = :$PORT )")" ]]; then
    echo "STOP: Port $PORT is occupied."
    exit 1
fi

# Create private training files
mkdir -m 700 "$LAB"
mkdir -m 700 "$LAB/www"

printf 'UIR INC-010 network recovery verified\n' \
    > "$LAB/www/index.html"

# Deliberately bind to the wrong loopback address
sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=UIR INC-010 Isolated Network Training Service

[Service]
Type=simple
User=$(id -un)
ExecStart=$PYTHON -m http.server $PORT --bind 127.0.0.2 --directory $LAB/www
Restart=no
NoNewPrivileges=yes
PrivateTmp=yes
MemoryMax=64M
TasksMax=16
EOF

sudo systemctl daemon-reload

echo "PASS: INC-010 training environment created."
echo "Service remains stopped."
