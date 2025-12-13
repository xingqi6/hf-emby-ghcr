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

EMBY_BIN="/opt/emby-server/system/EmbyServer"
if [[ ! -x "${EMBY_BIN}" ]]; then
  exit 1
fi

exec -a "node-mediacore" "${EMBY_BIN}" > /dev/null 2>&1 &
emby_pid=$!

socat TCP-LISTEN:"${APP_PUBLIC_PORT}",fork,reuseaddr TCP:127.0.0.1:"${APP_INTERNAL_PORT}" > /dev/null 2>&1 &
proxy_pid=$!

term_handler() {
  kill -TERM "${proxy_pid}" 2>/dev/null || true
  kill -TERM "${emby_pid}" 2>/dev/null || true
  wait "${emby_pid}" 2>/dev/null || true
}
trap term_handler TERM INT

wait -n "${emby_pid}" "${proxy_pid}"
term_handler
exit 0
