#!/bin/bash
#
# yt-dlp と Gist の設定ファイルをインストールするスクリプト
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

このスクリプトは yt-dlp の最新版をインストールし、
Gist (21141912fbacf40877f4cf877577e082) から設定ファイルをクローンして
シンボリックリンクを作成します。

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
echo "yt-dlp セットアップ処理を開始するのじゃ。"

# 必要なコマンドの存在チェック (sudo, git)
if ! command -v git &> /dev/null; then
    echo "エラー: 実行に必要な 'git' が見つからんぞ。" >&2
    exit 1
fi
if ! command -v sudo &> /dev/null; then
    echo "エラー: 実行に必要な 'sudo' が見つからんぞ。" >&2
    exit 1
fi

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


# 1. yt-dlp のダウンロードとインストール
URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
TARGET_PATH="/usr/local/bin/yt-dlp"

echo "yt-dlp をダウンロードしてインストールするぞ... (sudo がパスワードを尋ねるやもしれん)"

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
echo "yt-dlp のインストール完了じゃ。"
echo "---"

# 2. Gist のクローン
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

# 3. 設定ファイルのシンボリックリンク作成
CONFIG_DIR="$HOME/.config/yt-dlp"
CONFIG_FILE="$CONFIG_DIR/config"
SOURCE_FILE="$GIST_DIR/yt-dlp config" # ファイル名にスペース

echo "設定ディレクトリ ($CONFIG_DIR) を確認・作成中..."
if ! mkdir -p "$CONFIG_DIR"; then
    echo "エラー: 設定ディレクトリの作成に失敗したぞ: $CONFIG_DIR" >&2
    exit 1
fi

# ソースファイルの存在確認
if [ ! -f "$SOURCE_FILE" ]; then
    echo "エラー: Gist でクローンしたはずの設定ファイルが見当たらん: $SOURCE_FILE" >&2
    echo "Gist の中身が変わったか、クローンに失敗したかじゃな。" >&2
    exit 1
fi

# --- リンク作成処理 (変更点) ---
echo "シンボリックリンク ($CONFIG_FILE) を【強制的に】作成するぞ。"
echo "もし既存のファイルやリンクがあっても上書きするからの。"

# -f (force) で既存のファイルを削除してリンクを作成
# -s (symbolic)
# ファイル名にスペースがあるのでクォート必須じゃ
if ! ln -s -f "$SOURCE_FILE" "$CONFIG_FILE"; then
     echo "エラー: シンボリックリンクの作成に失敗したぞ。" >&2
     exit 1
fi
echo "シンボリックリンクの作成/上書き完了じゃ。"


echo "---"
echo "すべての処理が完了したぞ。これで文句なかろうな？"