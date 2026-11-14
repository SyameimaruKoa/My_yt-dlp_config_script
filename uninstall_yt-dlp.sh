#!/usr/bin/env bash
# アンインストール: リポジトリ内の実体、旧方式の残骸、管理下の起動リンクを削除する
# 引数の詳細は --help を参照
set -euo pipefail

show_help() {
    cat <<'EOF_HELP'
使用法: bash uninstall_yt-dlp.sh [--dry-run] [--cleanup-only] [--keep-repository]
        bash uninstall_yt-dlp.sh -h | --help

既定は現行の起動リンク・venv・設定・字幕変換ツール・Deno・Proton Prefix、
旧Gistなどの旧方式を削除し、変更の有無に関係なくGitクローンも削除する。
--cleanup-onlyは旧方式だけを整理し、現行方式の実体とリンクを残す。

オプション:
  --dry-run             削除せずに対象と判断結果を表示
  --cleanup-only        旧方式だけ削除し、現行方式を保持
  --keep-repository     完全削除時でもGit作業ツリーを残す
  --remove-repository   Git作業ツリーも削除（既定、旧引数との互換）
  -h, --help            このヘルプを表示
EOF_HELP
}

dry_run=false
remove_repository=true
cleanup_only=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        --dry-run) dry_run=true; shift ;;
        --cleanup-only) cleanup_only=true; shift ;;
        --keep-repository) remove_repository=false; shift ;;
        --remove-repository) remove_repository=true; shift ;;
        *) printf '不明な引数: %s\n' "$1" >&2; show_help; exit 2 ;;
    esac
done

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
RUNTIME="$ROOT/.runtime/linux"
LOCAL_BIN="$HOME/.local/bin"
LEGACY_GIST="$HOME/21141912fbacf40877f4cf877577e082"
MIGRATION="$ROOT/tools/migration/remove-standalone.sh"

delete_file() {
    local target="$1" sudo_flag="${2:-false}"
    if [ "$dry_run" = true ]; then
        printf '削除予定: %s\n' "$target"
    elif [ "$sudo_flag" = true ]; then
        sudo rm -f -- "$target"
        printf '削除完了: %s\n' "$target"
    else
        rm -f -- "$target"
        printf '削除完了: %s\n' "$target"
    fi
}

delete_link_if_owned() {
    local link="$1" expected="$2" alternate="${3:-}" elevate="${4:-false}"
    if [ -L "$link" ]; then
        delete_file "$link" "$elevate"
    fi
}

delete_known_wrapper() {
    local target="$1" kind="$2" elevate="${3:-false}"
    if [ ! -f "$target" ] || [ -L "$target" ]; then
        return
    fi
    case "$kind" in
        yt-dlp)
            if ! grep -Fq '# yt-dlp venv wrapper' "$target" 2>/dev/null; then
                return
            fi
            ;;
        wine)
            if ! grep -Fq '# yt-dlp UMU Proton wrapper' "$target" 2>/dev/null &&
               ! grep -Fq '# yt-dlp Proton wrapper' "$target" 2>/dev/null &&
               ! grep -Fq 'distrobox enter -n yt-dlp-wine' "$target" 2>/dev/null; then
                return
            fi
            ;;
    esac
    delete_file "$target" "$elevate"
}

if [ "$cleanup_only" = true ]; then
    if [ ! -x "$RUNTIME/venv/bin/python" ] ||
       [ ! -f "$RUNTIME/bin/yt-dlp" ] ||
       [ ! -L "$LOCAL_BIN/yt-dlp" ] ||
       [ ! -L "$HOME/.config/yt-dlp/config" ]; then
        printf '現行方式の導入が未完了じゃ。setup_yt-dlp.shでセットアップしてから--cleanup-onlyを使うのじゃ。\n' >&2
        exit 1
    fi
    if [ -L "$HOME/.config/yt-dlp/z__run_sub_converter.sh" ]; then
        legacy_link="$HOME/.config/yt-dlp/z__run_sub_converter.sh"
        case "$(readlink "$legacy_link")" in
            "$ROOT/z__run_sub_converter.sh"|"$LEGACY_GIST/z__run_sub_converter.sh")
                delete_file "$legacy_link"
                ;;
            *) printf '保持（管理外の旧字幕リンク）: %s\n' "$legacy_link" ;;
        esac
    fi
    if [ -f "$MIGRATION" ]; then
        args=(--legacy-gist --legacy-runtime)
        if [ "$dry_run" = true ]; then
            args+=(--dry-run)
        fi
        bash "$MIGRATION" "${args[@]}"
    fi
    printf '旧方式の整理完了（現行のvenv・起動リンク・設定・リポジトリは保持）\n'
    exit 0
fi

for link in "$LOCAL_BIN/yt-dlp" /usr/local/bin/yt-dlp; do
    if [ "$link" = /usr/local/bin/yt-dlp ]; then
        elevate=true
    else
        elevate=false
    fi
    delete_link_if_owned "$link" "$RUNTIME/bin/yt-dlp" "" "$elevate"
    delete_known_wrapper "$link" yt-dlp "$elevate"
done
delete_link_if_owned "$LOCAL_BIN/wine" "$RUNTIME/bin/wine"
delete_known_wrapper "$LOCAL_BIN/wine" wine
delete_link_if_owned "$LOCAL_BIN/deno" "$RUNTIME/deno/bin/deno" "$HOME/.deno/bin/deno"
delete_link_if_owned "$HOME/.config/yt-dlp/config" "$ROOT/yt-dlp config" "$LEGACY_GIST/yt-dlp config"
delete_link_if_owned "$HOME/.config/yt-dlp/run_sub_converter.sh" "$ROOT/run_sub_converter.sh" "$LEGACY_GIST/run_sub_converter.sh"
legacy_converter_link="$HOME/.config/yt-dlp/z__run_sub_converter.sh"
if [ -L "$legacy_converter_link" ]; then
    case "$(readlink "$legacy_converter_link")" in
        "$ROOT/z__run_sub_converter.sh"|"$LEGACY_GIST/z__run_sub_converter.sh")
            delete_file "$legacy_converter_link"
            ;;
        *) printf '保持（管理外の旧字幕リンク）: %s\n' "$legacy_converter_link" ;;
    esac
fi

converter="$HOME/.config/yt-dlp/tools/YTSubConverter/YTSubConverter.exe"
delete_link_if_owned "$converter" "$RUNTIME/tools/YTSubConverter/YTSubConverter.exe"
if [ -f "$converter" ] && [ ! -L "$converter" ] &&
   [ -f "$RUNTIME/tools/YTSubConverter/YTSubConverter.exe" ] &&
   cmp -s "$converter" "$RUNTIME/tools/YTSubConverter/YTSubConverter.exe"; then
    delete_file "$converter"
fi

if [ -f "$MIGRATION" ]; then
    args=(--legacy-gist --legacy-runtime)
    if [ "$dry_run" = true ]; then
        args+=(--dry-run)
    fi
    bash "$MIGRATION" "${args[@]}"
fi

for startup_file in "$HOME/.profile" "$HOME/.bashrc"; do
    if [ -f "$startup_file" ] &&
       grep -Fq '# yt-dlp local bin path' "$startup_file"; then
        if [ "$dry_run" = true ]; then
            printf 'PATH設定行削除予定: %s\n' "$startup_file"
        else
            python3 - "$startup_file" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = path.read_bytes()
line = b'\n# yt-dlp local bin path\nexport PATH="$HOME/.local/bin:$PATH"\n'
path.write_bytes(data.replace(line, b'\n'))
PY
            printf 'PATH設定行削除完了: %s\n' "$startup_file"
        fi
    fi
done

if [ -d "$RUNTIME" ] && [ ! -L "$RUNTIME" ]; then
    if [ "$dry_run" = true ]; then
        printf 'リポジトリ内の実行環境削除予定: %s\n' "$RUNTIME"
    else
        rm -rf -- "$RUNTIME"
        printf 'リポジトリ内の実行環境削除完了: %s\n' "$RUNTIME"
    fi
fi
if [ "$dry_run" = false ]; then
    rmdir "$HOME/.config/yt-dlp/tools/YTSubConverter" \
        "$HOME/.config/yt-dlp/tools" "$HOME/.config/yt-dlp" \
        "${XDG_DATA_HOME:-$HOME/.local/share}/yt-dlp" 2>/dev/null || true
fi

if [ "$remove_repository" = true ]; then
    if [ "$ROOT" = "$HOME" ] || [ "$ROOT" = / ] ||
       [ ! -f "$ROOT/setup_yt-dlp.sh" ] || [ ! -f "$ROOT/yt-dlp config" ]; then
        printf '削除中止（実行元がyt-dlpリポジトリではない）: %s\n' "$ROOT" >&2
        exit 1
    fi
    if [ "$dry_run" = true ]; then
        printf '現行リポジトリ全削除予定（編集・未送信コミットを含む）: %s\n' "$ROOT"
    else
        cd -- "$HOME"
        rm -rf -- "$ROOT"
        printf '現行リポジトリ全削除完了: %s\n' "$ROOT"
    fi
else
    printf 'リポジトリ保持（--keep-repository指定）: %s\n' "$ROOT"
fi
printf '完全アンインストール処理が完了したぞ。保持と表示された項目は削除しておらぬ。\n'
