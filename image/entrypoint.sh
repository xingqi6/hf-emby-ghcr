#!/usr/bin/env bash
set -euo pipefail

: "${APP_PUBLIC_PORT:=7860}"
: "${APP_INTERNAL_PORT:=8096}"
: "${SYNC_INTERVAL:=3600}"
: "${KEEP_SNAPSHOTS:=5}"

: "${DATA_DIR:=/var/lib/mediacore}"
: "${WEBDAV_URL:=}"
: "${WEBDAV_USERNAME:=}"
: "${WEBDAV_PASSWORD:=}"
: "${WEBDAV_BACKUP_PATH:=}"

mkdir -p "${DATA_DIR}"
mkdir -p /var/www/html
mkdir -p /tmp/nginx_client_body
mkdir -p /tmp/nginx_proxy
mkdir -p /tmp/nginx_fastcgi
mkdir -p /tmp/nginx_uwsgi
mkdir -p /tmp/nginx_scgi

if [[ -n "${WEBDAV_URL}" && -n "${WEBDAV_USERNAME}" && -n "${WEBDAV_PASSWORD}" ]]; then
  python3 /backup.py restore \
    --data-dir "${DATA_DIR}" \
    --webdav-url "${WEBDAV_URL}" \
    --webdav-username "${WEBDAV_USERNAME}" \
    --webdav-password "${WEBDAV_PASSWORD}" \
    --webdav-backup-path "${WEBDAV_BACKUP_PATH}" \
    --keep "${KEEP_SNAPSHOTS}" > /dev/null 2>&1 || true

  python3 /backup.py daemon \
    --data-dir "${DATA_DIR}" \
    --webdav-url "${WEBDAV_URL}" \
    --webdav-username "${WEBDAV_USERNAME}" \
    --webdav-password "${WEBDAV_PASSWORD}" \
    --webdav-backup-path "${WEBDAV_BACKUP_PATH}" \
    --interval "${SYNC_INTERVAL}" \
    --keep "${KEEP_SNAPSHOTS}" > /dev/null 2>&1 &
fi

APP_BIN="/opt/emby-server/system/EmbyServer"
if [[ ! -x "${APP_BIN}" ]]; then
  exit 1
fi

# 启动主服务
exec -a "node-mediacore" "${APP_BIN}" > /dev/null 2>&1 &
app_pid=$!

# 等待服务启动
sleep 5

# 启动 nginx (前台运行)
nginx -c /etc/nginx/nginx.conf -g "daemon off;" 2>&1 &
nginx_pid=$!

echo "Service ready"

# 信号处理
term_handler() {
  echo "Shutting down..."
  kill -TERM "${nginx_pid}" 2>/dev/null || true
  kill -TERM "${app_pid}" 2>/dev/null || true
  wait "${app_pid}" 2>/dev/null || true
  exit 0
}
trap term_handler TERM INT

# 监控进程，如果任一进程退出则重启
while true; do
  if ! kill -0 "${app_pid}" 2>/dev/null; then
    echo "Main process died, restarting..."
    exec -a "node-mediacore" "${APP_BIN}" > /dev/null 2>&1 &
    app_pid=$!
  fi
  
  if ! kill -0 "${nginx_pid}" 2>/dev/null; then
    echo "Nginx died, restarting..."
    nginx -c /etc/nginx/nginx.conf -g "daemon off;" 2>&1 &
    nginx_pid=$!
  fi
  
  sleep 10
done
