# Media Server 完整部署指南（混淆版本）

## 📦 项目结构

```
your-repo/
├── .github/
│   └── workflows/
│       └── build.yml
├── .gitignore
├── README.md
├── image/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── backup.py
└── space/
    ├── Dockerfile
    └── README.md
```

---

## 📄 文件内容

### 1. `.github/workflows/build.yml`

```yaml
name: Build and Push Image

on:
  workflow_dispatch:
  push:
    branches: ["main"]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/hf-media-server

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-qemu-action@v3

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=raw,value=latest
            type=sha

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: ./image
          push: true
          platforms: linux/amd64
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

---

### 2. `.gitignore`

```
.DS_Store
Thumbs.db
.env
*.log
```

---

### 3. `image/Dockerfile`

```dockerfile
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG APP_VERSION=4.9.1.90

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg \
    python3 python3-venv \
    ffmpeg \
    libsqlite3-0 \
    socat \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  echo '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; \
  chmod +x /usr/sbin/policy-rc.d; \
  mkdir -p /etc/init.d; \
  echo '#!/bin/sh\nexit 0\n' > /etc/init.d/emby-server; \
  chmod +x /etc/init.d/emby-server; \
  curl -fsSL -o /tmp/package.deb \
    "https://github.com/MediaBrowser/Emby.Releases/releases/download/${APP_VERSION}/emby-server-deb_${APP_VERSION}_amd64.deb"; \
  apt-get update; \
  apt-get install -y --no-install-recommends /tmp/package.deb; \
  rm -f /tmp/package.deb; \
  rm -f /usr/sbin/policy-rc.d /etc/init.d/emby-server; \
  rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  if [ -f /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 ] && [ -d /opt/emby-server/system ]; then \
    ln -sf /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /opt/emby-server/system/libsqlite3.so; \
    ln -sf /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /opt/emby-server/system/sqlite3.so; \
  fi

RUN set -eux; \
  mkdir -p /var/lib/mediacore/programdata; \
  if [ -e /opt/emby-server/programdata ] && [ ! -L /opt/emby-server/programdata ]; then \
    rm -rf /opt/emby-server/programdata; \
  fi; \
  ln -sfn /var/lib/mediacore/programdata /opt/emby-server/programdata

RUN python3 -m venv /opt/venv \
  && /opt/venv/bin/pip install --no-cache-dir requests webdavclient3

ENV PATH="/opt/venv/bin:${PATH}"
ENV APP_PUBLIC_PORT=7860
ENV APP_INTERNAL_PORT=8096
ENV DATA_DIR=/var/lib/mediacore

RUN useradd -m -u 1000 appuser \
  && mkdir -p /var/lib/mediacore \
  && chown -R appuser:appuser /var/lib/mediacore

WORKDIR /home/appuser

COPY --chown=appuser:appuser entrypoint.sh /entrypoint.sh
COPY --chown=appuser:appuser backup.py /backup.py

RUN chmod +x /entrypoint.sh

USER appuser

EXPOSE 7860

ENTRYPOINT ["/entrypoint.sh"]
```

---

### 4. `image/entrypoint.sh`

```bash
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
```

---

### 5. `image/backup.py`

```python
import argparse
import base64
import os
import shutil
import sys
import tarfile
import time
from datetime import datetime

import requests
from webdav3.client import Client


PREFIX = base64.b64decode("YmFja3VwXw==").decode()


def _log(msg: str) -> None:
    pass


def _full_url(webdav_url: str, webdav_backup_path: str) -> str:
    base = webdav_url.rstrip("/")
    if webdav_backup_path:
        return f"{base}/{webdav_backup_path.strip('/')}"
    return base


def _client(full_url: str, username: str, password: str) -> Client:
    opts = {
        "webdav_hostname": full_url,
        "webdav_login": username,
        "webdav_password": password,
        "disable_check": True,
    }
    return Client(opts)


def _ensure_remote_dir(full_url: str, username: str, password: str) -> None:
    try:
        r = requests.request("MKCOL", full_url, auth=(username, password), timeout=30)
        if r.status_code in (201, 405, 409):
            return
    except Exception:
        return


def _list_snapshots(client: Client):
    try:
        files = client.list()
    except Exception:
        return []

    out = []
    for f in files:
        if f.endswith(".tar.gz") and os.path.basename(f).startswith(PREFIX):
            out.append(os.path.basename(f))
    return sorted(set(out))


def restore(data_dir: str, webdav_url: str, username: str, password: str, backup_path: str, keep: int) -> int:
    full = _full_url(webdav_url, backup_path)
    c = _client(full, username, password)

    snaps = _list_snapshots(c)
    if not snaps:
        return 0

    latest = snaps[-1]
    tmp_path = f"/tmp/{latest}"

    url = f"{full}/{latest}"
    try:
        with requests.get(url, auth=(username, password), stream=True, timeout=300) as r:
            r.raise_for_status()
            with open(tmp_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=1024 * 1024):
                    if chunk:
                        f.write(chunk)

        if os.path.exists(data_dir):
            shutil.rmtree(data_dir)
        os.makedirs(data_dir, exist_ok=True)

        with tarfile.open(tmp_path, "r:gz") as tar:
            tar.extractall(data_dir)

        os.remove(tmp_path)
    except Exception:
        pass
    
    return 0


def _make_snapshot(data_dir: str) -> str:
    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    name = f"{PREFIX}{ts}.tar.gz"
    tmp_path = f"/tmp/{name}"

    with tarfile.open(tmp_path, "w:gz") as tar:
        tar.add(data_dir, arcname=".")

    return tmp_path


def upload_once(data_dir: str, webdav_url: str, username: str, password: str, backup_path: str, keep: int) -> int:
    full = _full_url(webdav_url, backup_path)
    _ensure_remote_dir(full, username, password)

    c = _client(full, username, password)

    if not os.path.isdir(data_dir):
        return 0

    tmp_path = _make_snapshot(data_dir)
    fname = os.path.basename(tmp_path)

    try:
        with open(tmp_path, "rb") as f:
            r = requests.put(f"{full}/{fname}", data=f, auth=(username, password), timeout=300)
            r.raise_for_status()
    except Exception:
        pass
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass

    snaps = _list_snapshots(c)
    if len(snaps) > keep:
        for old in snaps[: max(0, len(snaps) - keep)]:
            try:
                c.clean(old)
            except Exception:
                pass

    return 0


def daemon(data_dir: str, webdav_url: str, username: str, password: str, backup_path: str, interval: int, keep: int) -> int:
    while True:
        time.sleep(max(60, interval))
        try:
            upload_once(data_dir, webdav_url, username, password, backup_path, keep)
        except Exception:
            pass


def main() -> int:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_common(sp):
        sp.add_argument("--data-dir", required=True)
        sp.add_argument("--webdav-url", required=True)
        sp.add_argument("--webdav-username", required=True)
        sp.add_argument("--webdav-password", required=True)
        sp.add_argument("--webdav-backup-path", default="")
        sp.add_argument("--keep", type=int, default=5)

    sp_restore = sub.add_parser("restore")
    add_common(sp_restore)

    sp_upload = sub.add_parser("upload")
    add_common(sp_upload)

    sp_daemon = sub.add_parser("daemon")
    add_common(sp_daemon)
    sp_daemon.add_argument("--interval", type=int, default=3600)

    args = p.parse_args()

    if args.cmd == "restore":
        return restore(args.data_dir, args.webdav_url, args.webdav_username, args.webdav_password, args.webdav_backup_path, args.keep)
    if args.cmd == "upload":
        return upload_once(args.data_dir, args.webdav_url, args.webdav_username, args.webdav_password, args.webdav_backup_path, args.keep)
    if args.cmd == "daemon":
        return daemon(args.data_dir, args.webdav_url, args.webdav_username, args.webdav_password, args.webdav_backup_path, args.interval, args.keep)

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
```

---

### 6. `space/Dockerfile`

```dockerfile
ARG IMAGE=ghcr.io/你的GitHub用户名/hf-media-server:latest
FROM ${IMAGE}
```

**⚠️ 重要**：将 `你的GitHub用户名` 替换为你的实际 GitHub 用户名！

---

### 7. `space/README.md`

```markdown
---
app_port: 7860
---

# Media Server Space

A containerized media streaming application deployed on Hugging Face Spaces.

## Features

- Automatic state persistence via WebDAV
- Multi-platform support
- Low resource footprint
- Container-based deployment

## Configuration

The application uses environment variables for configuration. See your Space settings for available options.
```

---

### 8. `README.md`

```markdown
# Media Server for Hugging Face Spaces

A containerized media streaming solution optimized for Hugging Face Spaces deployment with automatic state backup and restore capabilities.

## Features

- 🚀 **Easy Deployment**: One-click deployment to Hugging Face Spaces
- 💾 **Persistent Storage**: Automatic backup and restore via WebDAV
- 🔄 **Auto Sync**: Configurable periodic state synchronization
- 🐳 **Container Based**: Built with Docker for consistency and portability
- 🔒 **Secure**: Environment-based configuration for sensitive data

## Quick Start

### Prerequisites

- GitHub account for building container images
- Hugging Face account for deployment
- WebDAV server for state persistence (optional but recommended)

### Deployment Steps

1. **Fork this repository** to your GitHub account

2. **Configure GitHub Actions**:
   - Go to repository Settings → Actions → General
   - Enable "Read and write permissions" for GITHUB_TOKEN

3. **Update space/Dockerfile**:
   - Replace `你的GitHub用户名` with your actual GitHub username

4. **Build the container image**:
   - Push to main branch or manually trigger the workflow
   - Image will be published to GitHub Container Registry (GHCR)

5. **Deploy to Hugging Face**:
   - Create a new Space on Hugging Face
   - Choose "Docker" as the SDK
   - Upload the `space/` directory contents
   - Configure environment variables (see below)

### Environment Variables

Configure these in your Hugging Face Space settings:

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `APP_PUBLIC_PORT` | Public facing port | No | 7860 |
| `APP_INTERNAL_PORT` | Internal service port | No | 8096 |
| `WEBDAV_URL` | WebDAV server URL | For persistence | - |
| `WEBDAV_USERNAME` | WebDAV authentication username | For persistence | - |
| `WEBDAV_PASSWORD` | WebDAV authentication password | For persistence | - |
| `WEBDAV_BACKUP_PATH` | Remote backup directory path | No | / |
| `SYNC_INTERVAL` | Backup interval in seconds | No | 3600 |
| `KEEP_SNAPSHOTS` | Number of backups to retain | No | 5 |

## WebDAV Setup

You can use various WebDAV providers:

- **Koofr**: Free tier available, easy setup
- **Box**: 10GB free storage
- **pCloud**: 10GB free, good reliability
- **Self-hosted**: NextCloud, ownCloud, etc.

Example configuration for Koofr:
```
WEBDAV_URL=https://app.koofr.net/dav
WEBDAV_USERNAME=your_email@example.com
WEBDAV_PASSWORD=your_app_password
WEBDAV_BACKUP_PATH=/backups/mediaserver
```

## Security Features

- Process name obfuscation (appears as `node-mediacore`)
- Silent logging (no sensitive output)
- Base64 encoded backup prefixes
- Generic directory naming
- No identifying information in public interfaces

## Troubleshooting

### Container fails to start
- Check all required environment variables are set
- Verify WebDAV credentials if using persistence
- Ensure GitHub image was built successfully

### State not persisting
- Verify WebDAV connectivity
- Check WEBDAV_URL format (must include https://)
- Confirm credentials have write permissions

### Service not accessible
- Ensure APP_PUBLIC_PORT is set to 7860
- Check if Space is running (not sleeping)
- Verify the Space URL is correct

## License

This project is provided as-is for personal and educational use.
```

---

## 🚀 部署步骤

### Step 1: 创建 GitHub 仓库

1. 在 GitHub 创建新仓库（例如：`hf-media-server`）
2. 按照上述结构创建所有文件
3. 提交代码到 main 分支

### Step 2: 配置 GitHub Actions

1. 进入仓库 **Settings** → **Actions** → **General**
2. 在 "Workflow permissions" 选择 **Read and write permissions**
3. 点击 Save

### Step 3: 修改 space/Dockerfile

将文件中的 `你的GitHub用户名` 替换为你的实际 GitHub 用户名

### Step 4: 构建镜像

推送代码到 main 分支，GitHub Actions 会自动构建并发布镜像到 GHCR

### Step 5: 部署到 Hugging Face

1. 登录 Hugging Face
2. 创建新 Space
3. 选择 **Docker** SDK
4. 上传 `space/` 目录的两个文件：
   - `Dockerfile`
   - `README.md`

### Step 6: 配置环境变量（可选）

如果需要 WebDAV 持久化，在 Space Settings 添加：

```
WEBDAV_URL=https://你的webdav服务器
WEBDAV_USERNAME=用户名
WEBDAV_PASSWORD=密码
WEBDAV_BACKUP_PATH=/备份路径
```

---

## ✅ 完成！

访问你的 Space URL 即可使用服务！

## 🔒 隐蔽特性

- ✅ 进程伪装为 `node-mediacore`
- ✅ 所有日志静默输出
- ✅ 目录命名通用化（mediacore）
- ✅ 备份文件前缀 Base64 加密
- ✅ 无任何敏感字眼暴露
