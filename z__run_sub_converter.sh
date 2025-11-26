#!/bin/bash
#
# yt-dlp から呼び出される字幕変換スクリプト (Wine版・高信頼性コピー)
#
# 使用法: z__run_sub_converter.sh "動画ファイルのパス"
#

# --- ヘルプ表示 ---
show_help() {
    cat << EOF
使用法: $(basename "$0") [動画ファイルのパス]
       $(basename "$0") -h | --help

.srv3 字幕ファイルを検出し、一時ディレクトリ(/tmp)で変換を行ってからNASに書き戻すのじゃ。
  - 安全のため mv ではなく cp を使用
  - 詳細なログを表示

オプション:
  -h, --help    このヘルプを表示
EOF
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_help
    exit 0
fi

# エラー発生時に即停止せず、個別にハンドリングする
set +e

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
echo "--- 字幕変換処理 (高信頼性モード) ---"
echo "対象動画: $VIDEO_BASENAME"
echo "保存先(NAS): $VIDEO_DIR"
echo "作業場所: $WORK_DIR"

# 終了時に一時ディレクトリを削除するトラップ
cleanup() {
    rm -rf "$WORK_DIR"
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
    if ! cp "$SUB_FILE_FULLPATH" "$WORK_DIR/"; then
        echo "  -> エラー: 作業フォルダへのコピーに失敗した。"
        continue
    fi
    
    # 2. 一時ディレクトリに移動して作業
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
                # Wine実行 (ログをファイルに吐かせて、エラー時のみ表示)
                if wine "$EXE_PATH" "$SUB_FILENAME" "$OUTPUT_ASS" > wine_log.txt 2>&1; then
                    # Wineの終了コードが0でもファイルが出来てない場合がある
                    if [ -f "$OUTPUT_ASS" ] && [ -s "$OUTPUT_ASS" ]; then
                        # 3. 成功したらNASに【コピー】する (mvよりcpが安全)
                        echo "  -> 生成成功。NASへ転送中..."
                        if cp -f "$OUTPUT_ASS" "$VIDEO_DIR/"; then
                            echo "  -> 転送完了: $OUTPUT_ASS"
                            
                            # 4. 転送成功を確認してから元のファイルを削除
                            if [ -f "$VIDEO_DIR/$OUTPUT_ASS" ]; then
                                rm -f "$SUB_FILE_FULLPATH"
                                echo "  -> 元ファイル(.srv3)を削除したぞ。"
                            else
                                echo "  -> 警告: 転送したはずのファイルがNASに見当たらん！元ファイルは残しておくぞ。"
                            fi
                        else
                            echo "  -> エラー: NASへの書き込み(cp)に失敗した。"
                        fi
                    else
                        echo "  -> 警告: 変換コマンドは走ったが、出力ファイルが無いか空じゃ。"
                        echo "  --- Wine Log ---"
                        cat wine_log.txt
                        echo "  ----------------"
                    fi
                else
                    echo "  -> エラー: Wineの実行に失敗した。"
                    cat wine_log.txt
                fi
            else
                echo "  -> エラー: Wine環境がないためスキップ。"
            fi

        else
            echo "  [シンプル] -> .srt に変換 (Python)"
            OUTPUT_SRT="${SUB_FILENAME%.*}.srt"

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
                 if cp -f "$OUTPUT_SRT" "$VIDEO_DIR/"; then
                    echo "  -> 転送完了: $OUTPUT_SRT"
                    rm -f "$SUB_FILE_FULLPATH"
                else
                    echo "  -> エラー: NASへの書き込み(cp)に失敗した。"
                fi
            else
                echo "  -> 警告: .srt への変換に失敗したぞ。"
            fi
        fi
    )
done

echo "--- 処理完了 ---"