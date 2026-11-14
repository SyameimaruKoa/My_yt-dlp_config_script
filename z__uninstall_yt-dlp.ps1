<#
.SYNOPSIS
    yt-dlpのLinux/Windows共通リポジトリ管理方式からWindows環境をアンインストールする。
.DESCRIPTION
    リポジトリ内venv、起動ラッパー、MPC-BE専用Shim、Deno、字幕変換ツール、
    設定ファイル、歴代セットアップで生成した旧ファイルを整理する。
.EXAMPLE
    .\z__uninstall_yt-dlp.ps1 --dry-run
.EXAMPLE
    .\z__uninstall_yt-dlp.ps1
.EXAMPLE
    .\z__uninstall_yt-dlp.ps1 --remove-repository
.EXAMPLE
    .\z__uninstall_yt-dlp.ps1 --help
.NOTES
    UTF-8 BOM
#>

#region 引数とヘルプ
$DryRun = $false
$RemoveRepository = $false
foreach ($Argument in $args) {
    switch ($Argument.ToLowerInvariant()) {
        { $_ -in @('-h', '--help', '-help') } {
            Get-Help -Detailed $MyInvocation.MyCommand.Path
            exit 0
        }
        '--dry-run' { $DryRun = $true }
        '--remove-repository' { $RemoveRepository = $true }
        default {
            Write-Error "不明な引数: $Argument"
            Get-Help -Detailed $MyInvocation.MyCommand.Path
            exit 2
        }
    }
}
#endregion

#region パス
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Runtime = Join-Path $Root '.runtime\windows'
$OldRoot = Join-Path $env:LOCALAPPDATA 'yt-dlp'
$BinLink = Join-Path $OldRoot 'bin'
$ConfigRoot = Join-Path $env:APPDATA 'yt-dlp'
$ConfigLink = Join-Path $ConfigRoot 'config'
$MpcLink = Join-Path $env:APPDATA 'MPC-BE\yt-dlp'
$LegacyVenv = Join-Path $OldRoot 'venv'
$LegacyUpdater = Join-Path $OldRoot 'auto_update.py'
$LegacyConverter = Join-Path $ConfigRoot 'tools\YTSubConverter\YTSubConverter.exe'
#endregion

#region 削除関数
function Remove-OwnedFile {
    param([string]$Path)
    if ($DryRun) {
        Write-Output "削除予定: $Path"
    }
    else {
        Remove-Item -LiteralPath $Path -Force
        Write-Output "削除完了: $Path"
    }
}

function Remove-OwnedJunction {
    param([string]$Link, [string]$Expected, [string]$Kind)
    $Item = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
    if (-not $Item) {
        return
    }
    if ($Item.LinkType -eq 'Junction') {
        if ([string]$Item.Target -ine $Expected) {
            Write-Output "保持（管理外のジャンクション）: $Link"
            return
        }
        if ($DryRun) {
            Write-Output "ジャンクション削除予定: $Link"
        }
        else {
            [System.IO.Directory]::Delete($Link)
            Write-Output "ジャンクション削除完了: $Link"
        }
        return
    }
    if ($Item.LinkType -or -not $Item.PSIsContainer) {
        Write-Output "保持（管理外のパス）: $Link"
        return
    }
    $Files = @(Get-ChildItem -LiteralPath $Link -Recurse -File -Force)
    $Allowed = if ($Kind -eq 'bin') { @('yt-dlp.cmd') } else { @('yt-dlp.exe', 'yt-dlp.shim') }
    if (@($Files | Where-Object { $_.Name -notin $Allowed }).Count -gt 0) {
        Write-Output "保持（管理外のファイルあり）: $Link"
        return
    }
    if ($Kind -eq 'bin' -and $Files.Count -gt 0) {
        $OldCmd = Join-Path $Link 'yt-dlp.cmd'
        if (-not (Test-Path -LiteralPath $OldCmd) -or -not (Select-String -LiteralPath $OldCmd -SimpleMatch '%LOCALAPPDATA%\yt-dlp\venv\Scripts\python.exe' -Quiet)) {
            Write-Output "保持（管理外の起動スクリプト）: $Link"
            return
        }
    }
    if ($Kind -eq 'mpc' -and $Files.Count -gt 0) {
        $OldShim = Join-Path $Link 'yt-dlp.shim'
        if (-not (Test-Path -LiteralPath $OldShim) -or -not ((Get-Content -LiteralPath $OldShim -Raw) -match '--ignore-config')) {
            Write-Output "保持（管理外のMPC-BEファイル）: $Link"
            return
        }
    }
    if ($DryRun) {
        Write-Output "旧方式ディレクトリ削除予定: $Link"
    }
    else {
        Remove-Item -LiteralPath $Link -Recurse -Force
        Write-Output "旧方式ディレクトリ削除完了: $Link"
    }
}
#endregion

#region 外部リンクと歴代のファイル
Remove-OwnedJunction -Link $BinLink -Expected (Join-Path $Runtime 'bin') -Kind 'bin'
Remove-OwnedJunction -Link $MpcLink -Expected (Join-Path $Runtime 'mpc-be') -Kind 'mpc'

$Config = Get-Item -LiteralPath $ConfigLink -Force -ErrorAction SilentlyContinue
$GeneratedConfig = Join-Path $Root 'win yt-dlp config'
if ($Config) {
    if ($Config.LinkType) {
        if ([string]$Config.Target -ieq $GeneratedConfig) {
            Remove-OwnedFile $ConfigLink
        }
        else {
            Write-Output "保持（管理外の設定リンク）: $ConfigLink"
        }
    }
    elseif ((Test-Path -LiteralPath $GeneratedConfig) -and
        ((Get-FileHash -LiteralPath $ConfigLink -Algorithm SHA256).Hash -eq
         (Get-FileHash -LiteralPath $GeneratedConfig -Algorithm SHA256).Hash)) {
        Remove-OwnedFile $ConfigLink
    }
    else {
        Write-Output "保持（変更済みの設定）: $ConfigLink"
    }
}
if (Test-Path -LiteralPath (Join-Path $LegacyVenv 'pyvenv.cfg')) {
    if ($DryRun) {
        Write-Output "旧venv削除予定: $LegacyVenv"
    }
    else {
        Remove-Item -LiteralPath $LegacyVenv -Recurse -Force
        Write-Output "旧venv削除完了: $LegacyVenv"
    }
}
if ((Test-Path -LiteralPath $LegacyUpdater -PathType Leaf) -and
    (Select-String -LiteralPath $LegacyUpdater -SimpleMatch 'yt-dlp-update.lock' -Quiet)) {
    Remove-OwnedFile $LegacyUpdater
}
if (Test-Path -LiteralPath $LegacyConverter -PathType Leaf) {
    Remove-OwnedFile $LegacyConverter
}
$UserBinPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$Parts = @($UserBinPath -split ';' | Where-Object { $_ -and $_ -ine $BinLink })
if (($UserBinPath -split ';') -icontains $BinLink) {
    if ($DryRun) {
        Write-Output "ユーザーPATH登録削除予定: $BinLink"
    }
    else {
        [Environment]::SetEnvironmentVariable('Path', ($Parts -join ';'), 'User')
        Write-Output "ユーザーPATH登録削除完了: $BinLink"
    }
}
$UserYtsc = [Environment]::GetEnvironmentVariable('YTSC_PATH', 'User')
$ExpectedYtsc = Join-Path $Runtime 'tools\YTSubConverter\YTSubConverter.exe'
if ($UserYtsc -ieq $ExpectedYtsc -or $UserYtsc -ieq $LegacyConverter) {
    if ($DryRun) {
        Write-Output 'YTSC_PATHの解除予定'
    }
    else {
        [Environment]::SetEnvironmentVariable('YTSC_PATH', $null, 'User')
        Write-Output 'YTSC_PATHを解除したぞ。'
    }
}
#endregion

#region リポジトリ内の実体
if (Test-Path -LiteralPath $Runtime -PathType Container) {
    if ($DryRun) {
        Write-Output "リポジトリ内の実行環境削除予定: $Runtime"
    }
    else {
        Remove-Item -LiteralPath $Runtime -Recurse -Force
        Write-Output "リポジトリ内の実行環境削除完了: $Runtime"
    }
}
if ($RemoveRepository) {
    $Origin = & git -C $Root remote get-url origin 2>$null
    $Dirty = & git -C $Root status --porcelain --untracked-files=all 2>$null
    if (($LASTEXITCODE -ne 0) -or $Dirty -or
        $Origin -notin @('https://github.com/SyameimaruKoa/My_yt-dlp_config_script.git', 'git@github.com:SyameimaruKoa/My_yt-dlp_config_script.git')) {
        Write-Output "リポジトリ保持（管理外またはローカル変更あり）: $Root"
    }
    elseif ($DryRun) {
        Write-Output "リポジトリ削除予定: $Root"
    }
    else {
        Remove-Item -LiteralPath $Root -Recurse -Force
        Write-Output "リポジトリ削除完了: $Root"
    }
}
Write-Output 'アンインストール処理が完了したぞ。'
#endregion
