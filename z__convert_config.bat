@echo off
rem [2025-04-24] ユーザー指示: WindowsバッチはShift-JIS (CP932) で作成
chcp 65001 > nul

rem 遅延環境変数の展開を有効にする (文字列置換のため)
setlocal enabledelayedexpansion

rem --- 設定 ---
SET "INPUT_FILE=yt-dlp config"
rem ★ここを変更したぞ★
SET "OUTPUT_FILE=win yt-dlp config"
rem --- 設定ここまで ---

echo yt-dlp config 変換バッチを起動したぞ。
echo 入力: "%INPUT_FILE%"
echo 出力: "%OUTPUT_FILE%"
echo ---

rem 入力ファイルの存在確認
if not exist "%INPUT_FILE%" (
    echo エラー: 入力ファイル "%INPUT_FILE%" が見つからんぞ。 >&2
    echo このバッチファイルと同じフォルダに置くのじゃ。 >&2
    echo ---
    pause
    exit /b 1
)

rem 古い出力ファイルがあれば削除 (ファイル名にスペースがあっても "%OUTPUT_FILE%" で対応)
if exist "%OUTPUT_FILE%" (
    echo 古い "%OUTPUT_FILE%" を削除中...
    del "%OUTPUT_FILE%"
)

echo 変換処理を開始する...

rem 1行ずつ読み込んで処理
rem [2025-09-06] Pythonではないが、ループ処理
for /f "usebackq tokens=* delims=" %%L in ("%INPUT_FILE%") do (
    set "line=%%L"

    rem ルール1-B: --exec で始まる行かチェック
    rem (findstr の /B は行頭, /I は大文字小文字無視)
    echo !line! | findstr /B /I /C:"--exec " > nul
    
    if !errorlevel! equ 0 (
        rem 【ルール1-B】 --exec の行はコメントアウトする
        echo rem !line! >> "%OUTPUT_FILE%"
    ) else (
        rem --exec 以外の行
        
        rem 【ルール3-A】 /tmp を %TEMP% に置換する
        rem (その他のルール 2-B, 4-A は「何もしない」なので処理不要)
        set "line=!line:/tmp=%%TEMP%%!"
        
        rem 変換後の行を出力
        echo !line! >> "%OUTPUT_FILE%"
    )
)

echo ---
echo 変換完了じゃ！ "%OUTPUT_FILE%" を確認せい。
echo このウィンドウは自動で閉じるぞ。
timeout /t 5 > nul
exit /b 0