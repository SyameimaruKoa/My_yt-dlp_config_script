<#
.SYNOPSIS
    'yt-dlp config' (Linux用) を 'win yt-dlp config' (Windows用) に変換するのじゃ。
.DESCRIPTION
    Linux用設定ファイルをWindows用に変換します。
    1. /tmp を %TEMP% に置換
    2. Linux用 --exec (Koa_Discord_Message.sh) をコメントアウト
    3. Windows用 --exec (プレースホルダー %SCRIPT_DIR% を含む行) を
       コメント解除し、パスを $PSScriptRoot に置換
.EXAMPLE
    .\z__convert_config.ps1
.NOTES
    文字コード: UTF-8 BOM で保存
#>
param ()

$ScriptDirectory = $PSScriptRoot
$InputFile = Join-Path $ScriptDirectory "yt-dlp config"
$OutputFile = Join-Path $ScriptDirectory "win yt-dlp config"
$Placeholder = "%SCRIPT_DIR%"
$LinuxExecMarker = "Koa_Discord_Message.sh"

Write-Output "PowerShell 変換ロジック (z__convert_config.ps1) を実行中..."
Write-Output "入力: $InputFile"
Write-Output "出力: $OutputFile"
Write-Output "スクリプト配置場所 (置換パス): $ScriptDirectory"

if (-not (Test-Path $InputFile)) {
    Write-Error "エラー: 入力ファイル '$InputFile' が見つかりません"
    exit 1
}

$OutputLines = [System.Collections.Generic.List[string]]::new()

try {
    Get-Content -Path $InputFile -Encoding Utf8 | ForEach-Object {
        
        if ($_ -like "*$LinuxExecMarker*") {
            # Linux用execをコメントアウト
            Write-Output "Linux用 --exec を無効化..."
            $OutputLines.Add(('# ' + $_))
        }
        elseif ($_ -like "*$Placeholder*") {
            # Windows用プレースホルダー行を有効化・置換
            Write-Output "Windows用 --exec を有効化・パス置換..."
            
            # 1. コメント解除 (行頭の # を削除)
            $UncommentedLine = $_.TrimStart('#')
            
            # 2. プレースホルダーを $ScriptDirectory (絶対パス) に置換
            $FinalExecCommand = $UncommentedLine -replace [regex]::Escape($Placeholder), $ScriptDirectory
            
            $OutputLines.Add($FinalExecCommand)
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