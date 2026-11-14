<#
.SYNOPSIS
    MPC-BE用yt-dlp ShimをWindows実行ファイルとしてビルドする。
.DESCRIPTION
    PowerShell 7から起動された場合はWindows PowerShell 5.1にビルドを委譲する。
    追加の.NET SDKやwingetを導入せずにConsoleApplicationを作成する。
.PARAMETER Source
    ビルドするC#ソースファイル。
.PARAMETER Output
    生成する実行ファイルのパス。
.EXAMPLE
    .\tools\build_mpc_be_shim.ps1 -Source .\tools\mpc_be_yt_dlp_shim.cs -Output .\shim.exe
.EXAMPLE
    .\tools\build_mpc_be_shim.ps1 --help
.NOTES
    文字コード: UTF-8 BOM
#>

#region ヘルプと引数
if ($args.Count -eq 1 -and $args[0] -in @('-h', '--help', '-Help')) {
    Get-Help -Detailed $MyInvocation.MyCommand.Path
    exit 0
}
if ($args.Count -ne 4 -or $args[0] -ne '-Source' -or $args[2] -ne '-Output') {
    Get-Help -Detailed $MyInvocation.MyCommand.Path
    exit 2
}
$SourceFile = [string]$args[1]
$OutputFile = [string]$args[3]
$ErrorActionPreference = 'Stop'
#endregion

#region 入出力の確認
if (-not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) {
    throw "MPC-BE Shimソースが見つからん: $SourceFile"
}
$SourceFile = (Resolve-Path -LiteralPath $SourceFile).Path
$OutputFile = [System.IO.Path]::GetFullPath($OutputFile)
$OutputDirectory = Split-Path -Parent $OutputFile
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
#endregion

#region C#コンソールアプリのビルド
if ($PSVersionTable.PSEdition -eq 'Core') {
    $SystemRoot = [Environment]::GetEnvironmentVariable('SystemRoot')
    $WindowsPowerShell = Join-Path $SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $WindowsPowerShell -PathType Leaf)) {
        throw "Windows PowerShell 5.1が見つからん: $WindowsPowerShell"
    }
    & $WindowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Source $SourceFile -Output $OutputFile
    if ($LASTEXITCODE -ne 0) {
        throw "Windows PowerShell 5.1でのMPC-BE Shimビルドに失敗したぞ（終了コード: $LASTEXITCODE）。"
    }
}
else {
    Add-Type -Path $SourceFile -OutputAssembly $OutputFile -OutputType ConsoleApplication -ErrorAction Stop
}
if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
    throw "MPC-BE Shimの実行ファイルが生成されておらん: $OutputFile"
}
Write-Output "MPC-BE Shimビルド完了: $OutputFile"
#endregion
