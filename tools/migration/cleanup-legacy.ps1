<#
.SYNOPSIS
    Windowsの旧yt-dlp構成とGistクローンを整理する。
.DESCRIPTION
    Linux由来の旧Gistクローン、以前のWindows用venv・更新スクリプト・字幕変換ツールを
    既知の旧配置先を変更の有無に関係なく削除する。現行の.runtime/windowsと現行ジャンクションは保持する。
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
if (Test-PlainDirectory $OldVenv) {
    Remove-LegacyPath $OldVenv '旧yt-dlp venv（内容に関係なく削除）'
}
elseif (Get-Item -LiteralPath $OldVenv -Force -ErrorAction SilentlyContinue) {
    Write-Output "保持（管理外のリンク）: $OldVenv"
}
else {
    Write-Output "対象なし（旧yt-dlp venv）: $OldVenv"
}
if (Test-Path -LiteralPath $OldUpdater -PathType Leaf) {
    Remove-LegacyPath $OldUpdater '旧更新スクリプト'
}
else {
    Write-Output "対象なし（旧更新スクリプト）: $OldUpdater"
}
$OldConverter = Join-Path $OldConverterDir 'YTSubConverter.exe'
if (Test-PlainDirectory $OldConverterDir) {
    Remove-LegacyPath $OldConverterDir '旧字幕変換ツール（フォルダ全削除）'
}
else {
    Write-Output "対象なし（旧字幕変換ツール）: $OldConverterDir"
}
if (Test-PlainDirectory $OldBin) {
    Remove-LegacyPath $OldBin '旧yt-dlp起動フォルダ（全削除）'
}
elseif (Get-Item -LiteralPath $OldBin -Force -ErrorAction SilentlyContinue) {
    Write-Output "保持（現行ジャンクション）: $OldBin"
}
else {
    Write-Output "対象なし（旧起動フォルダ）: $OldBin"
}
if (Test-PlainDirectory $OldMpc) {
    Remove-LegacyPath $OldMpc '旧MPC-BE Shim（フォルダ全削除）'
}
elseif (Get-Item -LiteralPath $OldMpc -Force -ErrorAction SilentlyContinue) {
    Write-Output "保持（現行MPC-BEジャンクション）: $OldMpc"
}
else {
    Write-Output "対象なし（旧MPC-BE Shim）: $OldMpc"
}
#endregion

#region Gist本体（指定された旧Gistは変更の有無にかかわらず全削除）
foreach ($GistDir in $GistCandidates) {
    $GistItem = Get-Item -LiteralPath $GistDir -Force -ErrorAction SilentlyContinue
    if (-not $GistItem) {
        Write-Output "対象なし（旧Gist）: $GistDir"
        continue
    }
    Remove-LegacyPath $GistDir '旧Gist（変更・未送信コミットを含め全削除）'
}
#endregion
Remove-EmptyLegacyParents @(
    $OldConverterDir,
    (Join-Path $env:APPDATA 'yt-dlp\tools'),
    (Join-Path $env:APPDATA 'yt-dlp'),
    $OldRoot
)
Write-Output '旧方式の整理・検出が完了したぞ。'
#endregion
