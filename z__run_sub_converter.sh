#!/bin/bash
#
# yt-dlp から呼び出される字幕変換スクリプト (Wine版)
#
# 使用法: z__run_sub_converter.sh "動画ファイルのパス"
#

# --- ヘルプ表示 ---
show_help() {
    cat << EOF
使用法: $(basename "$0") [動画ファイルのパス]
       $(basename "$0") -h | --help

.srv3 字幕ファイルを検出し、内容に応じて変換を行うのじゃ。
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

VIDEO_DIR=$(dirname "$VIDEO_PATH")
VIDEO_BASENAME=$(basename "$VIDEO_PATH")
VIDEO_NAME_NOEXT="${VIDEO_BASENAME%.*}"
# Windows版のパス
EXE_PATH="$HOME/.config/yt-dlp/tools/YTSubConverter/YTSubConverter.exe"

echo "--- 字幕変換処理 (Wine版) ---"
echo "動画: $VIDEO_PATH"

# Wine と EXE の確認
USE_WINE=false
if command -v wine &> /dev/null; then
    if [ -f "$EXE_PATH" ]; then
        USE_WINE=true
        echo "ツール確認: OK (Wine + $EXE_PATH)"
    else
        echo "警告: YTSubConverter.exe が見つからん ($EXE_PATH)。セットアップを実行したか？"
    fi
else
    echo "警告: 'wine' コマンドが見つからん。インストールせよ。"
fi

# .srv3 ファイルを探す
find "$VIDEO_DIR" -maxdepth 1 -name "*.srv3" | while read -r SUB_FILE; do
    if [[ "$SUB_FILE" != *"$VIDEO_NAME_NOEXT"* ]]; then continue; fi

    echo "処理中: $SUB_FILE"
    
    # ファイル内容チェック
    NEEDS_CONVERSION=false
    if grep -q "<span" "$SUB_FILE"; then NEEDS_CONVERSION=true; fi
    if grep -q "<u" "$SUB_FILE"; then NEEDS_CONVERSION=true; fi
    if grep -q "<pen" "$SUB_FILE"; then NEEDS_CONVERSION=true; fi

    if [ "$NEEDS_CONVERSION" = true ]; then
        echo "装飾タグ検出 -> Wineで変換 (.ass)"
        OUTPUT_ASS="${SUB_FILE%.*}.ass"
        
        if [ "$USE_WINE" = true ]; then
            # Wine実行 (デバッグログ抑制)
            WINEDEBUG=-all wine "$EXE_PATH" "$SUB_FILE" "$OUTPUT_ASS"
            
            if [ -f "$OUTPUT_ASS" ]; then
                echo "変換完了: $OUTPUT_ASS"
                rm "$SUB_FILE"
            else
                echo "警告: Wineでの変換に失敗したようじゃ。"
            fi
        else
            echo "エラー: Wine環境が整っていないため変換できん。"
        fi

    else
        echo "シンプルXML -> .srt に変換 (Python使用)"
        OUTPUT_SRT="${SUB_FILE%.*}.srt"

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
' "$SUB_FILE" "$OUTPUT_SRT"

        if [ $? -eq 0 ] && [ -f "$OUTPUT_SRT" ]; then
            echo "変換完了: $OUTPUT_SRT"
            rm "$SUB_FILE"
        else
            echo "警告: .srt への変換に失敗したぞ。"
        fi
    fi
done

echo "--- 処理完了 ---"