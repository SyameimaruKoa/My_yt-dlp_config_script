<#
.SYNOPSIS
    'yt-dlp config' (Linux用) を 'win yt-dlp config' (Windows用) に変換するのじゃ。
.DESCRIPTION
    Linux用設定ファイルをWindows用に変換します。
    1. /tmp を %TEMP% に置換
    2. Linux用 --exec をコメントアウト
    3. Windows用 --exec (after_move) を挿入
.EXAMPLE
    .\z__convert_config.ps1
.NOTES
    文字コード: UTF-8 BOM で保存
#>
param ()

$ScriptDirectory = $PSScriptRoot
$InputFile = Join-Path $ScriptDirectory "yt-dlp config"
$OutputFile = Join-Path $ScriptDirectory "win yt-dlp config"
$WindowsExecScript = "run_sub_converter.ps1"

Write-Output "PowerShell 変換ロジック (z__convert_config.ps1) を実行中..."
Write-Output "入力: $InputFile"
Write-Output "出力: $OutputFile"

if (-not (Test-Path $InputFile)) {
    Write-Error "エラー: 入力ファイル '$InputFile' が見つかりません"
    exit 1
}

$OutputLines = [System.Collections.Generic.List[string]]::new()

try {
    Get-Content -Path $InputFile -Encoding Utf8 | ForEach-Object {
        if ($_ -like '--exec *Koa_Discord_Message.sh*') {
            # Linux用execをWindows用に差し替え
            $OutputLines.Add('# --- (元) Linux用Discord通知 (無効化) ---')
            $OutputLines.Add(('# ' + $_))
            $OutputLines.Add('# === (新) Windows用 字幕変換 (after_move使用) ===')
            
            $ExecScriptPath = Join-Path $ScriptDirectory $WindowsExecScript
            
            # after_moveで動画ファイルパスを渡して字幕変換を実行
            $ExecCommand = '--exec after_move:"powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"{0}\" \"%(filepath)s\""' -f $ExecScriptPath
            
            $OutputLines.Add($ExecCommand)
        }
        else {
            # /tmp を %TEMP% に置換
            $OutputLines.Add(($_ -replace '/tmp', '%TEMP%'))
        }
    }

    Set-Content -Path $OutputFile -Value $OutputLines -Encoding Utf8 -ErrorAction Stop

    Write-Output "--------------------"
    Write-Output "変換完了！"
    Write-Output "'$OutputFile' が正常に生成されました。"

}
catch {
    Write-Error "エラー: 変換または出力ファイル ($OutputFile) への書き込みに失敗"
    Write-Error $_
    exit 1
}
