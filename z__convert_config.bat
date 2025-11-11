@echo off
rem [2025-04-24] ユーザー指示: WindowsバッチはShift-JIS (CP932) で作成
rem ★★★ ファイルの文字コードを Shift-JIS (ANSI) にして保存するんじゃぞ！ ★★★
chcp 932 > nul

setlocal enabledelayedexpansion

rem --- 設定 ---
SET "INPUT_FILE=yt-dlp config"
SET "OUTPUT_FILE=win yt-dlp config"
rem --- 設定ここまで ---

echo yt-dlp config 変換バッチ (修正版) を起動したぞ。
echo.
echo 入力: "%INPUT_FILE%"
echo 出力: "%OUTPUT_FILE%"
echo ---

rem 入力ファイルの存在確認
if not exist "%INPUT_FILE%" (
    echo エラー: 入力ファイル "%INPUT_FILE%" が見つからんぞ！
    echo このバッチと同じフォルダに置くのじゃ。
    echo.
    pause
    exit /b 1
)

rem 古い出力ファイルがあれば削除
if exist "%OUTPUT_FILE%" (
    echo 古い "%OUTPUT_FILE%" を削除中...
    del "%OUTPUT_FILE%"
)

echo 変換処理を開始する...

rem 1行ずつ読み込んで処理
rem [2025-09-06] Pythonではないが、ループ処理
for /f "usebackq tokens=* delims=" %%L in ("%INPUT_FILE%") do (
    set "line=%%L"
    
    rem デフォルトは「処理しない」フラグ
    set "processed=false"

    rem 【ルール1-B】 --exec で始まる行かチェック (先頭7文字で判定)
    rem findstr は特殊文字に弱いため、安全な文字列比較に変更
    if /I "!line:~0,7!" == "--exec " (
        rem --exec の行は rem を付けて出力
        echo rem !line! >> "%OUTPUT_FILE%"
        set "processed=true"
    )

    rem 【ルール3-A】 /tmp を %TEMP% に置換
    rem (processed=false の場合のみ、つまり --exec 以外の行で実行)
    if "!processed!" == "false" (
        rem (その他のルール 2-B, 4-A は「何もしない」)
        set "line=!line:/tmp=%%TEMP%%!"
        
        rem 変換後の行を出力
        echo !line! >> "%OUTPUT_FILE%"
    )
)

echo ---
echo 変換完了じゃ！ "%OUTPUT_FILE%" を確認せい。
echo 今度こそ問題なかろう！
echo (このウィンドウは 5秒後に自動で閉じるぞ...)
timeout /t 5 > nul
exit /b 0