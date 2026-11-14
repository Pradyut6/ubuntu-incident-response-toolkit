
#!/usr/bin/env bash
set -euo pipefail

LAB="$HOME/.local/share/uir-dns-lab-009"
UNIT="/etc/systemd/system/uir-training-009.service"
SERVICE="uir-training-009.service"

# Verify the disposable training resources
if [[ ! -d "$LAB" || -L "$LAB" ||
      ! -f "$UNIT" || -L "$UNIT" ]]; then
    echo "STOP: Unexpected training resources."
    exit 1
fi

sudo grep -Fxq \
    'Description=UIR INC-009 Isolated DNS Training Service' \
    "$UNIT" || {
    echo "STOP: Training unit identity mismatch."
    exit 1
}

# Stop the isolated resolver
sudo systemctl stop "$SERVICE"

# Ensure UDP port 15353 is no longer bound
if [[ -n "$(ss -H -lun '( sport = :15353 )')" ]]; then
    echo "STOP: DNS training port remains occupied."
    exit 1
fi

# Remove the dedicated service definition
sudo rm -- "$UNIT"
sudo systemctl daemon-reload

if [[ "$(systemctl show "$SERVICE" -p LoadState --value)" != "not-found" ]]; then
    echo "STOP: Training service is still loaded."
    exit 1
fi

# Remove only disposable training files
rm -r -- "$LAB"

echo "PASS: INC-009 DNS training environment removed."
