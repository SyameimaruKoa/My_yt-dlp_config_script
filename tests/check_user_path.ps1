<#
.SYNOPSIS
    WindowsユーザーPATHを破損させないことを検証する。
.DESCRIPTION
    setup_yt-dlp.ps1のPATH更新処理を実際に呼び出し、元のエントリ維持と二重登録防止、
    System.Object[]を含む破損PATHへの上書き拒否を確認する。
.EXAMPLE
    .\tests\check_user_path.ps1
.EXAMPLE
    .\tests\check_user_path.ps1 --help
#>
#region 引数
if ($args.Count -eq 1 -and $args[0] -in @('-h', '--help', '-Help')) {
    Get-Help -Detailed $MyInvocation.MyCommand.Path
    exit 0
}
if ($args.Count -ne 0) {
    Get-Help -Detailed $MyInvocation.MyCommand.Path
    exit 2
}
$ErrorActionPreference = 'Stop'
#endregion

#region PATH更新処理の抽出
$Setup = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\setup_yt-dlp.ps1') -Raw -Encoding UTF8
$Start = $Setup.IndexOf('$UserPath = [Environment]::GetEnvironmentVariable(')
$End = $Setup.IndexOf('Write-Output "起動リンク:', $Start)
if ($Start -lt 0 -or $End -le $Start) {
    throw 'PATH更新処理が見つからん。'
}
$UpdateCode = $Setup.Substring($Start, $End - $Start)
#endregion

#region レジストリPATHを退避して動作検証
$OriginalUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$OriginalProcessPath = $env:Path
$BinDir = 'C:\CI\yt-dlp\bin'
try {
    $Expected = "$BinDir;C:\Original\one;C:\Original\two"
    [Environment]::SetEnvironmentVariable('Path', 'C:\Original\one;C:\Original\two', 'User')
    Invoke-Expression $UpdateCode
    if ([Environment]::GetEnvironmentVariable('Path', 'User') -cne $Expected) {
        throw '既存PATHが保持されなかった。'
    }
    Invoke-Expression $UpdateCode
    if ([Environment]::GetEnvironmentVariable('Path', 'User') -cne $Expected) {
        throw 'PATHに重複追加された。'
    }
    $Damaged = 'C:\Original\one;System.Object[];C:\Original\two'
    [Environment]::SetEnvironmentVariable('Path', $Damaged, 'User')
    $Blocked = $false
    try {
        Invoke-Expression $UpdateCode
    }
    catch {
        $Blocked = $true
    }
    if (-not $Blocked -or [Environment]::GetEnvironmentVariable('Path', 'User') -cne $Damaged) {
        throw '破損したPATHの上書きを拒否できなかった。'
    }
    Write-Output 'ユーザーPATH保持・重複防止・破損検知のテスト成功'
}
finally {
    [Environment]::SetEnvironmentVariable('Path', $OriginalUserPath, 'User')
    $env:Path = $OriginalProcessPath
}
#endregion
