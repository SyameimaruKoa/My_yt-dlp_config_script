#!/usr/bin/env python3
import importlib.metadata
import os
import subprocess
import sys
import time
from pathlib import Path


def package_version():
    try:
        return importlib.metadata.version("yt-dlp")
    except importlib.metadata.PackageNotFoundError:
        return None


def update():
    if os.environ.get("YT_DLP_SKIP_UPDATE") == "1":
        return 0
    extras = "yt-dlp[default,curl-cffi,secretstorage]" if sys.platform.startswith("linux") else "yt-dlp[default,curl-cffi]"
    lock_path = Path(sys.prefix) / "yt-dlp-update.lock"
    lock_path.touch(exist_ok=True)
    with lock_path.open("r+b") as lock:
        if os.name == "nt":
            import msvcrt
            if lock.seek(0, 2) == 0:
                lock.write(b"0")
                lock.flush()
            lock.seek(0)
            for attempt in range(90):
                try:
                    msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
                    break
                except OSError:
                    if attempt == 89:
                        print("別のyt-dlp更新処理が実行中じゃ。", file=sys.stderr)
                        return 0
                    time.sleep(1)
        else:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX)
        previous = package_version()
        command = [
            sys.executable, "-m", "pip", "install", "--upgrade", "--pre",
            "--disable-pip-version-check", "--quiet", "--timeout", "5",
            "--retries", "0", extras,
        ]
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=90)
        except subprocess.TimeoutExpired:
            print("yt-dlp更新確認がタイムアウトしたため、インストール済みの版で続行するのじゃ。", file=sys.stderr)
            return 0
        if result.returncode:
            print("yt-dlp更新確認に失敗したため、インストール済みの版で続行するのじゃ。", file=sys.stderr)
            if os.environ.get("YT_DLP_UPDATE_DEBUG") == "1":
                print(result.stdout, file=sys.stderr)
            return 0
        current = package_version()
        if current != previous:
            print(f"yt-dlpを更新したぞ: {previous or '未導入'} -> {current}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    if sys.argv[1:] in (["-h"], ["--help"]):
        print("使用法: python yt_dlp_auto_update.py\n"
              "yt-dlpと追加pip依存関係の更新を確認するのじゃ。\n"
              "YT_DLP_SKIP_UPDATE=1 で自動更新を省略できるぞ。")
        sys.exit(0)
    if len(sys.argv) != 1:
        print("不明な引数じゃ。--helpを参照するのじゃ。", file=sys.stderr)
        sys.exit(2)
    sys.exit(update())
