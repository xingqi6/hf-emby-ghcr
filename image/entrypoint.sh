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

exec -a "node-mediacore" "${APP_BIN}" > /dev/null 2>&1 &
app_pid=$!

nginx -g "daemon off;" > /dev/null 2>&1 &
nginx_pid=$!

term_handler() {
  kill -TERM "${nginx_pid}" 2>/dev/null || true
  kill -TERM "${app_pid}" 2>/dev/null || true
  wait "${app_pid}" 2>/dev/null || true
}
trap term_handler TERM INT

wait -n "${app_pid}" "${nginx_pid}"
term_handler
exit 0
