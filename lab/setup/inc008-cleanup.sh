
#!/usr/bin/env bash
set -euo pipefail

LAB="$HOME/.local/share/uir-nginx-lab-008"
PROXY="/etc/systemd/system/uir-training-008-proxy.service"
BACKEND="/etc/systemd/system/uir-training-008-upstream.service"

# Verify the training files
if [[ ! -d "$LAB" || -L "$LAB" ]]; then
    echo "STOP: Unexpected lab directory."
    exit 1
fi

for unit in "$PROXY" "$BACKEND"; do
    if [[ ! -f "$unit" || -L "$unit" ]]; then
        echo "STOP: Unexpected training unit: $unit"
        exit 1
    fi
done

sudo grep -Fxq \
    'Description=UIR INC-008 Isolated Nginx Proxy' "$PROXY"

sudo grep -Fxq \
    'Description=UIR INC-008 Disposable HTTP Backend' "$BACKEND"

# Stop only our disposable services
sudo systemctl stop uir-training-008-proxy.service
sudo systemctl stop uir-training-008-upstream.service

# Verify neither training port remains occupied
if [[ -n "$(ss -H -lnt '( sport = :18088 or sport = :18089 )')" ]]; then
    echo "STOP: Training port still occupied."
    exit 1
fi

# Remove training units
sudo rm -- "$PROXY" "$BACKEND"
sudo systemctl daemon-reload

# Confirm systemd no longer loads these units
for unit in uir-training-008-proxy.service uir-training-008-upstream.service; do
    if [[ "$(systemctl show "$unit" -p LoadState --value)" != "not-found" ]]; then
        echo "STOP: Training unit still loaded: $unit"
        exit 1
    fi
done

# Remove only the disposable training directory
rm -r -- "$LAB"

echo "PASS: INC-008 training environment removed."
