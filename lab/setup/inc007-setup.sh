
#!/usr/bin/env bash
set -euo pipefail
umask 077

LAB="$HOME/.local/share/uir-nginx-lab-007"
UNIT="/etc/systemd/system/uir-training-007.service"
PORT=18087

NGINX="$(command -v nginx)"

# Refuse existing files and occupied ports
if [[ -e "$LAB" || -L "$LAB" ||
      -e "$UNIT" || -L "$UNIT" ]]; then
    echo "STOP: Existing INC-007 training files."
    exit 1
fi

if [[ -n "$(ss -H -lnt "( sport = :$PORT )")" ]]; then
    echo "STOP: Training port already occupied."
    exit 1
fi

if [[ "$(systemctl show uir-training-007.service \
    -p LoadState --value)" != "not-found" ]]; then
    echo "STOP: Training systemd unit already exists."
    exit 1
fi

# Create disposable private directories
mkdir -m 700 "$LAB"
mkdir -m 700 "$LAB/logs" "$LAB/www"

printf 'UIR INC-007 recovery verified\n' \
    > "$LAB/www/index.html"

# Deliberately faulty Nginx configuration
cat > "$LAB/nginx.conf" <<EOF
worker_processes 1;
daemon off;
pid $LAB/nginx.pid;
error_log $LAB/logs/error.log notice;

events {
    worker_connections 128;
}

http {
    access_log $LAB/logs/access.log;

    server {
        listen 127.0.0.1:$PORT;
        server_name localhost;
        root $LAB/www;
        index index.html;

        UIRInvalidDirective on;
    }
}
EOF

# Verify the intended configuration failure
if "$NGINX" -t -p "$LAB/" -c nginx.conf \
    >"$LAB/config-test-before.txt" 2>&1; then
    echo "STOP: Configuration unexpectedly passed."
    exit 1
fi

if ! grep -q 'unknown directive' \
    "$LAB/config-test-before.txt"; then
    echo "STOP: Unexpected configuration error."
    cat "$LAB/config-test-before.txt"
    exit 1
fi

# Install the isolated training service
sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=UIR INC-007 Isolated Nginx Training Service

[Service]
Type=simple
User=$(id -un)
ExecStart=$NGINX -p $LAB/ -c nginx.conf
Restart=no
NoNewPrivileges=yes
MemoryMax=128M
TasksMax=32
EOF

sudo systemctl daemon-reload

echo "PASS: Isolated faulty Nginx service created."
