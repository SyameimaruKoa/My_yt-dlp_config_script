#!/bin/bash
#
# yt-dlp (Nightly) と Windows版YTSubConverter (Wine動作) をセットアップするのじゃ
#
# 使用法: ./z__setup_yt-dlp.sh
# ヘルプ: ./z__setup_yt-dlp.sh -h

set -e

# --- ヘルプ表示 ---
show_help() {
    cat << EOF
使用法: $(basename "$0")
       $(basename "$0") -h | --help

機能:
  1. システムパッケージ (git, ffmpeg, python3, wine, unzip) のインストール
  2. yt-dlp の最新 Nightly ビルドをインストール
  3. YTSubConverter (Windows版) をダウンロードして配置
  4. Gist (21141912fbacf40877f4cf877577e082) から設定ファイルをクローン
  5. 各種シンボリックリンクを作成

オプション:
  -h, --help    このヘルプを表示するのじゃ
EOF
}

if [ $# -gt 0 ]; then
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        *) echo "エラー: 不明な引数じゃ: $1" >&2; show_help; exit 1 ;;
    esac
fi

echo "Wine環境で構築し直すぞ。覚悟はいいか？"

# --- 1. 必須パッケージ (Wine含む) のインストール ---
echo "システムパッケージを確認・インストール中 (sudoパスワードを入れるのじゃ)..."
sudo apt-get update
# wine と unzip を追加
sudo apt-get install -y ffmpeg git python3 curl wget aria2 wine unzip

echo "システムパッケージの準備完了じゃ。"
echo "---"

# ダウンローダー確認
DL_TOOL="aria2c"
if ! command -v aria2c &> /dev/null; then DL_TOOL="wget"; fi
echo "ダウンローダー: $DL_TOOL"
echo "---"

# --- 2. yt-dlp (Nightly) のインストール ---
URL="https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp"
TARGET_PATH="/usr/local/bin/yt-dlp"

echo "yt-dlp (Nightly) を更新中..."
DOWNLOAD_SUCCESS=false
case "$DL_TOOL" in
    aria2c) sudo aria2c -d "$(dirname "$TARGET_PATH")" -o "$(basename "$TARGET_PATH")" --allow-overwrite=true "$URL" && DOWNLOAD_SUCCESS=true ;;
    wget)   sudo wget "$URL" -O "$TARGET_PATH" && DOWNLOAD_SUCCESS=true ;;
    *)      sudo curl -L "$URL" -o "$TARGET_PATH" && DOWNLOAD_SUCCESS=true ;;
esac

if [ "$DOWNLOAD_SUCCESS" != "true" ]; then
    echo "エラー: yt-dlp のダウンロードに失敗じゃ。" >&2
    exit 1
fi
sudo chmod a+rx "$TARGET_PATH"
echo "yt-dlp 更新完了。"
echo "---"

# --- 3. Windows版 YTSubConverter のインストール ---
# 配置場所: ~/.config/yt-dlp/tools/YTSubConverter
INSTALL_DIR="$HOME/.config/yt-dlp/tools/YTSubConverter"
EXE_PATH="$INSTALL_DIR/YTSubConverter.exe"
ZIP_URL="https://github.com/arcusmaximus/YTSubConverter/releases/download/1.6.4/YTSubConverter-1.6.4.zip"
TEMP_ZIP="/tmp/YTSubConverter.zip"

echo "Windows版 YTSubConverter をセットアップ中..."

if [ -f "$EXE_PATH" ]; then
    echo "既にインストール済みじゃな ($EXE_PATH)。スキップするぞ。"
else
    mkdir -p "$INSTALL_DIR"
    
    case "$DL_TOOL" in
        aria2c) aria2c -d "/tmp" -o "YTSubConverter.zip" --allow-overwrite=true "$ZIP_URL" ;;
        wget)   wget "$ZIP_URL" -O "$TEMP_ZIP" ;;
        *)      curl -L "$ZIP_URL" -o "$TEMP_ZIP" ;;
    esac

    if [ -f "$TEMP_ZIP" ]; then
        echo "解凍中..."
        unzip -o "$TEMP_ZIP" -d "$INSTALL_DIR"
        rm "$TEMP_ZIP"
        echo "配置完了じゃ。"
    else
        echo "エラー: Zipファイルのダウンロードに失敗したようじゃ。" >&2
        exit 1
    fi
fi
echo "---"

# --- 4. Gist設定のクローン & リンク作成 ---
GIST_DIR="$HOME/21141912fbacf40877f4cf877577e082"
GIST_URL="https://gist.github.com/21141912fbacf40877f4cf877577e082.git"
CONFIG_DIR="$HOME/.config/yt-dlp"

LINK_CONFIG="$CONFIG_DIR/config"
LINK_SCRIPT="$CONFIG_DIR/z__run_sub_converter.sh"
SOURCE_CONFIG="$GIST_DIR/yt-dlp config"
SOURCE_SCRIPT="$GIST_DIR/z__run_sub_converter.sh"

if [ ! -d "$GIST_DIR" ]; then
    git clone "$GIST_URL" "$GIST_DIR" || exit 1
else
    cd "$GIST_DIR" && git pull
fi

mkdir -p "$CONFIG_DIR"

# リンク作成
ln -s -f "$SOURCE_CONFIG" "$LINK_CONFIG"
ln -s -f "$SOURCE_SCRIPT" "$LINK_SCRIPT"
chmod +x "$SOURCE_SCRIPT"

echo "---"
echo "Wine環境セットアップ完了じゃ。これで文句なかろう！"