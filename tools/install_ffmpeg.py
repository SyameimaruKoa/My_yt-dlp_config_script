import os
import shutil
import subprocess
import sys
from pathlib import Path
from uuid import uuid4


def install_ffmpeg(bin_dir, resolve_executables=None, verify=None):
    if resolve_executables is None:
        from static_ffmpeg.run import get_or_fetch_platform_executables_else_raise
        resolve_executables = get_or_fetch_platform_executables_else_raise
    if verify is None:
        verify = subprocess.run
    ffmpeg, ffprobe = resolve_executables()
    bin_dir = Path(bin_dir)
    bin_dir.mkdir(parents=True, exist_ok=True)
    installed = []
    for name, source in (("ffmpeg.exe", ffmpeg), ("ffprobe.exe", ffprobe)):
        source = Path(source)
        target = bin_dir / name
        if source.resolve() == target.resolve():
            verify([str(target), "-version"], check=True, stdout=subprocess.DEVNULL)
            installed.append(target)
            continue
        temporary = bin_dir / f"{Path(name).stem}.{uuid4().hex}.exe"
        try:
            try:
                os.link(source, temporary)
            except OSError:
                shutil.copy2(source, temporary)
            verify([str(temporary), "-version"], check=True, stdout=subprocess.DEVNULL)
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
        installed.append(target)
    return installed


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] in ("-h", "--help"):
        print("Usage: python tools/install_ffmpeg.py <binary-directory>")
        sys.exit(0 if len(sys.argv) == 2 and sys.argv[1] in ("-h", "--help") else 2)
    install_ffmpeg(sys.argv[1])
