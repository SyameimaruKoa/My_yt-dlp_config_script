@echo off
rem [2025-04-24] ユーザー指示: WindowsバッチはShift-JIS (CP932) で作成
rem ★★★ この .bat ファイル自体は Shift-JIS (ANSI) で保存するんじゃぞ！ ★★★
chcp 932 > nul

setlocal enabledelayedexpansion

rem --- 設定 ---
SET "INPUT_FILE=yt-dlp config"
SET "OUTPUT_FILE=win yt-dlp config"
rem --- 設定ここまで ---

echo yt-dlp config 変換バッチ (PowerShell版) を起動したぞ。
echo 文字化けを直すために、今度は PowerShell の力を使うからの！
echo.
echo 入力: "%INPUT_FILE%" (UTF-8と仮定)
echo 出力: "%OUTPUT_FILE%" (UTF-8で保存)
echo ---

rem 入力ファイルの存在確認
if not exist "%INPUT_FILE%" (
    echo エラー: 入力ファイル "%INPUT_FILE%" が見つからん！
    echo このバッチと同じフォルダに置くんじゃぞ。
    echo.
    pause
    exit /b 1
)

echo 変換処理 (PowerShell) を実行中...

rem --- ここからが本体 ---
rem PowerShell を呼び出し、UTF-8で読み込み(Get-Content)、処理し、UTF-8で書き出す(Set-Content)
rem [2025-09-24] ユーザー指示: PowerShellの活用
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -Path '.\%INPUT_FILE%' -Encoding Utf8 | ForEach-Object { if ($_ -like '--exec *') { 'rem ' + $_ } else { $_ -replace '/tmp', '$env:TEMP' } } | Set-Content -Path '.\%OUTPUT_FILE%' -Encoding Utf8"
rem --- ここまで ---

if !errorlevel! neq 0 (
    echo エラー: PowerShell での変換に失敗したぞ。
    echo PowerShell が実行できない設定（ExecutionPolicy）になっとるかもしれん。
    echo.
    pause
    exit /b 1
)

echo ---
echo 変換完了じゃ！
echo 今度こそ "%OUTPUT_FILE%" の文字化けは無いはずじゃ！
echo (このウィンドウは 5秒後に自動で閉じるぞ...)
timeout /t 5 > nul
exit /b 0