#!/bin/bash
#
# yt-dlp (Nightly) と Gist の設定ファイル、および YTSubConverter をインストールするスクリプト
# (aria2c, wget, curl のいずれかを利用可能なものでダウンロード)
# (既存の設定ファイルを強制的にシンボリックリンクで上書き)
#
# このスクリプトは引数を取らずに実行します。
# ヘルプ表示: ./setup_yt-dlp.sh -h

# --- エラー処理 ---
# エラーが発生したらスクリプトを終了する
set -e

# --- ヘルプ表示用の関数 (ユーザー指示) ---
show_help() {
    cat << EOF
使用法: $(basename "$0")
       $(basename "$0") -h | --help

このスクリプトは以下の処理を一括で行うのじゃ:
  1. yt-dlp の最新 Nightly ビルドをインストール
  2. YTSubConverter (Linux版) を .deb パッケージからインストール
  3. Gist (21141912fbacf40877f4cf877577e082) から設定ファイルをクローン
  4. 設定ファイル(config) と 字幕変換スクリプト(z__run_sub_converter.sh) の
     シンボリックリンクを ~/.config/yt-dlp/ に作成

ダウンロードには aria2c, wget, curl のいずれかを利用します。
(優先度: aria2c > wget > curl)

*** 注意 ***
~/.config/yt-dlp/config に既存のファイルやリンクがあっても、
強制的に上書きして Gist の設定ファイルへのリンクを作成します。

このスクリプトは引数を必要としません。

オプション:
  -h, --help    このヘルプメッセージを表示します。
EOF
}

# --- 引数の処理 (ユーザー指示) ---
# 引数がある場合のみ処理
if [ $# -gt 0 ]; then
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "エラー: 不正な引数です: $1" >&2
            echo ""
            show_help
            exit 1
            ;;
    esac
fi

# --- メイン処理 ---
echo "yt-dlp (Nightly) & YTSubConverter セットアップ処理を開始するのじゃ。"

# 必要なコマンドの存在チェック (sudo, git, python3)
for cmd in git sudo python3; do
    if ! command -v $cmd &> /dev/null; then
        echo "エラー: 実行に必要な '$cmd' が見つからんぞ。" >&2
        exit 1
    fi
done

# --- ダウンロードツールの確認 (優先度: aria2c > wget > curl) ---
DL_TOOL=""
if command -v aria2c &> /dev/null; then
    DL_TOOL="aria2c"
elif command -v wget &> /dev/null; then
    DL_TOOL="wget"
elif command -v curl &> /dev/null; then
    DL_TOOL="curl"
else
    echo "エラー: ダウンロードに必要なコマンド (aria2c, wget, curl のいずれか) が見つからんぞ。" >&2
    exit 1
fi
echo "ダウンロードには '$DL_TOOL' を使うぞ。"
echo "---"


# 1. yt-dlp (Nightly) のダウンロードとインストール
# Nightlyビルドのリポジトリから最新のバイナリを取得
URL="https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp"
TARGET_PATH="/usr/local/bin/yt-dlp"

echo "yt-dlp (Nightly) をダウンロードしてインストールするぞ... (sudo がパスワードを尋ねるやもしれん)"

DOWNLOAD_SUCCESS=false
case "$DL_TOOL" in
    aria2c)
        TARGET_DIR=$(dirname "$TARGET_PATH")
        TARGET_FILE=$(basename "$TARGET_PATH")
        if sudo aria2c -d "$TARGET_DIR" -o "$TARGET_FILE" --allow-overwrite=true "$URL"; then
            DOWNLOAD_SUCCESS=true
        fi
        ;;
    wget)
        if sudo wget "$URL" -O "$TARGET_PATH"; then
            DOWNLOAD_SUCCESS=true
        fi
        ;;
    curl)
        if sudo curl -L "$URL" -o "$TARGET_PATH"; then
            DOWNLOAD_SUCCESS=true
        fi
        ;;
esac

if [ "$DOWNLOAD_SUCCESS" != "true" ]; then
    echo "エラー: yt-dlp ($DL_TOOL を使用) のダウンロードに失敗したぞ。" >&2
    exit 1
fi

# 権限付与 (共通)
if ! sudo chmod a+rx "$TARGET_PATH"; then
    echo "エラー: yt-dlp への実行権限の付与に失敗したぞ。" >&2
    exit 1
fi
echo "yt-dlp (Nightly) のインストール完了じゃ。"
echo "---"

# 2. YTSubConverter のインストール
echo "YTSubConverter (.deb) をインストール中..."
YTSC_URL="https://github.com/arcusmaximus/YTSubConverter/releases/download/1.6.4/YTSubConverter-Linux.deb"
TEMP_DEB="/tmp/YTSubConverter-Linux.deb"

# .debファイルのダウンロード
case "$DL_TOOL" in
    aria2c) aria2c -d "/tmp" -o "YTSubConverter-Linux.deb" --allow-overwrite=true "$YTSC_URL" ;;
    wget)   wget "$YTSC_URL" -O "$TEMP_DEB" ;;
    curl)   curl -L "$YTSC_URL" -o "$TEMP_DEB" ;;
esac

# インストール実行 (apt-get install ./file.deb で依存関係も解決させる)
if [ -f "$TEMP_DEB" ]; then
    echo "apt で .deb パッケージをインストールするぞ..."
    sudo apt-get update
    sudo apt-get install -y "$TEMP_DEB"
    rm "$TEMP_DEB"
    echo "YTSubConverter のインストール完了じゃ。"
else
    echo "エラー: YTSubConverter パッケージのダウンロードに失敗したようじゃな。" >&2
    exit 1
fi
echo "---"

# 3. Gist のクローン
GIST_DIR="$HOME/21141912fbacf40877f4cf877577e082"
GIST_URL="https://gist.github.com/21141912fbacf40877f4cf877577e082.git"

if [ -d "$GIST_DIR" ]; then
    echo "Gist ディレクトリ ($GIST_DIR) は既に存在しとるな。クローンは飛ばすぞ。"
else
    echo "Gist ($GIST_URL) をクローン中..."
    if ! git clone "$GIST_URL" "$GIST_DIR"; then
        echo "エラー: Gist のクローンに失敗したぞ。" >&2
        exit 1
    fi
    echo "Gist のクローン完了じゃ。"
fi
echo "---"

# 4. 設定ファイルとスクリプトのシンボリックリンク作成
CONFIG_DIR="$HOME/.config/yt-dlp"

# リンク先パス
LINK_CONFIG="$CONFIG_DIR/config"
LINK_SCRIPT="$CONFIG_DIR/z__run_sub_converter.sh"

# Gist内の実体パス
SOURCE_CONFIG="$GIST_DIR/yt-dlp config" # ファイル名にスペース
SOURCE_SCRIPT="$GIST_DIR/z__run_sub_converter.sh"

echo "設定ディレクトリ ($CONFIG_DIR) を確認・作成中..."
if ! mkdir -p "$CONFIG_DIR"; then
    echo "エラー: 設定ディレクトリの作成に失敗したぞ: $CONFIG_DIR" >&2
    exit 1
fi

# --- config ファイルのリンク ---
if [ -f "$SOURCE_CONFIG" ]; then
    echo "設定ファイル ($LINK_CONFIG) のシンボリックリンクを【強制的に】作成するぞ。"
    if ! ln -s -f "$SOURCE_CONFIG" "$LINK_CONFIG"; then
        echo "エラー: config のリンク作成に失敗したぞ。" >&2
        exit 1
    fi
    echo "config のリンク作成完了じゃ。"
else
    echo "エラー: Gist 内に設定ファイルが見当たらん: $SOURCE_CONFIG" >&2
    exit 1
fi

# --- 変換スクリプトのリンク ---
if [ -f "$SOURCE_SCRIPT" ]; then
    echo "変換スクリプト ($LINK_SCRIPT) のシンボリックリンクを作成し、実行権限を付与するぞ。"
    if ! ln -s -f "$SOURCE_SCRIPT" "$LINK_SCRIPT"; then
        echo "エラー: スクリプトのリンク作成に失敗したぞ。" >&2
        exit 1
    fi
    # 実行権限は実体ファイルに付与する
    chmod +x "$SOURCE_SCRIPT"
    echo "スクリプトのリンク作成と権限付与完了じゃ。"
else
    echo "警告: Gist 内に変換スクリプトが見当たらんぞ ($SOURCE_SCRIPT)。" >&2
fi

echo "---"
echo "すべての処理が完了したぞ。これで文句なかろうな？"