@echo off
rem [2025-04-24] ユーザー指示: WindowsバッチはShift-JIS (CP932) で作成
rem ★★★ この .bat ファイル自体は Shift-JIS (ANSI) で保存するんじゃぞ！ ★★★
chcp 932 > nul

setlocal enabledelayedexpansion

rem --- 設定 ---
SET "INPUT_FILE=yt-dlp config"
SET "OUTPUT_FILE=win yt-dlp config"
rem --- 設定ここまで ---

echo yt-dlp config 変換バッチ (TEMP修正版) を起動したぞ。
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

rem --- ここからが本体 (★ $env:TEMP を %%TEMP%% に修正したぞ！) ---
rem [2025-09-24] ユーザー指示: PowerShellの活用
rem バッチファイル内で % を % として扱うには %% とエスケープするのじゃ。
rem これで PowerShell には '%TEMP%' という文字列が渡され、
rem 最終的なファイルには -P temp:%TEMP% と書き込まれるぞ。
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -Path '.\%INPUT_FILE%' -Encoding Utf8 | ForEach-Object { if ($_ -like '--exec *') { '# ' + $_ } else { $_ -replace '/tmp', '%%TEMP%%' } } | Set-Content -Path '.\%OUTPUT_FILE%' -Encoding Utf8"
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
echo 今度こそ "%OUTPUT_FILE%" を確認せい。-P temp:%%TEMP%% となっとるはずじゃ！
echo (このウィンドウは 5秒後に自動で閉じるぞ...)
timeout /t 5 > nul
exit /b 0