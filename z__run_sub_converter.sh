#!/bin/bash
#
# yt-dlp から呼び出される字幕変換スクリプト (Wine版・/tmp作業対応)
#
# 使用法: z__run_sub_converter.sh "動画ファイルのパス"
#

# --- ヘルプ表示 ---
show_help() {
    cat << EOF
使用法: $(basename "$0") [動画ファイルのパス]
       $(basename "$0") -h | --help

.srv3 字幕ファイルを検出し、一時ディレクトリ(/tmp)で変換を行ってから書き戻すのじゃ。
  - 装飾タグあり -> Wine 経由で Windows版 YTSubConverter.exe を実行 (.ass)
  - 装飾タグなし -> シンプルな .srt に変換 (Python使用)

オプション:
  -h, --help    このヘルプを表示
EOF
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_help
    exit 0
fi

VIDEO_PATH="$1"
if [ -z "$VIDEO_PATH" ]; then
    echo "エラー: 動画パスが指定されておらんぞ。"
    exit 1
fi

# パス情報の取得
VIDEO_DIR=$(dirname "$VIDEO_PATH")
VIDEO_BASENAME=$(basename "$VIDEO_PATH")
VIDEO_NAME_NOEXT="${VIDEO_BASENAME%.*}"

# Windows版ツールのパス
EXE_PATH="$HOME/.config/yt-dlp/tools/YTSubConverter/YTSubConverter.exe"

# 一時作業ディレクトリの作成
WORK_DIR=$(mktemp -d)
echo "--- 字幕変換処理 (/tmp作業モード) ---"
echo "対象動画: $VIDEO_BASENAME"
echo "作業場所: $WORK_DIR"

# 終了時に一時ディレクトリを削除するトラップを設定
cleanup() {
    rm -rf "$WORK_DIR"
    # echo "作業場所を掃除したぞ。"
}
trap cleanup EXIT

# Wine と EXE の確認
USE_WINE=false
if command -v wine &> /dev/null; then
    if [ -f "$EXE_PATH" ]; then
        USE_WINE=true
    else
        echo "警告: YTSubConverter.exe が見つからん ($EXE_PATH)。"
    fi
else
    echo "警告: 'wine' コマンドが見つからん。"
fi

# NAS上のファイルを検索
find "$VIDEO_DIR" -maxdepth 1 -name "*.srv3" | while read -r SUB_FILE_FULLPATH; do
    SUB_FILENAME=$(basename "$SUB_FILE_FULLPATH")
    
    # 動画ファイル名を含むものだけ対象にする
    if [[ "$SUB_FILENAME" != *"$VIDEO_NAME_NOEXT"* ]]; then continue; fi

    echo "処理中: $SUB_FILENAME"

    # 1. ファイルを一時ディレクトリにコピー
    cp "$SUB_FILE_FULLPATH" "$WORK_DIR/"
    
    # 2. 一時ディレクトリに移動して作業
    # (サブシェル () を使うことで、ディレクトリ移動の影響をこのブロックだけに留める)
    (
        cd "$WORK_DIR" || exit 1
        
        # ファイル内容チェック
        NEEDS_CONVERSION=false
        if grep -q "<span" "$SUB_FILENAME"; then NEEDS_CONVERSION=true; fi
        if grep -q "<u" "$SUB_FILENAME"; then NEEDS_CONVERSION=true; fi
        if grep -q "<pen" "$SUB_FILENAME"; then NEEDS_CONVERSION=true; fi

        if [ "$NEEDS_CONVERSION" = true ]; then
            echo "  [装飾あり] -> Wineで変換 (.ass)"
            OUTPUT_ASS="${SUB_FILENAME%.*}.ass"
            
            if [ "$USE_WINE" = true ]; then
                # Wine実行 (エラーログは捨てるが、失敗時はステータスコードで判断)
                wine "$EXE_PATH" "$SUB_FILENAME" "$OUTPUT_ASS" 2>&1 >/dev/null
                
                if [ -f "$OUTPUT_ASS" ]; then
                    # 3. 成功したら元の場所(NAS)に書き戻す
                    mv "$OUTPUT_ASS" "$VIDEO_DIR/"
                    echo "  -> 成功: $OUTPUT_ASS をNASに転送したぞ。"
                    
                    # 4. 元のファイルを削除
                    rm "$SUB_FILE_FULLPATH"
                else
                    echo "  -> 警告: 変換失敗。出力ファイルが生成されなかった。"
                fi
            else
                echo "  -> エラー: Wine環境がないためスキップ。"
            fi

        else
            echo "  [シンプル] -> .srt に変換 (Python)"
            OUTPUT_SRT="${SUB_FILENAME%.*}.srt"

            # Pythonスクリプト
            python3 -c '
import sys
import xml.etree.ElementTree as ET

def ms_to_srt_time(ms):
    h = ms // 3600000
    ms %= 3600000
    m = ms // 60000
    ms %= 60000
    s = ms // 1000
    ms %= 1000
    return "{:02d}:{:02d}:{:02d},{:03d}".format(h, m, s, ms)

try:
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    tree = ET.parse(input_file)
    root = tree.getroot()
    lines = []
    index = 1
    for p in root.findall(".//p"):
        try:
            t = int(p.get("t", 0))
            d = int(p.get("d", 0))
        except: continue
        text = "".join(p.itertext()).strip()
        if not text: continue
        lines.append(str(index))
        lines.append(f"{ms_to_srt_time(t)} --> {ms_to_srt_time(t+d)}")
        lines.append(text)
        lines.append("")
        index += 1
    with open(output_file, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
except Exception as e:
    print(f"Python Error: {e}")
    sys.exit(1)
' "$SUB_FILENAME" "$OUTPUT_SRT"

            if [ $? -eq 0 ] && [ -f "$OUTPUT_SRT" ]; then
                mv "$OUTPUT_SRT" "$VIDEO_DIR/"
                echo "  -> 成功: $OUTPUT_SRT をNASに転送したぞ。"
                rm "$SUB_FILE_FULLPATH"
            else
                echo "  -> 警告: .srt への変換に失敗したぞ。"
            fi
        fi
    )
done

echo "--- 処理完了 ---"