#!/bin/bash
#
# yt-dlp (Nightly) と Windows版YTSubConverter.exe (Wine動作) をセットアップするのじゃ
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
1. 必須パッケージ (git, ffmpeg, python3, curl, wget, aria2, Wine) の準備
   Ubuntu / Debian: apt-get
   Bazzite: Homebrew と Distrobox (OS本体の変更・再起動なし)
2. yt-dlp の最新 Nightly ビルドをインストール
3. YTSubConverter.exe をダウンロードして配置
4. Wine Mono 9.0.0 をダウンロードしてインストール
5. Gist から設定ファイルと字幕変換スクリプトを取得
6. Deno (JavaScriptランタイム) をインストール
7. 各種シンボリックリンクを作成

オプション:
-h, --help  このヘルプを表示するのじゃ
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

setup_bazzite_wine() {
    local box_name="yt-dlp-wine"
    local wine_wrapper="$LOCAL_BIN/wine"

    if command -v wine > /dev/null 2>&1 && \
        ! { [ -f "$wine_wrapper" ] && grep -Fq 'distrobox enter -n yt-dlp-wine' "$wine_wrapper"; }; then
        echo "既存のWineを使用するぞ。"
        return
    fi

    if ! command -v distrobox > /dev/null 2>&1 || \
        ! command -v podman > /dev/null 2>&1; then
        echo "エラー: Distrobox と Podman が必要じゃ。" >&2
        exit 1
    fi

    if ! podman container exists "$box_name"; then
        echo "Wine用Distroboxを作成中..."
        distrobox create --name "$box_name" --image quay.io/fedora/fedora:44 \
            --volume /tmp:/tmp:rw --yes
    fi

    echo "Distrobox内のWineを確認・インストール中..."
    distrobox enter -n "$box_name" -- sudo dnf install -y wine-core

    if [ -e "$wine_wrapper" ] && \
        ! grep -Fq 'distrobox enter -n yt-dlp-wine' "$wine_wrapper"; then
        echo "エラー: $wine_wrapper は既存のファイルじゃ。上書きはしないぞ。" >&2
        exit 1
    fi

    cat > "$wine_wrapper" << 'EOF_WINE'
#!/bin/bash
exec distrobox enter -n yt-dlp-wine -- /usr/bin/wine "$@"
EOF_WINE
    chmod +x "$wine_wrapper"
}

echo "yt-dlpをセットアップするのじゃ (OS: $OS_TYPE)"

# --- 1. 必須パッケージ (Wine含む) のインストール ---
if [ "$OS_TYPE" = "bazzite" ]; then
    install_bazzite_dependencies
    setup_bazzite_wine
else
    echo "システムパッケージを確認・インストール中 (sudoパスワードを入れるのじゃ)..."
    sudo apt-get update
    sudo apt-get install -y ffmpeg git python3 curl wget aria2 wine
fi

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

# --- 2. yt-dlp (Nightly) のインストール ---
URL="https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp"
if [ "$OS_TYPE" = "bazzite" ]; then
    TARGET_PATH="$LOCAL_BIN/yt-dlp"
else
    TARGET_PATH="/usr/local/bin/yt-dlp"
fi

echo "yt-dlp (Nightly) を更新中..."
if [ "$OS_TYPE" = "bazzite" ]; then
    download_file "$URL" "$TARGET_PATH"
    chmod a+rx "$TARGET_PATH"
else
    TEMP_YTDLP=$(mktemp)
    trap 'rm -f "$TEMP_YTDLP"' EXIT
    download_file "$URL" "$TEMP_YTDLP"
    sudo install -m 755 "$TEMP_YTDLP" "$TARGET_PATH"
    rm -f "$TEMP_YTDLP"
    trap - EXIT
fi
echo "yt-dlp 更新完了。"
echo "---"

# --- 3. Windows版 YTSubConverter.exe のインストール ---
INSTALL_DIR="$HOME/.config/yt-dlp/tools/YTSubConverter"
EXE_PATH="$INSTALL_DIR/YTSubConverter.exe"
EXE_URL="https://github.com/arcusmaximus/YTSubConverter/releases/download/1.6.4/YTSubConverter.exe"

echo "Windows版 YTSubConverter.exe を配置中..."
download_file "$EXE_URL" "$EXE_PATH"
echo "EXE配置完了。"
echo "---"

# --- 4. Wine Mono の手動インストール ---
echo "Wine Mono 9.0.0 をセットアップするぞ..."
MONO_VERSION="9.0.0"
MONO_MSI="wine-mono-${MONO_VERSION}-x86.msi"
MONO_URL="https://dl.winehq.org/wine/wine-mono/${MONO_VERSION}/${MONO_MSI}"

if [ "$OS_TYPE" = "bazzite" ]; then
    TEMP_MSI="$HOME/.cache/yt-dlp/$MONO_MSI"
else
    TEMP_MSI="/tmp/$MONO_MSI"
fi

if [ ! -s "$TEMP_MSI" ]; then
    echo "インストーラーをダウンロード中..."
    download_file "$MONO_URL" "$TEMP_MSI"
fi

echo "Wine Mono をインストール中 (画面は出ないぞ)..."
wine msiexec /i "$TEMP_MSI"
echo "インストールコマンド送信完了。少し待機する..."
sleep 5
echo "---"

# --- 5. Gist設定のクローン & リンク作成 ---
GIST_DIR="$HOME/21141912fbacf40877f4cf877577e082"
GIST_URL="https://gist.github.com/21141912fbacf40877f4cf877577e082.git"
CONFIG_DIR="$HOME/.config/yt-dlp"

LINK_CONFIG="$CONFIG_DIR/config"
LINK_SCRIPT="$CONFIG_DIR/z__run_sub_converter.sh"
SOURCE_CONFIG="$GIST_DIR/yt-dlp config"
SOURCE_SCRIPT="$GIST_DIR/z__run_sub_converter.sh"

if [ ! -d "$GIST_DIR/.git" ]; then
    if [ -e "$GIST_DIR" ]; then
        echo "エラー: $GIST_DIR は既に存在するがGitリポジトリではないぞ。" >&2
        exit 1
    fi
    git clone "$GIST_URL" "$GIST_DIR"
else
    git -C "$GIST_DIR" pull --ff-only
fi

if [ ! -f "$SOURCE_CONFIG" ] || [ ! -f "$SOURCE_SCRIPT" ]; then
    echo "エラー: Gistの設定ファイルまたは字幕変換スクリプトが見つからん。" >&2
    exit 1
fi

mkdir -p "$CONFIG_DIR"
ln -s -f "$SOURCE_CONFIG" "$LINK_CONFIG"
ln -s -f "$SOURCE_SCRIPT" "$LINK_SCRIPT"
chmod +x "$SOURCE_SCRIPT"
echo "---"

# --- 6. Deno のインストール ---
echo "Deno (JavaScriptランタイム) をインストールするのじゃ..."
curl -fsSL https://deno.land/install.sh | sh
if [ -x "$HOME/.deno/bin/deno" ] && { [ ! -e "$LOCAL_BIN/deno" ] || [ -L "$LOCAL_BIN/deno" ]; }; then
    ln -s -f "$HOME/.deno/bin/deno" "$LOCAL_BIN/deno"
fi
echo "Deno のインストール処理完了じゃ。"
echo "---"

echo "全てのセットアップが完了したぞ。今度こそ完璧じゃ！"
