
#!/usr/bin/env bash
set -euo pipefail
umask 077

LAB="$HOME/.local/share/uir-ssh-lab-002"
UNIT="/etc/systemd/system/uir-training-002.service"

# Preflight safety checks
if [[ -e "$LAB" || -L "$LAB" || -e "$UNIT" || -L "$UNIT" ]]; then
    echo "STOP: Existing training files detected."
    exit 1
fi

if [[ ! -d /run/sshd ]]; then
    echo "STOP: /run/sshd is missing."
    exit 1
fi

if [[ -n "$(ss -H -lnt '( sport = :22222 )')" ]]; then
    echo "STOP: Port 22222 is occupied."
    exit 1
fi

# Create private training directory and key
mkdir -m 700 "$LAB"
ssh-keygen -q -t ed25519 -N '' -f "$LAB/host_ed25519_key"

# Create deliberately invalid SSH configuration
cat > "$LAB/sshd_config" <<EOF
Port 22222
ListenAddress 127.0.0.1
AddressFamily inet
HostKey $LAB/host_ed25519_key
PidFile $LAB/sshd.pid
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile /dev/null
AllowUsers uir-nonexistent-002
PermitRootLogin no
UsePAM no
AllowTcpForwarding no
X11Forwarding no
LoginGraceTime 10
LogLevel VERBOSE
BadDirectiveForUIR yes
EOF

# Create dedicated systemd training service
sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=UIR INC-002 Isolated SSH Training Service

[Service]
Type=simple
User=$(id -un)
ExecStart=/usr/sbin/sshd -D -e -f $LAB/sshd_config
Restart=no
NoNewPrivileges=yes
MemoryMax=128M
TasksMax=32
EOF

sudo systemctl daemon-reload

echo "PASS: Isolated SSH training environment created."
