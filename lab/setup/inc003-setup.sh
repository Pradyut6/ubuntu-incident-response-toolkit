
#!/usr/bin/env bash
set -euo pipefail
umask 077

LAB="$HOME/.local/share/uir-nginx-lab-003"
UNIT="/etc/systemd/system/uir-training-003.service"
PORT=18083

# Refuse to overwrite existing lab files
if [[ -e "$LAB" || -L "$LAB" || -e "$UNIT" || -L "$UNIT" ]]; then
    echo "STOP: Existing INC-003 training files found."
    exit 1
fi

NGINX="$(command -v nginx)" || {
    echo "STOP: nginx is not installed."
    exit 1
}

if [[ -n "$(ss -H -lnt "( sport = :$PORT )")" ]]; then
    echo "STOP: Training port $PORT is already in use."
    exit 1
fi

# Create isolated directories and sample content
mkdir -m 700 "$LAB"
mkdir -m 700 "$LAB/logs" "$LAB/www"

printf 'UIR INC-003 training page\n' > "$LAB/www/index.html"

# Simulate an unreadable web document
chmod 000 "$LAB/www/index.html"

# Dedicated Nginx configuration
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
    }
}
EOF

chmod 600 "$LAB/nginx.conf"

# Validate configuration before installation
"$NGINX" -t -p "$LAB/" -c nginx.conf

# Create a separate non-root training service
sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=UIR INC-003 Isolated Nginx Training Service

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

echo "PASS: Isolated Nginx lab created; service not started."
