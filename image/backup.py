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
