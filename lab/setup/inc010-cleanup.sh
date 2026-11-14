
#!/usr/bin/env bash
set -euo pipefail

LAB="$HOME/.local/share/uir-network-lab-010"
UNIT="/etc/systemd/system/uir-training-010.service"
SERVICE="uir-training-010.service"

# Verify resources belong to our training lab
if [[ ! -d "$LAB" || -L "$LAB" ||
      ! -f "$UNIT" || -L "$UNIT" ]]; then
    echo "STOP: Unexpected lab resources."
    exit 1
fi

sudo grep -Fxq \
    'Description=UIR INC-010 Isolated Network Training Service' \
    "$UNIT" || {
    echo "STOP: Unit identity mismatch."
    exit 1
}

# Require preserved evidence and archive
test -f "$HOME/INC-010-handoff.tar.gz"
test -f "$HOME/.local/share/ubuntu-irt/incidents/INC-010/report.md"
test -f "$HOME/.local/share/ubuntu-irt/lab-evidence/INC-010/http-after.txt"

# Stop only the disposable service
sudo systemctl stop "$SERVICE"

if [[ -n "$(ss -H -lnt '( sport = :18110 )')" ]]; then
    echo "STOP: Training port is still occupied."
    exit 1
fi

sudo rm -- "$UNIT"
sudo systemctl daemon-reload

if [[ "$(systemctl show "$SERVICE" -p LoadState --value)" != "not-found" ]]; then
    echo "STOP: Unit still loaded."
    exit 1
fi

rm -r -- "$LAB"

echo "PASS: INC-010 training environment removed."
