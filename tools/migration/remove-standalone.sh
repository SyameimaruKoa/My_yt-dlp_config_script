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
  --legacy-gist      旧Gistの内容と変更履歴に関係なく全削除
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
    if [ ! -e "$gist_dir" ] && [ ! -L "$gist_dir" ]; then
        printf '旧Gistなし: %s\n' "$gist_dir"
        return
    fi
    if [ "$dry_run" = true ]; then
        printf '旧Gist全削除予定（変更・未送信コミットを含む）: %s\n' "$gist_dir"
    else
        rm -rf -- "$gist_dir"
        printf '旧Gist削除完了: %s\n' "$gist_dir"
    fi
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

    for old_directory in "$old_venv" "$old_prefix"; do
        if [ -d "$old_directory" ] && [ ! -L "$old_directory" ]; then
            if [ "$dry_run" = true ]; then
                printf '旧実行環境全削除予定: %s\n' "$old_directory"
            else
                rm -rf -- "$old_directory"
                printf '旧実行環境削除完了: %s\n' "$old_directory"
            fi
        fi
    done
    if [ -e "$old_updater" ] || [ -L "$old_updater" ]; then
        if [ "$dry_run" = true ]; then
            printf '旧更新スクリプト全削除予定: %s\n' "$old_updater"
        else
            rm -f -- "$old_updater"
            printf '旧更新スクリプト削除完了: %s\n' "$old_updater"
        fi
    fi
    local old_checkout="$legacy_root/My_yt-dlp_config_script"
    local active_checkout
    active_checkout=$(readlink -f "$(dirname "$0")/../.." 2>/dev/null || true)
    if { [ -d "$old_checkout" ] || [ -L "$old_checkout" ]; } &&
       [ "$(readlink -f "$old_checkout" 2>/dev/null || true)" != "$active_checkout" ]; then
        if [ "$dry_run" = true ]; then
            printf '旧リポジトリ全削除予定: %s\n' "$old_checkout"
        else
            rm -rf -- "$old_checkout"
            printf '旧リポジトリ削除完了: %s\n' "$old_checkout"
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
