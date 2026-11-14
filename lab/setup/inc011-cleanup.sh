
#!/usr/bin/env bash
set -euo pipefail

LAB="$HOME/.local/share/uir-logging-lab-011"
UNIT="/etc/systemd/system/uir-training-011.service"
SERVICE="uir-training-011.service"
STORE="$HOME/.local/share/ubuntu-irt"

# Verify the training resources
if [[ ! -d "$LAB" || -L "$LAB" ||
      ! -f "$UNIT" || -L "$UNIT" ]]; then
    echo "STOP: Unexpected training resources."
    exit 1
fi

sudo grep -Fxq \
    'Description=UIR INC-011 Isolated Logging Training Service' \
    "$UNIT" || {
    echo "STOP: Training unit identity mismatch."
    exit 1
}

# Require preserved evidence and archive
test -f "$HOME/INC-011-handoff.tar.gz"
test -f "$STORE/incidents/INC-011/report.md"
test -f "$STORE/lab-evidence/INC-011/journal-before.txt"
test -f "$STORE/lab-evidence/INC-011/journal-after.txt"

# Stop only our disposable service

# Stop only our verified disposable service
sudo systemctl stop "$SERVICE"

# Clear any retained systemd failure state
sudo systemctl reset-failed "$SERVICE"

# Verify the unit is no longer active
if [[ "$(systemctl show "$SERVICE" \
    -p ActiveState --value)" != "inactive" ]]; then
    echo "STOP: Service still active."
    exit 1
fi

# Remove dedicated systemd unit
sudo rm -- "$UNIT"
sudo systemctl daemon-reload

if [[ "$(systemctl show "$SERVICE" \
    -p LoadState --value)" != "not-found" ]]; then
    echo "STOP: Training unit still loaded."
    exit 1
fi

# Remove disposable files
rm -r -- "$LAB"

echo "PASS: INC-011 training environment removed."
