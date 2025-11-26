#!/bin/bash
#
# yt-dlp から呼び出される字幕変換スクリプト (Linux版)
#
# 使用法: z__run_sub_converter.sh "動画ファイルのパス"
#

# --- ヘルプ表示 ---
show_help() {
    cat << EOF
使用法: $(basename "$0") [動画ファイルのパス]
       $(basename "$0") -h | --help

.srv3 字幕ファイルを検出し、内容に応じて変換を行うのじゃ。
  - 装飾タグ (<span, <u, <pen) あり -> YTSubConverter で .ass に変換
  - 装飾タグ なし -> シンプルな .srt に変換

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
    show_help
    exit 1
fi

VIDEO_DIR=$(dirname "$VIDEO_PATH")
VIDEO_BASENAME=$(basename "$VIDEO_PATH")
VIDEO_NAME_NOEXT="${VIDEO_BASENAME%.*}"

echo "--- 字幕変換処理 (Linux) ---"
echo "動画: $VIDEO_PATH"

# YTSubConverterの確認
if ! command -v YTSubConverter &> /dev/null; then
    echo "警告: 'YTSubConverter' コマンドが見つからん。パスが通っているか確認せよ。"
    # 続行はする（単純変換は可能なため）
fi

# .srv3 ファイルを探す
# findコマンドでディレクトリ内のsrv3を探し、ベース名が一致するものをフィルタ
find "$VIDEO_DIR" -maxdepth 1 -name "*.srv3" | while read -r SUB_FILE; do
    # 動画ファイル名を含むものだけ対象にする
    if [[ "$SUB_FILE" != *"$VIDEO_NAME_NOEXT"* ]]; then
        continue
    fi

    echo "処理中: $SUB_FILE"
    
    # ファイル内容をチェックして変換方式を決定
    NEEDS_CONVERSION=false
    if grep -q "<span" "$SUB_FILE"; then NEEDS_CONVERSION=true; fi
    if grep -q "<u" "$SUB_FILE"; then NEEDS_CONVERSION=true; fi
    if grep -q "<pen" "$SUB_FILE"; then NEEDS_CONVERSION=true; fi

    if [ "$NEEDS_CONVERSION" = true ]; then
        echo "装飾タグを検出 -> YTSubConverter (.ass) を使用"
        
        OUTPUT_ASS="${SUB_FILE%.*}.ass"
        
        if command -v YTSubConverter &> /dev/null; then
            # YTSubConverter 入力 出力
            YTSubConverter "$SUB_FILE" "$OUTPUT_ASS"
            
            if [ -f "$OUTPUT_ASS" ]; then
                echo "変換完了: $OUTPUT_ASS"
                rm "$SUB_FILE"
            else
                echo "警告: .ass への変換に失敗したようじゃ。"
            fi
        else
            echo "エラー: YTSubConverterが無いので変換できん。"
        fi

    else
        echo "シンプルXML -> .srt に変換 (Python使用)"
        OUTPUT_SRT="${SUB_FILE%.*}.srt"

        # Pythonスクリプトを埋め込んで実行 (XML解析とSRT生成)
        python3 -c '
import sys
import xml.etree.ElementTree as ET
import math

def ms_to_srt_time(ms):
    h = ms // 3600000
    ms %= 3600000
    m = ms // 60000
    ms %= 60000
    s = ms // 1000
    ms %= 1000
    return "{:02d}:{:02d}:{:02d},{:03d}".format(h, m, s, ms)

input_file = sys.argv[1]
output_file = sys.argv[2]

try:
    tree = ET.parse(input_file)
    root = tree.getroot()
    # Namespace除去は手抜きだが、単純なyt-dlpのsrv3ならそのままいけることが多い
    # 必要なら iter でタグ名だけ見る
    
    lines = []
    index = 1
    # body/p タグを探す
    for p in root.findall(".//p"):
        try:
            t = int(p.get("t", 0))
            d = int(p.get("d", 0))
        except:
            continue
            
        text = "".join(p.itertext()).strip()
        if not text: continue
        
        start_time = ms_to_srt_time(t)
        end_time = ms_to_srt_time(t + d)
        
        lines.append(str(index))
        lines.append(f"{start_time} --> {end_time}")
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