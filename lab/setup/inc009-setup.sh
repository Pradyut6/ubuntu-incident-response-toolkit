
#!/usr/bin/env bash
set -euo pipefail
umask 077

LAB="$HOME/.local/share/uir-dns-lab-009"
UNIT="/etc/systemd/system/uir-training-009.service"
SOURCE="lab/setup/inc009-dns.py"

# Verify prerequisites
if [[ ! -f "$SOURCE" || -L "$SOURCE" ]]; then
    echo "STOP: Python DNS application missing."
    exit 1
fi

if [[ -e "$LAB" || -L "$LAB" ||
      -e "$UNIT" || -L "$UNIT" ]]; then
    echo "STOP: Training files already exist."
    exit 1
fi

if [[ "$(systemctl show uir-training-009.service \
    -p LoadState --value)" != "not-found" ]]; then
    echo "STOP: Training service already exists."
    exit 1
fi

if [[ -n "$(ss -H -lun '( sport = :15353 )')" ]]; then
    echo "STOP: UDP port 15353 is occupied."
    exit 1
fi

# Create a private, isolated application directory
mkdir -m 700 "$LAB"

install -m 600 "$SOURCE" "$LAB/dns_lab.py"

PYTHON="$(command -v python3)"

# Dedicated disposable systemd service
sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=UIR INC-009 Isolated DNS Training Service

[Service]
Type=simple
User=$(id -un)
ExecStart=$PYTHON -u $LAB/dns_lab.py serve
Restart=no
NoNewPrivileges=yes
UMask=0077
MemoryMax=64M
TasksMax=16
EOF

sudo systemctl daemon-reload

echo "PASS: INC-009 DNS training environment created."
echo "DNS service remains stopped."
