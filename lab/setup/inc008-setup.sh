
#!/usr/bin/env bash
set -euo pipefail
umask 077

LAB="$HOME/.local/share/uir-nginx-lab-008"
PROXY_UNIT="/etc/systemd/system/uir-training-008-proxy.service"
BACKEND_UNIT="/etc/systemd/system/uir-training-008-upstream.service"

NGINX="$(command -v nginx)"
PYTHON="$(command -v python3)"

# Safety checks
for path in "$LAB" "$PROXY_UNIT" "$BACKEND_UNIT"; do
    if [[ -e "$path" || -L "$path" ]]; then
        echo "STOP: Training path already exists: $path"
        exit 1
    fi
done

for port in 18088 18089; do
    if [[ -n "$(ss -H -lnt "( sport = :$port )")" ]]; then
        echo "STOP: Port $port is occupied."
        exit 1
    fi
done

for unit in uir-training-008-proxy.service uir-training-008-upstream.service; do
    if [[ "$(systemctl show "$unit" -p LoadState --value)" != "not-found" ]]; then
        echo "STOP: Existing systemd unit detected: $unit"
        exit 1
    fi
done

# Create private training files
mkdir -m 700 "$LAB"
mkdir -m 700 "$LAB/logs" "$LAB/www"

printf 'UIR INC-008 upstream recovered\n' > "$LAB/www/index.html"

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
        listen 127.0.0.1:18088;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:18089;
            proxy_connect_timeout 2s;
            proxy_read_timeout 3s;
            proxy_send_timeout 3s;
        }
    }
}
EOF

# Validate isolated Nginx configuration
"$NGINX" -t -p "$LAB/" -c nginx.conf

# Create disposable proxy unit
sudo tee "$PROXY_UNIT" >/dev/null <<EOF
[Unit]
Description=UIR INC-008 Isolated Nginx Proxy

[Service]
Type=simple
User=$(id -un)
ExecStart=$NGINX -p $LAB/ -c nginx.conf
Restart=no
NoNewPrivileges=yes
MemoryMax=128M
TasksMax=32
EOF

# Create disposable backend unit, but DO NOT start it
sudo tee "$BACKEND_UNIT" >/dev/null <<EOF
[Unit]
Description=UIR INC-008 Disposable HTTP Backend

[Service]
Type=simple
User=$(id -un)
ExecStart=$PYTHON -m http.server 18089 --bind 127.0.0.1 --directory $LAB/www
Restart=no
NoNewPrivileges=yes
MemoryMax=128M
TasksMax=32
EOF

sudo systemctl daemon-reload

echo "PASS: INC-008 environment created."
echo "Both services remain stopped."
