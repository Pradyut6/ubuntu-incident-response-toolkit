
#!/usr/bin/env bash
set -euo pipefail

LAB="$HOME/.local/share/uir-dependency-lab-012"
APP="/etc/systemd/system/uir-training-012-app.service"
DEP="/etc/systemd/system/uir-training-012-dependency.service"

APP_SERVICE="uir-training-012-app.service"
DEP_SERVICE="uir-training-012-dependency.service"

STORE="$HOME/.local/share/ubuntu-irt"

# Verify the expected lab and unit files
if [[ ! -d "$LAB" || -L "$LAB" ||
      ! -f "$APP" || -L "$APP" ||
      ! -f "$DEP" || -L "$DEP" ]]; then
    echo "STOP: Unexpected training resources."
    exit 1
fi

# Verify the exact identities of both units
sudo grep -Fxq \
    'Description=UIR INC-012 Dependent Application Service' \
    "$APP" || exit 1

sudo grep -Fxq \
    'Description=UIR INC-012 Disposable Dependency Service' \
    "$DEP" || exit 1

# Ensure incident evidence is preserved
test -f "$STORE/incidents/INC-012/report.md"
test -f "$HOME/INC-012-handoff.tar.gz"
test -f "$STORE/lab-evidence/INC-012/app-before.txt"
test -f "$STORE/lab-evidence/INC-012/dependency-after.txt"

# Stop the application before its dependency
sudo systemctl stop "$APP_SERVICE"
sudo systemctl stop "$DEP_SERVICE"

# Confirm neither service remains running
for service in "$APP_SERVICE" "$DEP_SERVICE"; do
    state="$(systemctl show "$service" -p ActiveState --value)"

    if [[ "$state" != "inactive" && "$state" != "failed" ]]; then
        echo "STOP: Service not stopped: $service ($state)"
        exit 1
    fi
done


# Remove only the two dedicated training units
sudo rm -- "$APP" "$DEP"
sudo systemctl daemon-reload

for service in "$APP_SERVICE" "$DEP_SERVICE"; do
    if [[ "$(systemctl show "$service" -p LoadState --value)" != "not-found" ]]; then
        echo "STOP: Unit still loaded: $service"
        exit 1
    fi
done

# Remove only the isolated lab directory
rm -r -- "$LAB"

echo "PASS: INC-012 training environment removed."
