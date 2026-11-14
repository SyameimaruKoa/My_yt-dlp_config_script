#!/bin/bash
#
# yt-dlp (Nightly) と Windows版YTSubConverter.exe (UMU / Proton動作) をセットアップするのじゃ
# Ubuntu / Debian と Bazzite に対応
#
# 使用法: ./z__setup_yt-dlp.sh
# ヘルプ: ./z__setup_yt-dlp.sh -h

set -e
set -o pipefail

# --- ヘルプ表示 ---
show_help() {
    cat << EOF_HELP
使用法: $(basename "$0")
        $(basename "$0") -h | --help

機能:
1. 必須パッケージ (git, ffmpeg, python3, curl, wget, aria2) の準備
   Ubuntu / Debian: apt-get
   Bazzite: Homebrew (OS本体の変更・再起動なし)
2. Python仮想環境にyt-dlp Nightlyとpip追加依存関係をインストール
3. YTSubConverter.exe をダウンロードして配置
4. UMU Launcher でProtonを利用 (Wine/Monoの手動インストール不要)
   Bazzite: インストール済みProtonを優先
   Ubuntu / Debian: Steam不要のUMU-Protonを自動取得
5. このGitHubリポジトリから設定ファイルと字幕変換スクリプトを取得
6. Deno (JavaScriptランタイム) をインストール
7. 起動ラッパー・設定・変換ツールの参照先をリポジトリ内に統一
8. 移行前の不要なファイル・旧Gistクローンを整理

オプション:
-h, --help  このヘルプを表示するのじゃ

PROTON_PATH=/path/to/Proton を指定すればProtonの自動選択を上書きできるぞ。
EOF_HELP
}

if [ "$#" -gt 0 ]; then
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "エラー: 不明な引数じゃ: $1" >&2
            show_help
            exit 1
            ;;
    esac
fi

# --- OS判定 ---
if grep -qi 'bazzite' /etc/os-release; then
    OS_TYPE="bazzite"
elif command -v apt-get > /dev/null 2>&1; then
    OS_TYPE="apt"
else
    echo "エラー: 対応OSは Ubuntu / Debian / Bazzite じゃ。" >&2
    exit 1
fi

LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

# 新しいターミナルでも ~/.local/bin を先頭で検索する
for startup_file in "$HOME/.profile" "$HOME/.bashrc"; do
    if ! grep -Fq '# yt-dlp local bin path' "$startup_file" 2>/dev/null; then
        printf '\n# yt-dlp local bin path\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$startup_file"
    fi
done

install_owned_link() {
    local source="$1" target="$2" elevate="${3:-false}" kind
    local canonical_source canonical_target
    canonical_source=$(readlink -f "$source")
    if [ -L "$target" ]; then
        canonical_target=$(readlink -f "$target" || true)
        if [ "$canonical_target" = "$canonical_source" ]; then
            printf 'リンク確認済み（リポジトリ内）: %s -> %s\\n' "$target" "$source"
            return
        fi
        if [ "$target" != "$LOCAL_BIN/deno" ] || [ "$(readlink "$target")" != "$HOME/.deno/bin/deno" ]; then
            printf 'エラー: 他のシンボリックリンクを変更しない: %s\\n' "$target" >&2
            return 1
        fi
    elif [ -e "$target" ]; then
        if [ ! -f "$target" ]; then
            printf 'エラー: 通常ファイル以外を置き換えない: %s\\n' "$target" >&2
            return 1
        fi
        kind=$(basename "$target")
        case "$kind" in
            yt-dlp)
                if ! grep -Fq '# yt-dlp venv wrapper' "$target" 2>/dev/null &&
                   ! python3 - "$target" <<'PY_STANDALONE'
import sys
import zipfile
try:
    with zipfile.ZipFile(sys.argv[1]) as archive:
        names = set(archive.namelist())
    sys.exit(0 if {'yt_dlp/__main__.py', 'yt_dlp/version.py'} <= names else 1)
except (OSError, zipfile.BadZipFile):
    sys.exit(1)
PY_STANDALONE
                then
                    printf 'エラー: 管理外のyt-dlpを変更しない: %s\\n' "$target" >&2
                    return 1
                fi
                ;;
            wine)
                if ! grep -Fq '# yt-dlp UMU Proton wrapper' "$target" &&
                   ! grep -Fq '# yt-dlp Proton wrapper' "$target" &&
                   ! grep -Fq 'distrobox enter -n yt-dlp-wine' "$target"; then
                    printf 'エラー: 管理外のwineを変更しない: %s\\n' "$target" >&2
                    return 1
                fi
                ;;
            *)
                printf 'エラー: 管理外のファイルを変更しない: %s\\n' "$target" >&2
                return 1
                ;;
        esac
    fi
    if [ "$elevate" = true ]; then
        sudo ln -sfn -- "$source" "$target"
    else
        ln -sfn -- "$source" "$target"
    fi
    printf 'リポジトリ内へリンク設定: %s -> %s\\n' "$target" "$source"
}

download_file() {
    local url="$1"
    local target="$2"
    local tmp
    mkdir -p "$(dirname "$target")"
    tmp=$(mktemp "${target}.tmp.XXXXXX")

    if command -v aria2c > /dev/null 2>&1; then
        if ! aria2c --allow-overwrite=true --auto-file-renaming=false \
            -d "$(dirname "$tmp")" -o "$(basename "$tmp")" "$url"; then
            rm -f "$tmp"
            return 1
        fi
    elif command -v wget > /dev/null 2>&1; then
        if ! wget -q --show-progress "$url" -O "$tmp"; then
            rm -f "$tmp"
            return 1
        fi
    else
        if ! curl -fL --retry 3 "$url" -o "$tmp"; then
            rm -f "$tmp"
            return 1
        fi
    fi

    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        echo "エラー: ダウンロードしたファイルが空じゃ: $url" >&2
        return 1
    fi
    mv -f "$tmp" "$target"
}

install_bazzite_dependencies() {
    local packages=()
    local command_name package_name

    if ! command -v brew > /dev/null 2>&1; then
        echo "エラー: Homebrew (brew) が見つからん。BazziteのHomebrew環境を確認するのじゃ。" >&2
        exit 1
    fi
    eval "$(brew shellenv)"

    for command_name in git ffmpeg python3 curl wget aria2c; do
        if ! command -v "$command_name" > /dev/null 2>&1; then
            case "$command_name" in
                python3) package_name="python" ;;
                aria2c) package_name="aria2" ;;
                *) package_name="$command_name" ;;
            esac
            packages+=("$package_name")
        fi
    done

    if [ "${#packages[@]}" -gt 0 ]; then
        echo "Homebrewで不足パッケージをインストール中: ${packages[*]}"
        brew install "${packages[@]}"
    fi

    for command_name in git ffmpeg python3 curl aria2c; do
        if ! command -v "$command_name" > /dev/null 2>&1; then
            echo "エラー: 必須コマンドが見つからん: $command_name" >&2
            exit 1
        fi
    done
}

install_umu() {
    if command -v umu-run > /dev/null 2>&1; then
        echo "UMU Launcher: $(command -v umu-run)"
        return
    fi

    if [ "$OS_TYPE" = "bazzite" ]; then
        echo "エラー: umu-runが見つからん。Bazziteのシステム更新でUMU Launcherを導入するのじゃ。" >&2
        exit 1
    fi

    local distro version arch suffix checksum filename url tempdir
    . /etc/os-release
    distro="$ID"
    version="${VERSION_ID:-}"
    arch=$(dpkg --print-architecture)
    case "$distro:$version:$arch" in
        ubuntu:24.04:amd64) suffix=ubuntu-noble; checksum=86b7a234f77fbcd13699654656192a12ed3852ec2bcc721506ae4f91436b3793 ;;
        ubuntu:26.04:amd64) suffix=ubuntu-resolute; checksum=5ec92ee8b2f3066d927d573cb485759dd96c3bdf73d25b0a39ec110fb974b502 ;;
        debian:12:amd64) suffix=debian-12; checksum=4197f59434deba9beeec97c16e2ef481e80d77390da178a99b10c8ea086cfd38 ;;
        debian:13:amd64) suffix=debian-13; checksum=602c4ac7210a54b835530f927b10c2781e51e294b1cf46448006e48fae66f232 ;;
        *) echo "エラー: $distro $version ($arch) 用のUMU Launcherが見つからん。先にumu-runを導入するのじゃ。" >&2; exit 1 ;;
    esac

    filename="python3-umu-launcher_1.4.4-1_${arch}_${suffix}.deb"
    url="https://github.com/Open-Wine-Components/umu-launcher/releases/download/1.4.4/$filename"
    tempdir=$(mktemp -d)
    if ! download_file "$url" "$tempdir/$filename"; then
        rm -rf "$tempdir"
        exit 1
    fi
    if ! printf '%s  %s\n' "$checksum" "$tempdir/$filename" | sha256sum -c -; then
        rm -rf "$tempdir"
        echo "エラー: UMU Launcherのチェックサムが一致せん。" >&2
        exit 1
    fi
    sudo apt-get install -y "$tempdir/$filename"
    rm -rf "$tempdir"
    if ! command -v umu-run > /dev/null 2>&1; then
        echo "エラー: UMU Launcherのインストールに失敗したぞ。" >&2
        exit 1
    fi
}

setup_proton_wrapper() {
    local wine_wrapper="$RUNTIME_DIR/bin/wine"
    local root candidate library_dir proton_script="" proton_dir=""
    local -a steam_roots=()
    local -a proton_candidates=()
    local -a preferred_candidates=()

    if [ -n "${PROTON_PATH:-}" ]; then
        if [ -f "$PROTON_PATH/proton" ]; then
            proton_script="$PROTON_PATH/proton"
        elif [ -f "$PROTON_PATH" ] && [ "$(basename "$PROTON_PATH")" = "proton" ]; then
            proton_script="$PROTON_PATH"
        else
            echo "エラー: 指定したProtonが見つからん: $PROTON_PATH" >&2
            exit 1
        fi
    elif [ "$OS_TYPE" = "bazzite" ]; then
        for root in "$HOME/.steam/root" "$HOME/.local/share/Steam" \
            "$HOME/.steam/steam" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
            if [ -d "$root/steamapps" ]; then
                steam_roots+=("$root")
                if [ -f "$root/steamapps/libraryfolders.vdf" ]; then
                    while IFS= read -r library_dir; do
                        if [ -d "$library_dir/steamapps" ]; then
                            steam_roots+=("$library_dir")
                        fi
                    done < <(awk -F '"' '$2 == "path" { print $4 }' "$root/steamapps/libraryfolders.vdf")
                fi
            fi
        done
        for root in "${steam_roots[@]}"; do
            for candidate in "$root"/compatibilitytools.d/*/proton \
                "$root"/steamapps/common/Proton*/proton; do
                if [ -f "$candidate" ]; then
                    proton_candidates+=("$candidate")
                    case "$(basename "$(dirname "$candidate")")" in
                        Proton\ [0-9]*|GE-Proton*) preferred_candidates+=("$candidate") ;;
                    esac
                fi
            done
        done
        if [ "${#preferred_candidates[@]}" -gt 0 ]; then
            proton_script=$(printf '%s\n' "${preferred_candidates[@]}" | LC_ALL=C sort -V | tail -n 1)
        elif [ "${#proton_candidates[@]}" -gt 0 ]; then
            proton_script=$(printf '%s\n' "${proton_candidates[@]}" | LC_ALL=C sort -V | tail -n 1)
        fi
    fi

    if [ -n "$proton_script" ]; then
        proton_dir=$(dirname "$(readlink -f "$proton_script")")
        echo "使用するProton: $proton_dir"
    else
        echo "UMU-Protonを使用するぞ (初回起動時に取得)。"
    fi

    if [ -e "$wine_wrapper" ] || [ -L "$wine_wrapper" ]; then
        if ! { [ -f "$wine_wrapper" ] &&
            { grep -Fq '# yt-dlp UMU Proton wrapper' "$wine_wrapper" ||
              grep -Fq '# yt-dlp Proton wrapper' "$wine_wrapper" ||
              grep -Fq 'distrobox enter -n yt-dlp-wine' "$wine_wrapper"; }; }; then
            echo "エラー: $wine_wrapper は既存のファイルじゃ。上書きはしないぞ。" >&2
            exit 1
        fi
    fi

    {
        printf '#!/bin/bash\n# yt-dlp UMU Proton wrapper\n'
        printf 'DEFAULT_PROTON_DIR=%q\n' "$proton_dir"
        printf 'DEFAULT_WINEPREFIX=%q\n' "$RUNTIME_DIR/proton-prefix"
        cat << 'EOF_PROTON'
set -e
show_help() {
    cat << 'EOF_HELP'
使用法: wine <Windowsプログラム.exe> [引数...]
        wine -h | --help

UMU LauncherからProtonを起動し、yt-dlp専用のPrefixを使用するのじゃ。
YT_DLP_PROTON_PATHで利用するProtonを上書きできるぞ。
EOF_HELP
}
if [ "$#" -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi
if ! command -v umu-run > /dev/null 2>&1; then
    echo "エラー: umu-runが見つからん。" >&2
    exit 1
fi
export GAMEID="umu-default"
export WINEPREFIX="${YT_DLP_WINEPREFIX:-$DEFAULT_WINEPREFIX}"
mkdir -p "$WINEPREFIX"
if [ -n "${YT_DLP_PROTON_PATH:-}" ]; then
    export PROTONPATH="$YT_DLP_PROTON_PATH"
elif [ -z "${PROTONPATH:-}" ] && [ -n "$DEFAULT_PROTON_DIR" ]; then
    export PROTONPATH="$DEFAULT_PROTON_DIR"
fi
exec umu-run "$@"
EOF_PROTON
    } > "$wine_wrapper"
    chmod +x "$wine_wrapper"
    install_owned_link "$wine_wrapper" "$LOCAL_BIN/wine"
    echo "UMU / Protonラッパーを配置したぞ: $wine_wrapper"
}

echo "yt-dlpをセットアップするのじゃ (OS: $OS_TYPE)"

# --- 1. 必須パッケージのインストール ---
if [ "$OS_TYPE" = "bazzite" ]; then
    install_bazzite_dependencies
else
    echo "システムパッケージを確認・インストール中 (sudoパスワードを入れるのじゃ)..."
    sudo apt-get update
    sudo apt-get install -y ffmpeg git python3 python3-venv curl wget aria2 ca-certificates
fi

# --- リポジトリを確定（以後の生成物はこのディレクトリ内に配置） ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if [ -f "$SCRIPT_DIR/yt-dlp config" ] && [ -f "$SCRIPT_DIR/z__run_sub_converter.sh" ]; then
    SOURCE_DIR="$SCRIPT_DIR"
else
    SOURCE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/yt-dlp/My_yt-dlp_config_script"
    REPO_URL="https://github.com/SyameimaruKoa/My_yt-dlp_config_script.git"
    if [ -d "$SOURCE_DIR/.git" ]; then
        git -C "$SOURCE_DIR" pull --ff-only
    elif [ -e "$SOURCE_DIR" ]; then
        echo "エラー: $SOURCE_DIR は既存のGitリポジトリではないぞ。" >&2
        exit 1
    else
        mkdir -p "$(dirname "$SOURCE_DIR")"
        git clone "$REPO_URL" "$SOURCE_DIR"
    fi
fi
RUNTIME_DIR="$SOURCE_DIR/.runtime/linux"
VENV_DIR="$RUNTIME_DIR/venv"
UPDATER_PATH="$SOURCE_DIR/tools/yt_dlp_auto_update.py"
mkdir -p "$RUNTIME_DIR/bin"
echo "管理対象の実体: $RUNTIME_DIR"

install_umu
setup_proton_wrapper
echo "システムパッケージの準備完了じゃ。"
echo "---"

if command -v aria2c > /dev/null 2>&1; then
    echo "ダウンローダー: aria2c"
elif command -v wget > /dev/null 2>&1; then
    echo "ダウンローダー: wget"
else
    echo "ダウンローダー: curl"
fi
echo "---"

# --- 2. yt-dlp Nightly と追加pipパッケージを仮想環境に導入 ---
echo "Python仮想環境を準備中: $VENV_DIR"
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
    echo "エラー: Python 3.11以上が必要じゃ。" >&2
    exit 1
fi
if [ ! -x "$VENV_DIR/bin/python" ]; then
    python3 -m venv "$VENV_DIR"
fi
if ! "$VENV_DIR/bin/python" -m pip --version > /dev/null 2>&1; then
    echo "エラー: 仮想環境内のpipが利用できん。python3-venvを確認するのじゃ。" >&2
    exit 1
fi
echo "yt-dlp Nightlyと追加依存関係をインストール中..."
"$VENV_DIR/bin/python" -m pip install --upgrade --upgrade-strategy eager --pre 'yt-dlp[default,curl-cffi,secretstorage]'

# 仮想環境を手動でactivateしなくても通常のyt-dlpコマンドで実行する
TARGET_PATH="$RUNTIME_DIR/bin/yt-dlp"
WRAPPER_TMP=$(mktemp)
{
    printf '#!/bin/bash\n# yt-dlp venv wrapper\n'
    printf 'VENV_PYTHON=%q\n' "$VENV_DIR/bin/python"
    printf 'UPDATER=%q\n' "$UPDATER_PATH"
    cat <<'EOF_YTDLP_WRAPPER'
show_help() {
    exec "$VENV_PYTHON" -m yt_dlp --help
}
if [ -f "$UPDATER" ] && [ "${YT_DLP_SKIP_UPDATE:-}" != "1" ]; then
    "$VENV_PYTHON" "$UPDATER" || true
fi
case "${1:-}" in
    -h|--help) show_help ;;
esac
exec "$VENV_PYTHON" -m yt_dlp "$@"
EOF_YTDLP_WRAPPER
} > "$WRAPPER_TMP"
install -m 755 "$WRAPPER_TMP" "$TARGET_PATH"
rm -f "$WRAPPER_TMP"
install_owned_link "$TARGET_PATH" "$LOCAL_BIN/yt-dlp"
if [ "$OS_TYPE" = "apt" ]; then
    install_owned_link "$TARGET_PATH" /usr/local/bin/yt-dlp true
fi
echo "yt-dlp実体: $TARGET_PATH"
echo "yt-dlp起動リンク: $LOCAL_BIN/yt-dlp"
"$VENV_DIR/bin/python" -m yt_dlp --version
echo "---"

# --- 3. Windows版 YTSubConverter.exe のインストール ---
INSTALL_DIR="$RUNTIME_DIR/tools/YTSubConverter"
EXE_PATH="$INSTALL_DIR/YTSubConverter.exe"
EXE_URL="https://github.com/arcusmaximus/YTSubConverter/releases/download/1.6.4/YTSubConverter.exe"

echo "Windows版 YTSubConverter.exe を配置中..."
download_file "$EXE_URL" "$EXE_PATH"
LEGACY_CONVERTER="$HOME/.config/yt-dlp/tools/YTSubConverter/YTSubConverter.exe"
mkdir -p "$(dirname "$LEGACY_CONVERTER")"
if [ -f "$LEGACY_CONVERTER" ] && [ ! -L "$LEGACY_CONVERTER" ]; then
    if cmp -s "$LEGACY_CONVERTER" "$EXE_PATH"; then
        rm -f -- "$LEGACY_CONVERTER"
    else
        echo "エラー: 既存の字幕変換ツールがダウンロード版と異なる: $LEGACY_CONVERTER" >&2
        exit 1
    fi
fi
if [ ! -e "$LEGACY_CONVERTER" ] && [ ! -L "$LEGACY_CONVERTER" ]; then
    ln -s -- "$EXE_PATH" "$LEGACY_CONVERTER"
fi
echo "字幕変換ツール実体: $EXE_PATH"
echo "---"

# --- 4. Protonの準備 ---
echo "YTSubConverter.exeはUMU / Proton経由で実行するぞ。"
echo "---"

# --- 5. リポジトリ内の設定と字幕変換スクリプトをリンク ---
CONFIG_DIR="$HOME/.config/yt-dlp"

LINK_CONFIG="$CONFIG_DIR/config"
LINK_SCRIPT="$CONFIG_DIR/z__run_sub_converter.sh"
SOURCE_CONFIG="$SOURCE_DIR/yt-dlp config"
SOURCE_SCRIPT="$SOURCE_DIR/z__run_sub_converter.sh"
UPDATER_SOURCE="$SOURCE_DIR/tools/yt_dlp_auto_update.py"
if [ ! -f "$UPDATER_SOURCE" ]; then
    echo "エラー: 更新確認スクリプトが見つからん: $UPDATER_SOURCE" >&2
    exit 1
fi
mkdir -p "$CONFIG_DIR"
ln -s -f "$SOURCE_CONFIG" "$LINK_CONFIG"
ln -s -f "$SOURCE_SCRIPT" "$LINK_SCRIPT"
chmod +x "$SOURCE_SCRIPT"
echo "設定ファイル: $LINK_CONFIG"
echo "yt-dlp起動時の自動更新: $UPDATER_PATH"
echo "---"

# --- 6. Deno のインストール ---
echo "Deno (JavaScriptランタイム) をインストールするのじゃ..."
export DENO_INSTALL="$RUNTIME_DIR/deno"
curl -fsSL https://deno.land/install.sh | sh
if [ -x "$RUNTIME_DIR/deno/bin/deno" ]; then
    install_owned_link "$RUNTIME_DIR/deno/bin/deno" "$LOCAL_BIN/deno"
else
    echo "エラー: リポジトリ内にDenoが導入されておらん。" >&2
    exit 1
fi
echo "Deno のインストール処理完了じゃ。"
echo "---"

# --- 7. 旧方式の残骸を整理（新設定・仮想環境の導入に成功した後） ---
CLEANUP_SCRIPT="$SOURCE_DIR/tools/migration/remove-standalone.sh"
if [ -f "$CLEANUP_SCRIPT" ]; then
    echo "旧方式の不要ファイルを確認中..."
    if ! bash "$CLEANUP_SCRIPT" --legacy-gist --legacy-runtime; then
        echo "警告: 旧方式のファイル整理に失敗したぞ。手動で確認するのじゃ。" >&2
    fi
fi
echo "---"

echo "全てのセットアップが完了したぞ。今度こそ完璧じゃ！"
