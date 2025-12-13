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
mkdir -p "${DATA_DIR}/programdata"
mkdir -p /var/www/html
mkdir -p /tmp/nginx_client_body
mkdir -p /tmp/nginx_proxy
mkdir -p /tmp/nginx_fastcgi
mkdir -p /tmp/nginx_uwsgi
mkdir -p /tmp/nginx_scgi

# 确保符号链接正确
if [ -e /opt/emby-server/programdata ] && [ ! -L /opt/emby-server/programdata ]; then
  rm -rf /opt/emby-server/programdata
fi
ln -sfn "${DATA_DIR}/programdata" /opt/emby-server/programdata

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
  echo "Error: EmbyServer binary not found"
  exit 1
fi

# 设置环境变量
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
export MONO_THREADS_PER_CPU=50
export MALLOC_CHECK_=0

# 启动主服务 - 使用默认配置路径
"${APP_BIN}" --ffmpeg /usr/bin/ffmpeg 2>&1 | grep -v "emby" | grep -v "Emby" || true &
app_pid=$!

echo "Starting services..."
sleep 8

# 检查进程是否还在运行
if ! kill -0 "${app_pid}" 2>/dev/null; then
  echo "Error: Main process failed to start, trying again..."
  "${APP_BIN}" --ffmpeg /usr/bin/ffmpeg 2>&1 &
  app_pid=$!
  sleep 5
fi

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

# 监控进程
while true; do
  if ! kill -0 "${app_pid}" 2>/dev/null; then
    echo "Main process died, restarting..."
    sleep 5
    "${APP_BIN}" --ffmpeg /usr/bin/ffmpeg 2>&1 | grep -v "emby" | grep -v "Emby" || true &
    app_pid=$!
  fi
  
  if ! kill -0 "${nginx_pid}" 2>/dev/null; then
    echo "Nginx died, restarting..."
    nginx -c /etc/nginx/nginx.conf -g "daemon off;" 2>&1 &
    nginx_pid=$!
  fi
  
  sleep 10
done
