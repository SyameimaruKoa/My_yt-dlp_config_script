<#
.SYNOPSIS
    yt-dlpのLinux/Windows共通リポジトリ管理方式からWindows環境をアンインストールする。
.DESCRIPTION
    既定では現行・旧方式の実行環境、起動リンク、設定、Gistクローンを削除し、
    Git作業ツリーもローカル変更・未送信コミットに関係なく削除する。
    --cleanup-onlyで旧方式のみ整理し、現行の仮想環境・設定・リンクを維持する。
    --dry-runですべての判定を表示し、削除は行わない。
.EXAMPLE
    .\uninstall_yt-dlp.ps1 --dry-run
.EXAMPLE
    .\uninstall_yt-dlp.ps1
.EXAMPLE
    .\uninstall_yt-dlp.ps1 --cleanup-only
.EXAMPLE
    .\uninstall_yt-dlp.ps1 --keep-repository
.EXAMPLE
    .\uninstall_yt-dlp.ps1 --help
.NOTES
    UTF-8 BOM
#>

#region 引数とヘルプ
$DryRun = $false
$RemoveRepository = $true
$CleanupOnly = $false
foreach ($Argument in $args) {
    switch ($Argument.ToLowerInvariant()) {
        { $_ -in @('-h', '--help', '-help') } {
            Get-Help -Detailed $MyInvocation.MyCommand.Path
            exit 0
        }
        '--dry-run' { $DryRun = $true }
        '--cleanup-only' { $CleanupOnly = $true }
        '--remove-repository' { $RemoveRepository = $true }
        '--keep-repository' { $RemoveRepository = $false }
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
$LegacyCleanup = Join-Path $Root 'tools\migration\cleanup-legacy.ps1'
if (-not (Test-Path -LiteralPath $LegacyCleanup -PathType Leaf)) {
    throw "旧方式の整理スクリプトが見つからん: $LegacyCleanup"
}
if ($CleanupOnly) {
    if (-not (Test-Path -LiteralPath (Join-Path $Runtime 'venv\Scripts\python.exe') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $Runtime 'bin\yt-dlp.cmd') -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ConfigLink -PathType Leaf)) {
        throw '現行方式のセットアップが未完了じゃ。setup_yt-dlp.ps1を実行してから--cleanup-onlyを使うのじゃ。'
    }
    if ($DryRun) {
        & $LegacyCleanup --dry-run
    }
    else {
        & $LegacyCleanup
    }
    if (-not $?) {
        throw '旧方式の整理に失敗したぞ。'
    }
    Write-Output '旧方式だけ整理したぞ。現行のvenv・起動リンク・設定・Gitリポジトリは保持した。'
    return
}
if ($DryRun) {
    & $LegacyCleanup --dry-run
}
else {
    & $LegacyCleanup
}
if (-not $?) {
    throw '旧方式の整理に失敗したぞ。'
}
#endregion

#region 削除関数
function Remove-OwnedFile {
    param([string]$Path)
    if ($DryRun) {
        Write-Output "削除予定: $Path"
    }
    else {
        $Item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($Item -and $Item.LinkType -eq 'SymbolicLink') {
            [System.IO.File]::Delete($Path)
        }
        else {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
        Write-Output "削除完了: $Path"
    }
}

function Remove-OwnedJunction {
    param([string]$Link, [string]$Expected, [string]$Kind)
    $Item = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
    if (-not $Item) {
        Write-Output "対象なし: $Link"
        return
    }
    if ($DryRun) {
        Write-Output "起動先削除予定（内容や変更の有無に関係なく）: $Link"
        return
    }
    if ($Item.LinkType -eq 'Junction' -or ($Item.LinkType -eq 'SymbolicLink' -and $Item.PSIsContainer)) {
        [System.IO.Directory]::Delete($Link)
    }
    elseif ($Item.LinkType -eq 'SymbolicLink') {
        [System.IO.File]::Delete($Link)
    }
    else {
        Remove-Item -LiteralPath $Link -Recurse -Force -ErrorAction Stop
    }
    Write-Output "起動先削除完了: $Link"
}
#endregion

#region 外部リンクと歴代のファイル
Remove-OwnedJunction -Link $BinLink -Expected (Join-Path $Runtime 'bin') -Kind 'bin'
Remove-OwnedJunction -Link $MpcLink -Expected (Join-Path $Runtime 'mpc-be') -Kind 'mpc'

$Config = Get-Item -LiteralPath $ConfigLink -Force -ErrorAction SilentlyContinue
if ($Config) {
    if ($DryRun) {
        Write-Output "設定削除予定（変更の有無に関係なく）: $ConfigLink"
    }
    elseif ($Config.PSIsContainer -and -not $Config.LinkType) {
        Remove-Item -LiteralPath $ConfigLink -Recurse -Force -ErrorAction Stop
        Write-Output "設定削除完了: $ConfigLink"
    }
    else {
        Remove-OwnedFile $ConfigLink
    }
}
else {
    Write-Output "対象なし（設定）: $ConfigLink"
}
$PreserveRuntime = $false
if (Test-Path -LiteralPath (Join-Path $LegacyVenv 'pyvenv.cfg')) {
    if ($DryRun) {
        Write-Output "旧venv削除予定: $LegacyVenv"
    }
    else {
        Remove-Item -LiteralPath $LegacyVenv -Recurse -Force
        Write-Output "旧venv削除完了: $LegacyVenv"
    }
}
elseif (Test-Path -LiteralPath $LegacyVenv) {
    Write-Output "保持（yt-dlp用venvと判定できず）: $LegacyVenv"
}
else {
    Write-Output "対象なし（旧venv）: $LegacyVenv"
}
if ((Test-Path -LiteralPath $LegacyUpdater -PathType Leaf) -and
    (Select-String -LiteralPath $LegacyUpdater -SimpleMatch 'yt-dlp-update.lock' -Quiet)) {
    Remove-OwnedFile $LegacyUpdater
}
elseif (Test-Path -LiteralPath $LegacyUpdater) {
    Write-Output "保持（旧更新スクリプトと判定できず）: $LegacyUpdater"
}
else {
    Write-Output "対象なし（旧更新スクリプト）: $LegacyUpdater"
}
if (Test-Path -LiteralPath $LegacyConverter -PathType Leaf) {
    Remove-OwnedFile $LegacyConverter
}
else {
    Write-Output "対象なし（旧字幕変換ツール）: $LegacyConverter"
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
else {
    Write-Output "対象なし（ユーザーPATH登録）: $BinLink"
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
elseif ($UserYtsc) {
    Write-Output "保持（管理外のYTSC_PATH）: $UserYtsc"
}
else {
    Write-Output '対象なし（YTSC_PATH環境変数）'
}
#endregion

#region リポジトリ内の実体
$GeneratedConfig = Join-Path $Root 'win yt-dlp config'
if (Test-Path -LiteralPath $GeneratedConfig -PathType Leaf) {
    Remove-OwnedFile $GeneratedConfig
}
else {
    Write-Output "対象なし（生成設定ファイル）: $GeneratedConfig"
}
if (Test-Path -LiteralPath $Runtime -PathType Container) {
    if ($PreserveRuntime) {
        Write-Output "保持（未復元の旧設定バックアップがある）: $Runtime"
    }
    elseif ($DryRun) {
        Write-Output "リポジトリ内の実行環境削除予定: $Runtime"
    }
    else {
        Remove-Item -LiteralPath $Runtime -Recurse -Force
        Write-Output "リポジトリ内の実行環境削除完了: $Runtime"
    }
}
else {
    Write-Output "対象なし（リポジトリ内実行環境）: $Runtime"
}
if (-not $DryRun) {
    foreach ($Folder in @(
        (Join-Path $ConfigRoot 'tools\YTSubConverter'),
        (Join-Path $ConfigRoot 'tools'),
        $ConfigRoot,
        $OldRoot
    )) {
        if ((Test-Path -LiteralPath $Folder -PathType Container) -and
            @(Get-ChildItem -LiteralPath $Folder -Force).Count -eq 0) {
            [System.IO.Directory]::Delete($Folder)
            Write-Output "空の旧フォルダ削除: $Folder"
        }
    }
}
if ($RemoveRepository) {
    if ($DryRun) {
        Write-Output "現行リポジトリ全削除予定（編集・未送信コミットを含む）: $Root"
    }
    else {
        $CurrentLocation = (Get-Location).ProviderPath
        $NormalizedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
        if ($CurrentLocation -ieq $NormalizedRoot -or
            $CurrentLocation.StartsWith($NormalizedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            Set-Location -LiteralPath ([System.IO.Path]::GetTempPath())
        }
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop
        Write-Output "現行リポジトリ全削除完了: $Root"
    }
}
else {
    Write-Output "リポジトリ保持（--keep-repository指定）: $Root"
}
#region 残存するコマンドの検出
Write-Output '--- PATH上のyt-dlpを確認 ---'
$DetectedCommands = @(
    Get-Command -Name 'yt-dlp', 'yt-dlp.exe', 'yt-dlp.cmd' -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' -or $_.CommandType -eq 'ExternalScript' } |
        Select-Object -ExpandProperty Source -Unique
)
if ($DetectedCommands.Count -eq 0) {
    Write-Output 'PATH上にyt-dlpは見つからなかったぞ。'
}
else {
    foreach ($CommandPath in $DetectedCommands) {
        if (Test-Path -LiteralPath $CommandPath -PathType Leaf) {
            Write-Output "PATH上に残るyt-dlp（管理対象外の可能性）: $CommandPath"
        }
        else {
            Write-Output "PATH登録が残っているがファイルは存在しない: $CommandPath"
        }
    }
}
$LikelyStandalone = @(
    (Join-Path $env:LOCALAPPDATA 'yt-dlp\yt-dlp.exe'),
    (Join-Path $env:LOCALAPPDATA 'yt-dlp\bin\yt-dlp.exe'),
    (Join-Path $env:APPDATA 'MPC-BE\yt-dlp\yt-dlp.exe')
)
foreach ($Candidate in $LikelyStandalone) {
    if ((Test-Path -LiteralPath $Candidate -PathType Leaf) -and
        $Candidate -notin $DetectedCommands) {
        Write-Output "個別確認が必要なyt-dlp実行ファイル: $Candidate"
    }
}
#endregion

Write-Output '完全アンインストール処理が完了したぞ。保持と表示された項目は削除しておらぬ。'
#endregion
