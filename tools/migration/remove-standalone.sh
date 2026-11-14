#!/bin/bash
set -euo pipefail

show_help() {
    cat <<'EOF_HELP'
使用法: remove-standalone.sh [--dry-run] [--path ファイル] [--legacy-gist] [--legacy-runtime]
        remove-standalone.sh -h | --help

旧yt-dlp単独実行ファイルを削除するのじゃ。
引数なしでは ~/.local/bin/yt-dlp と /usr/local/bin/yt-dlp を確認する。
yt-dlpのZIP形式単独配布ファイルだけを削除し、新しいラッパーは残すぞ。

オプション:
  --path ファイル    指定したファイルだけを確認（繰り返し指定可能）
  --legacy-gist      旧Gistクローンも確認し、不要なら削除
  --legacy-runtime   移行後の旧venv・旧更新スクリプト等を整理
  --dry-run          削除せず確認結果を表示
  -h, --help         このヘルプを表示
EOF_HELP
}

dry_run=false
cleanup_gist=false
cleanup_runtime=false
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
        --legacy-runtime)
            cleanup_runtime=true
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
        if [ "$(readlink -f "$target" 2>/dev/null || true)" = "$(readlink -f "$(dirname "$0")/../../.runtime/linux/bin/yt-dlp" 2>/dev/null || true)" ]; then
            printf '移行完了（リポジトリ内のpip版ラッパーへリンク済み）: %s\n' "$target"
        else
            printf '保持（別のシンボリックリンク）: %s\n' "$target"
        fi
    elif [ ! -f "$target" ]; then
        printf '対象なし: %s\n' "$target"
    elif grep -Fq '# yt-dlp venv wrapper' "$target" 2>/dev/null; then
        printf '移行済み（pip版の起動ラッパー）: %s\n' "$target"
    elif [ "$(basename "$target")" != "yt-dlp" ] || ! is_standalone_zipapp "$target"; then
        printf '保持（管理対象の旧バイナリではない）: %s\n' "$target"
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

cleanup_legacy_runtime() {
    local legacy_root="${XDG_DATA_HOME:-$HOME/.local/share}/yt-dlp"
    local old_venv="$legacy_root/venv"
    local old_updater="$legacy_root/auto_update.py"
    local old_prefix="$legacy_root/proton-prefix"
    local old_deno="$HOME/.deno/bin/deno"
    local target

    if [ -d "$old_venv" ] && [ ! -L "$old_venv" ] &&
       [ -f "$old_venv/pyvenv.cfg" ] && [ -x "$old_venv/bin/python" ]; then
        if [ "$dry_run" = true ]; then
            printf '旧venv削除予定: %s\n' "$old_venv"
        else
            rm -rf -- "$old_venv"
            printf '旧venv削除完了: %s\n' "$old_venv"
        fi
    fi
    if [ -f "$old_updater" ] && [ ! -L "$old_updater" ] &&
       grep -Fq 'yt-dlp-update.lock' "$old_updater"; then
        if [ "$dry_run" = true ]; then
            printf '旧更新スクリプト削除予定: %s\n' "$old_updater"
        else
            rm -f -- "$old_updater"
            printf '旧更新スクリプト削除完了: %s\n' "$old_updater"
        fi
    fi
    if [ -d "$old_prefix" ] && [ ! -L "$old_prefix" ] &&
       { [ -f "$old_prefix/system.reg" ] || [ -f "$old_prefix/user.reg" ]; }; then
        if [ "$dry_run" = true ]; then
            printf '旧Proton Prefix削除予定: %s\n' "$old_prefix"
        else
            rm -rf -- "$old_prefix"
            printf '旧Proton Prefix削除完了: %s\n' "$old_prefix"
        fi
    fi
    local old_checkout="$legacy_root/My_yt-dlp_config_script"
    local active_checkout
    active_checkout=$(readlink -f "$(dirname "$0")/../.." 2>/dev/null || true)
    if [ -d "$old_checkout/.git" ] && [ ! -L "$old_checkout" ] &&
       [ "$(readlink -f "$old_checkout")" != "$active_checkout" ] &&
       [ "$(git -C "$old_checkout" remote get-url origin 2>/dev/null || true)" = "https://github.com/SyameimaruKoa/My_yt-dlp_config_script.git" ] &&
       [ -z "$(git -C "$old_checkout" status --porcelain --untracked-files=all 2>/dev/null)" ]; then
        if [ "$dry_run" = true ]; then
            printf '旧リポジトリの重複クローン削除予定: %s\\n' "$old_checkout"
        else
            rm -rf -- "$old_checkout"
            printf '旧リポジトリの重複クローン削除完了: %s\\n' "$old_checkout"
        fi
    fi
    target=$(readlink -f "$HOME/.local/bin/deno" 2>/dev/null || true)
    if [ -f "$old_deno" ] && [ ! -L "$old_deno" ] &&
       [ "$target" != "$(readlink -f "$old_deno")" ]; then
        if [ "$dry_run" = true ]; then
            printf '旧Deno本体削除予定: %s\n' "$old_deno"
        else
            rm -f -- "$old_deno"
            rmdir "$HOME/.deno/bin" "$HOME/.deno" 2>/dev/null || true
            printf '旧Deno本体削除完了: %s\n' "$old_deno"
        fi
    fi
}

if [ "$cleanup_runtime" = true ]; then
    cleanup_legacy_runtime
fi
