<#
.SYNOPSIS
    Windowsの旧yt-dlp構成とGistクローンを整理する。
.DESCRIPTION
    Linux由来の旧Gistクローン、以前のWindows用venv・更新スクリプト・字幕変換ツールを
    検出して整理する。現行の.runtime/windowsと現行ジャンクションには手を触れない。
.PARAMETER DryRun
    検出結果と削除予定だけを表示する。
.EXAMPLE
    .\tools\migration\cleanup-legacy.ps1 --dry-run
.EXAMPLE
    .\tools\migration\cleanup-legacy.ps1
.EXAMPLE
    .\tools\migration\cleanup-legacy.ps1 --help
#>
#region 引数とパス
$DryRun = $false
foreach ($Argument in $args) {
    switch ($Argument.ToLowerInvariant()) {
        { $_ -in @('-h', '--help', '-help') } {
            Get-Help -Detailed $MyInvocation.MyCommand.Path
            exit 0
        }
        '--dry-run' { $DryRun = $true }
        default {
            throw "不明な引数: $Argument"
        }
    }
}
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$GistId = '21141912fbacf40877f4cf877577e082'
$GistHome = Join-Path $HOME $GistId
$OldRoot = Join-Path $env:LOCALAPPDATA 'yt-dlp'
$OldVenv = Join-Path $OldRoot 'venv'
$OldUpdater = Join-Path $OldRoot 'auto_update.py'
$OldConfig = Join-Path $env:APPDATA 'yt-dlp\config'
$OldConverterDir = Join-Path $env:APPDATA 'yt-dlp\tools\YTSubConverter'
$OldBin = Join-Path $OldRoot 'bin'
$OldMpc = Join-Path $env:APPDATA 'MPC-BE\yt-dlp'
#endregion

#region 共通の削除と判定
function Remove-LegacyPath {
    param([string]$Path, [string]$Reason)
    if ($DryRun) {
        Write-Output "削除予定（$Reason）: $Path"
    }
    else {
        $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($Item.LinkType -eq 'Junction' -or ($Item.LinkType -eq 'SymbolicLink' -and $Item.PSIsContainer)) {
            [System.IO.Directory]::Delete($Path)
        }
        elseif ($Item.LinkType -eq 'SymbolicLink') {
            [System.IO.File]::Delete($Path)
        }
        else {
            Remove-Item -LiteralPath $Path -Recurse -Force
        }
        Write-Output "削除完了（$Reason）: $Path"
    }
}

function Test-PlainDirectory {
    param([string]$Path)
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return ($null -ne $Item -and $Item.PSIsContainer -and -not $Item.LinkType)
}

function Invoke-LegacyGit {
    param([string]$Directory, [string[]]$Arguments)
    $PriorErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $Lines = @()
    $ExitCode = 1
    try {
        $Lines = @(& git -C $Directory @Arguments 2>$null)
        $ExitCode = $LASTEXITCODE
    }
    catch {
        $Lines = @()
    }
    finally {
        $ErrorActionPreference = $PriorErrorAction
    }
    return [pscustomobject]@{ Lines = $Lines; ExitCode = $ExitCode }
}

function Remove-EmptyLegacyParents {
    param([string[]]$Paths)
    if ($DryRun) { return }
    foreach ($Path in $Paths) {
        if ((Test-PlainDirectory $Path) -and
            @(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0) {
            [System.IO.Directory]::Delete($Path)
            Write-Output "空の旧フォルダ削除: $Path"
        }
    }
}
#endregion

#region 旧Gistの設定リンク
$GistCandidates = @($GistHome)
$OtherGist = @(
    (Join-Path $env:LOCALAPPDATA "yt-dlp\$GistId"),
    (Join-Path $env:APPDATA "yt-dlp\$GistId")
)
foreach ($Candidate in $OtherGist) {
    if ($GistCandidates -notcontains $Candidate) {
        $GistCandidates += $Candidate
    }
}
$CurrentConfig = Join-Path $Root 'win yt-dlp config'
$ConfigItem = Get-Item -LiteralPath $OldConfig -Force -ErrorAction SilentlyContinue
if ($ConfigItem -and $ConfigItem.LinkType -eq 'SymbolicLink') {
    $Target = [string]$ConfigItem.Target
    foreach ($GistDir in $GistCandidates) {
        if ($Target -ieq (Join-Path $GistDir 'win yt-dlp config') -or
            $Target -ieq (Join-Path $GistDir 'yt-dlp config')) {
            Remove-LegacyPath $OldConfig '旧Gist設定リンク'
            break
        }
    }
}
#endregion

#region 以前のWindows専用ファイル
if ((Test-PlainDirectory $OldVenv) -and
    (Test-Path -LiteralPath (Join-Path $OldVenv 'pyvenv.cfg') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $OldVenv 'Scripts\yt-dlp.exe') -PathType Leaf)) {
    Remove-LegacyPath $OldVenv '旧yt-dlp venv'
}
elseif (Test-Path -LiteralPath $OldVenv) {
    Write-Output "保持（旧yt-dlp venvと確認できず）: $OldVenv"
}
else {
    Write-Output "対象なし（旧yt-dlp venv）: $OldVenv"
}
if ((Test-Path -LiteralPath $OldUpdater -PathType Leaf) -and
    ((Get-Content -LiteralPath $OldUpdater -Raw -ErrorAction SilentlyContinue) -match 'yt-dlp-update.lock')) {
    Remove-LegacyPath $OldUpdater '旧更新スクリプト'
}
elseif (Test-Path -LiteralPath $OldUpdater) {
    Write-Output "保持（旧更新スクリプトと確認できず）: $OldUpdater"
}
else {
    Write-Output "対象なし（旧更新スクリプト）: $OldUpdater"
}
$OldConverter = Join-Path $OldConverterDir 'YTSubConverter.exe'
if ((Test-PlainDirectory $OldConverterDir) -and (Test-Path -LiteralPath $OldConverter -PathType Leaf)) {
    Remove-LegacyPath $OldConverter '旧字幕変換ツール'
}
elseif (Test-Path -LiteralPath $OldConverterDir) {
    Write-Output "保持（旧字幕変換フォルダの内容を確認）: $OldConverterDir"
}
else {
    Write-Output "対象なし（旧字幕変換ツール）: $OldConverter"
}
if (Test-PlainDirectory $OldBin) {
    $Entries = @(Get-ChildItem -LiteralPath $OldBin -Force)
    $Launcher = Join-Path $OldBin 'yt-dlp.cmd'
    if ($Entries.Count -eq 1 -and $Entries[0].Name -eq 'yt-dlp.cmd' -and
        -not $Entries[0].LinkType -and
        (Select-String -LiteralPath $Launcher -SimpleMatch '%LOCALAPPDATA%\yt-dlp\venv\Scripts\python.exe' -Quiet)) {
        Remove-LegacyPath $OldBin '旧yt-dlpコマンド'
    }
    else {
        Write-Output "保持（現行リンクまたは管理外の起動ファイル）: $OldBin"
    }
}
elseif (Test-Path -LiteralPath $OldBin) {
    Write-Output "保持（現行リンクまたは管理外の起動先）: $OldBin"
}
else {
    Write-Output "対象なし（旧起動フォルダ）: $OldBin"
}
if (Test-PlainDirectory $OldMpc) {
    $Entries = @(Get-ChildItem -LiteralPath $OldMpc -Force)
    $Shim = Join-Path $OldMpc 'yt-dlp.shim'
    if ($Entries.Count -gt 0 -and
        @($Entries | Where-Object { $_.PSIsContainer -or $_.LinkType -or $_.Name -notin @('yt-dlp.exe', 'yt-dlp.shim') }).Count -eq 0 -and
        (Test-Path -LiteralPath $Shim -PathType Leaf) -and
        ((Get-Content -LiteralPath $Shim -Raw) -match '--ignore-config')) {
        Remove-LegacyPath $OldMpc '旧MPC-BE Shim'
    }
    else {
        Write-Output "保持（管理外のMPC-BEファイル）: $OldMpc"
    }
}
elseif (Test-Path -LiteralPath $OldMpc) {
    Write-Output "保持（現行MPC-BEリンク）: $OldMpc"
}
else {
    Write-Output "対象なし（旧MPC-BE Shim）: $OldMpc"
}
#endregion

#region Gist本体（Gitクローンは取得元・変更・未送信コミットを確認）
foreach ($GistDir in $GistCandidates) {
    if (-not (Test-Path -LiteralPath $GistDir) -and
        -not (Get-Item -LiteralPath $GistDir -Force -ErrorAction SilentlyContinue)) {
        Write-Output "対象なし（旧Gist）: $GistDir"
        continue
    }
    if (-not (Test-PlainDirectory $GistDir)) {
        Write-Output "旧Gist保持（管理外のリンクまたはファイル）: $GistDir"
        continue
    }
    $GitDir = Join-Path $GistDir '.git'
    if (Test-PlainDirectory $GitDir) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Output "旧Gist保持（gitが見つからない）: $GistDir"
            continue
        }
        $RemoteResult = Invoke-LegacyGit -Directory $GistDir -Arguments @('remote', 'get-url', 'origin')
        $RootResult = Invoke-LegacyGit -Directory $GistDir -Arguments @('rev-parse', '--show-toplevel')
        $Origin = [string]($RemoteResult.Lines | Select-Object -First 1)
        $RootPath = [string]($RootResult.Lines | Select-Object -First 1)
        $AllowedRemotes = @(
            "https://gist.github.com/$GistId.git",
            "https://gist.github.com/$GistId",
            "git@gist.github.com:$GistId.git"
        )
        if ($RemoteResult.ExitCode -ne 0 -or $RootResult.ExitCode -ne 0 -or
            $Origin -notin $AllowedRemotes -or
            [IO.Path]::GetFullPath($RootPath).TrimEnd('\') -ine [IO.Path]::GetFullPath($GistDir).TrimEnd('\')) {
            Write-Output "旧Gist保持（取得元が違う）: $GistDir"
            continue
        }
        $StatusResult = Invoke-LegacyGit -Directory $GistDir -Arguments @('status', '--porcelain', '--ignored', '--untracked-files=all')
        $Status = @($StatusResult.Lines)
        if ($StatusResult.ExitCode -ne 0 -or
            @($Status | Where-Object { $_ -and $_ -ne '!! win yt-dlp config' -and $_ -ne '!! "win yt-dlp config"' }).Count -gt 0) {
            Write-Output "旧Gist保持（編集・追加ファイルあり）: $GistDir"
            continue
        }
        $UpstreamResult = Invoke-LegacyGit -Directory $GistDir -Arguments @('rev-parse', '--verify', '@{upstream}')
        if ($UpstreamResult.ExitCode -ne 0) {
            Write-Output "旧Gist保持（追跡先不明）: $GistDir"
            continue
        }
        $AheadResult = Invoke-LegacyGit -Directory $GistDir -Arguments @('rev-list', '--count', '@{upstream}..HEAD')
        $Ahead = [string]($AheadResult.Lines | Select-Object -First 1)
        if ($AheadResult.ExitCode -ne 0 -or $Ahead -ne '0') {
            Write-Output "旧Gist保持（未送信コミットあり）: $GistDir"
            continue
        }
        Remove-LegacyPath $GistDir '旧Gistクローン'
    }
    else {
        $Names = @(Get-ChildItem -LiteralPath $GistDir -Force)
        $AllowedNames = @('.gitignore', 'yt-dlp config', 'z__convert_config.ps1',
            'z__run_sub_converter.ps1', 'win yt-dlp config')
        if ((Test-Path -LiteralPath (Join-Path $GistDir 'yt-dlp config') -PathType Leaf) -and
            @($Names | Where-Object { $_.PSIsContainer -or $_.LinkType -or $_.Name -notin $AllowedNames }).Count -eq 0) {
            Remove-LegacyPath $GistDir '旧Gist展開フォルダ'
        }
        else {
            Write-Output "旧Gist保持（取得元や内容を確認できない）: $GistDir"
        }
    }
}
Remove-EmptyLegacyParents @(
    $OldConverterDir,
    (Join-Path $env:APPDATA 'yt-dlp\tools'),
    (Join-Path $env:APPDATA 'yt-dlp'),
    $OldRoot
)
Write-Output '旧方式の整理・検出が完了したぞ。'
#endregion
