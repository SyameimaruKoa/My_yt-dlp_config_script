#!/bin/bash
set -euo pipefail

show_help() {
    cat <<'EOF_HELP'
使用法: remove-standalone.sh [--dry-run] [--path ファイル] [--legacy-gist]
        remove-standalone.sh -h | --help

旧yt-dlp単独実行ファイルを削除するのじゃ。
引数なしでは ~/.local/bin/yt-dlp と /usr/local/bin/yt-dlp を確認する。
yt-dlpのZIP形式単独配布ファイルだけを削除し、新しいラッパーは残すぞ。

オプション:
  --path ファイル    指定したファイルだけを確認（繰り返し指定可能）
  --legacy-gist      旧Gistクローンも確認し、不要なら削除
  --dry-run          削除せず確認結果を表示
  -h, --help         このヘルプを表示
EOF_HELP
}

dry_run=false
cleanup_gist=false
declare -a explicit_paths=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        --legacy-gist)
            cleanup_gist=true
            shift
            ;;
        --path)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                show_help
                exit 1
            fi
            explicit_paths+=("$2")
            shift 2
            ;;
        *)
            echo "不明な引数じゃ: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

if [ "${#explicit_paths[@]}" -gt 0 ]; then
    targets=("${explicit_paths[@]}")
else
    targets=("$HOME/.local/bin/yt-dlp" "/usr/local/bin/yt-dlp")
fi

is_standalone_zipapp() {
    python3 - "$1" <<'PY'
import sys
import zipfile

try:
    with zipfile.ZipFile(sys.argv[1]) as archive:
        names = archive.namelist()
    sys.exit(0 if "yt_dlp/__main__.py" in names and "yt_dlp/version.py" in names else 1)
except (OSError, zipfile.BadZipFile):
    sys.exit(1)
PY
}

for target in "${targets[@]}"; do
    if [ -L "$target" ]; then
        printf '保持（シンボリックリンク）: %s\n' "$target"
    elif [ ! -f "$target" ]; then
        printf '対象なし: %s\n' "$target"
    elif [ "$(basename "$target")" != "yt-dlp" ] || ! is_standalone_zipapp "$target"; then
        printf '保持（単独実行ファイルではない）: %s\n' "$target"
    elif [ "$dry_run" = true ]; then
        printf '削除予定: %s\n' "$target"
    elif [ -w "$target" ] && [ -w "$(dirname "$target")" ]; then
        rm -- "$target"
        printf '削除完了: %s\n' "$target"
    else
        sudo rm -- "$target"
        printf '削除完了: %s\n' "$target"
    fi
done

cleanup_legacy_gist() {
    local gist_dir="$HOME/21141912fbacf40877f4cf877577e082"
    local gist_remote="https://gist.github.com/21141912fbacf40877f4cf877577e082.git"
    local status ahead root

    if [ ! -e "$gist_dir" ] && [ ! -L "$gist_dir" ]; then
        printf '旧Gistなし: %s\n' "$gist_dir"
        return
    fi
    if [ -L "$gist_dir" ] || [ ! -d "$gist_dir/.git" ] || [ -L "$gist_dir/.git" ]; then
        printf '旧Gist保持（通常のGitクローンではない）: %s\n' "$gist_dir"
        return
    fi
    root=$(git -C "$gist_dir" rev-parse --show-toplevel 2>/dev/null) || {
        printf '旧Gist保持（Git情報を確認できない）: %s\n' "$gist_dir"
        return
    }
    if [ "$root" != "$gist_dir" ] ||
       [ "$(git -C "$gist_dir" remote get-url origin 2>/dev/null || true)" != "$gist_remote" ]; then
        printf '旧Gist保持（取得元が一致しない）: %s\n' "$gist_dir"
        return
    fi
    if ! status=$(git -C "$gist_dir" status --porcelain --ignored --untracked-files=all 2>/dev/null); then
        printf '旧Gist保持（変更状態を確認できない）: %s\n' "$gist_dir"
        return
    fi
    if [ -n "$status" ]; then
        printf '旧Gist保持（ローカルファイルに変更がある）: %s\n' "$gist_dir"
        return
    fi
    if ! git -C "$gist_dir" rev-parse --verify '@{upstream}' > /dev/null 2>&1 ||
       ! ahead=$(git -C "$gist_dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null) ||
       [ "$ahead" != 0 ]; then
        printf '旧Gist保持（未送信コミットまたは追跡先不明）: %s\n' "$gist_dir"
        return
    fi
    if [ "$dry_run" = true ]; then
        printf '旧Gist削除予定: %s\n' "$gist_dir"
        return
    fi
    rm -rf -- "$gist_dir"
    printf '旧Gist削除完了: %s\n' "$gist_dir"
}

if [ "$cleanup_gist" = true ]; then
    cleanup_legacy_gist
fi
