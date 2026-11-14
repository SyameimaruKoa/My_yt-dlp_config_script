<#
.SYNOPSIS
    Windowsにyt-dlp Nightly、Python仮想環境、依存ツール、設定を導入するのじゃ。
.DESCRIPTION
    %LOCALAPPDATA%\yt-dlp\venv にPython仮想環境を作成し、pipでyt-dlpと追加依存関係を導入する。
    yt-dlp.cmd をユーザーPATHに登録し、仮想環境を手動で有効化せずにyt-dlpを実行できるようにする。
    wingetでffmpeg、aria2、Denoを準備し、YTSubConverterとWindows用設定ファイルも配置する。
.EXAMPLE
    .\setup_yt-dlp.ps1
.EXAMPLE
    .\setup_yt-dlp.ps1 -h
.EXAMPLE
    .\setup_yt-dlp.ps1 --help
.NOTES
    文字コード: UTF-8 BOM
#>

#region ヘルプと引数
if ($args.Count -eq 1 -and $args[0] -in @('-h', '--help', '-Help')) {
    Get-Help -Detailed $MyInvocation.MyCommand.Path
    exit 0
}
if ($args.Count -gt 0) {
    Write-Error "不明な引数じゃ: $($args -join ' ')"
    Get-Help -Detailed $MyInvocation.MyCommand.Path
    exit 1
}
#endregion

#region 初期化
$ErrorActionPreference = 'Stop'
$RuntimeDir = Join-Path $PSScriptRoot '.runtime\windows'
$VenvDir = Join-Path $RuntimeDir 'venv'
$RuntimeBinDir = Join-Path $RuntimeDir 'bin'
$BinDir = Join-Path $env:LOCALAPPDATA 'yt-dlp\bin'
$ConfigDir = Join-Path $env:APPDATA 'yt-dlp'
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
New-Item -ItemType Directory -Path (Split-Path -Parent $BinDir), $RuntimeBinDir, $ConfigDir -Force | Out-Null
Write-Output "リポジトリ内の実体: $RuntimeDir"
#endregion

#region 外部パスをリポジトリ内へ接続
function Set-ManagedJunction {
    param([string]$Link, [string]$Target, [string]$Kind)
    $Existing = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
    if ($Existing -and $Existing.LinkType -eq 'Junction') {
        if ([string]$Existing.Target -ieq $Target) {
            Write-Output "リンク確認済み: $Link -> $Target"
            return
        }
        throw "他のジャンクションは変更しないぞ: $Link"
    }
    if ($Existing) {
        if (-not $Existing.PSIsContainer -or $Existing.LinkType) {
            throw "管理外のリンクまたはファイルは変更しないぞ: $Link"
        }
        $Entries = @(Get-ChildItem -LiteralPath $Link -Force)
        $Expected = if ($Kind -eq 'bin') { @('yt-dlp.cmd') } else { @('yt-dlp.exe', 'yt-dlp.shim') }
        if (@($Entries | Where-Object { $_.PSIsContainer -or $_.LinkType -or $_.Name -notin $Expected }).Count -gt 0) {
            throw "管理外のファイルがあるので保持する: $Link"
        }
        if ($Kind -eq 'bin' -and $Entries.Count -gt 0) {
            if (-not (Select-String -LiteralPath (Join-Path $Link 'yt-dlp.cmd') -SimpleMatch '%LOCALAPPDATA%\yt-dlp\venv\Scripts\python.exe' -Quiet)) {
                throw "管理外の起動スクリプトなので保持する: $Link"
            }
        }
        if ($Kind -eq 'mpc' -and $Entries.Count -gt 0) {
            $OldConfig = Join-Path $Link 'yt-dlp.shim'
            if (-not (Test-Path -LiteralPath $OldConfig) -or -not ((Get-Content -LiteralPath $OldConfig -Raw) -match '--ignore-config')) {
                throw "管理外のMPC-BE用ファイルなので保持する: $Link"
            }
        }
        Remove-Item -LiteralPath $Link -Recurse -Force
    }
    New-Item -ItemType Junction -Path $Link -Target $Target -Force | Out-Null
    Write-Output "リポジトリ内へジャンクション設定: $Link -> $Target"
}

function Set-ManagedConfigLink {
    param([string]$Link, [string]$Target)
    $Existing = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
    if ($Existing -and $Existing.LinkType) {
        if ($Existing.LinkType -eq 'HardLink' -and
            ((Get-FileHash -LiteralPath $Link -Algorithm SHA256).Hash -eq
             (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash)) {
            Write-Output "設定ハードリンク確認済み: $Link"
            return
        }
        if ([string]$Existing.Target -ieq $Target) {
            Write-Output "設定リンク確認済み: $Link"
            return
        }
        throw "管理外の設定リンクは変更しないぞ: $Link"
    }
    if ($Existing) {
        if ($Existing.PSIsContainer) {
            throw "設定パスがディレクトリになっておる: $Link"
        }
        $OldHash = (Get-FileHash -LiteralPath $Link -Algorithm SHA256).Hash
        $NewHash = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash
        if ($OldHash -ne $NewHash) {
            $Backup = Join-Path $RuntimeDir 'legacy-config.backup'
            if (Test-Path -LiteralPath $Backup) {
                throw "既存の設定バックアップがあるため上書きしない: $Backup"
            }
            Move-Item -LiteralPath $Link -Destination $Backup
            Write-Output "以前の設定を退避: $Backup"
        }
        else {
            Remove-Item -LiteralPath $Link -Force
        }
    }
    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -Force -ErrorAction Stop | Out-Null
        Write-Output "設定をシンボリックリンク化: $Link -> $Target"
    }
    catch {
        New-Item -ItemType HardLink -Path $Link -Target $Target -ErrorAction Stop | Out-Null
        Write-Output "設定をハードリンク化: $Link -> $Target"
    }
}
#endregion

#region Python仮想環境
$PythonCommand = $null
$PythonPrefix = @()
$Candidates = @(
    @{ Command = 'py'; Prefix = @('-3') },
    @{ Command = 'python'; Prefix = @() }
)
foreach ($Candidate in $Candidates) {
    if (-not (Get-Command $Candidate.Command -ErrorAction SilentlyContinue)) {
        continue
    }
    $Exe = $Candidate.Command
    $Prefix = @($Candidate.Prefix)
    try {
        & $Exe @Prefix -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $PythonCommand = $Exe
            $PythonPrefix = $Prefix
            break
        }
    }
    catch {
        continue
    }
}
if (-not $PythonCommand) {
    throw 'Python 3.11以上が見つからん。Pythonをインストールするのじゃ。'
}
if (-not (Test-Path -LiteralPath $VenvPython)) {
    Write-Output "仮想環境を作成中: $VenvDir"
    & $PythonCommand @PythonPrefix -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) {
        throw 'Python仮想環境の作成に失敗したぞ。'
    }
}
Write-Output 'yt-dlp Nightlyと追加pip依存関係をインストール中...'
& $VenvPython -m pip install --upgrade --upgrade-strategy eager --pre 'yt-dlp[default,curl-cffi]'
if ($LASTEXITCODE -ne 0) {
    throw 'yt-dlpのpipインストールに失敗したぞ。'
}
#endregion

#region PATHとyt-dlpコマンド
$UpdaterSource = Join-Path $PSScriptRoot 'tools\yt_dlp_auto_update.py'
$UpdaterTarget = $UpdaterSource
if (-not (Test-Path -LiteralPath $UpdaterSource)) {
    throw '起動時の自動更新スクリプトが見つからんぞ。'
}
$ShimPath = Join-Path $RuntimeBinDir 'yt-dlp.cmd'
$ShimLines = @(
    '@echo off',
    'chcp 932 >nul',
    ('if not "%YT_DLP_SKIP_UPDATE%"=="1" if exist "' + $UpdaterTarget + '" ('),
    ('    "' + $VenvPython + '" "' + $UpdaterTarget + '"'),
    ')',
    'if "%~1"=="" goto help',
    'if /I "%~1"=="-h" goto help',
    'if /I "%~1"=="--help" goto help',
    ('"' + $VenvPython + '" -m yt_dlp %*'),
    'exit /b %errorlevel%',
    ':help',
    ('"' + $VenvPython + '" -m yt_dlp --help'),
    'exit /b %errorlevel%'
)
[System.IO.File]::WriteAllLines($ShimPath, $ShimLines, [System.Text.Encoding]::GetEncoding(932))
Set-ManagedJunction -Link $BinDir -Target $RuntimeBinDir -Kind 'bin'
$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$PathParts = @($UserPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($PathParts -notcontains $BinDir) {
    [Environment]::SetEnvironmentVariable('Path', (($BinDir, $PathParts) -join ';'), 'User')
}
$env:Path = "$BinDir;$env:Path"
Write-Output "起動リンク: $(Join-Path $BinDir 'yt-dlp.cmd') -> $ShimPath"
Write-Output "起動時のpip更新確認: $UpdaterTarget"
#endregion

#region ffmpeg・aria2・Deno
$Tools = @(
    @{ Command = 'ffmpeg'; Package = 'Gyan.FFmpeg' },
    @{ Command = 'aria2c'; Package = 'aria2.aria2' }
)
foreach ($Tool in $Tools) {
    if (Get-Command $Tool.Command -ErrorAction SilentlyContinue) {
        Write-Output "確認済み: $($Tool.Command)"
        continue
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "wingetが見つからん。$($Tool.Command) を導入できんぞ。"
    }
    Write-Output "wingetで$($Tool.Package)をインストール中..."
    & winget install --id $Tool.Package --exact --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "$($Tool.Package) のインストールに失敗したぞ。"
    }
}
#endregion

#region 字幕変換ツールと設定
$ConverterDir = Join-Path $RuntimeDir 'tools\YTSubConverter'
New-Item -ItemType Directory -Path $ConverterDir -Force | Out-Null
$ConverterPath = Join-Path $ConverterDir 'YTSubConverter.exe'
$ConverterUrl = 'https://github.com/arcusmaximus/YTSubConverter/releases/download/1.6.4/YTSubConverter.exe'
Write-Output 'YTSubConverter.exeを取得中...'
Invoke-WebRequest -Uri $ConverterUrl -OutFile $ConverterPath -UseBasicParsing
if (-not (Test-Path -LiteralPath $ConverterPath) -or (Get-Item -LiteralPath $ConverterPath).Length -eq 0) {
    throw 'YTSubConverter.exeの取得に失敗したぞ。'
}
[Environment]::SetEnvironmentVariable('YTSC_PATH', $ConverterPath, 'User')
$env:YTSC_PATH = $ConverterPath

$ConverterScript = Join-Path $PSScriptRoot 'convert_config.ps1'
if (-not (Test-Path -LiteralPath $ConverterScript)) {
    throw 'convert_config.ps1 が見つからんぞ。'
}
& $ConverterScript
if (-not $?) {
    throw 'Windows向け設定ファイルの生成に失敗したぞ。'
}
$GeneratedConfig = Join-Path $PSScriptRoot 'win yt-dlp config'
if (-not (Test-Path -LiteralPath $GeneratedConfig)) {
    throw '変換済み設定ファイルが見つからんぞ。'
}
Set-ManagedConfigLink -Link (Join-Path $ConfigDir 'config') -Target $GeneratedConfig
#endregion

#region MPC-BE専用yt-dlp Shim
function Test-MpcBePresent {
    $AppDataDir = Join-Path $env:APPDATA 'MPC-BE'
    if (Test-Path -LiteralPath $AppDataDir -PathType Container) {
        return $true
    }
    foreach ($Name in @('mpc-be64.exe', 'mpc-be.exe')) {
        if (Get-Command $Name -ErrorAction SilentlyContinue) {
            return $true
        }
        foreach ($RegistryRoot in @(
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'
        )) {
            if (Test-Path -LiteralPath (Join-Path $RegistryRoot $Name)) {
                return $true
            }
        }
    }
    $InstallRoots = @(
        $env:ProgramFiles,
        [Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),
        (Join-Path $env:LOCALAPPDATA 'Programs')
    )
    foreach ($Root in $InstallRoots) {
        if (-not $Root -or -not (Test-Path -LiteralPath $Root -PathType Container)) {
            continue
        }
        foreach ($Folder in @('MPC-BE', 'MPC-BE x64', 'MPC-BE x86')) {
            $Candidate = Join-Path $Root $Folder
            foreach ($Name in @('mpc-be64.exe', 'mpc-be.exe')) {
                if (Test-Path -LiteralPath (Join-Path $Candidate $Name) -PathType Leaf) {
                    return $true
                }
            }
        }
    }
    return $false
}

if (Test-MpcBePresent) {
    $MpcYtDlpExe = Join-Path $VenvDir 'Scripts\yt-dlp.exe'
    $MpcShimSource = Join-Path $PSScriptRoot 'tools\mpc_be_yt_dlp_shim.cs'
    if (-not (Test-Path -LiteralPath $MpcYtDlpExe -PathType Leaf)) {
        throw 'pip版yt-dlp.exeが見つからんぞ。'
    }
    if (-not (Test-Path -LiteralPath $MpcShimSource -PathType Leaf)) {
        throw 'MPC-BE用Shimのソースが見つからんぞ。'
    }
    $MpcShimDirectory = Join-Path $RuntimeDir 'mpc-be'
    New-Item -ItemType Directory -Path $MpcShimDirectory -Force | Out-Null
    $MpcShimExe = Join-Path $MpcShimDirectory 'yt-dlp.exe'
    $MpcShimConfig = Join-Path $MpcShimDirectory 'yt-dlp.shim'
    $TempExe = Join-Path $env:TEMP ("yt-dlp-mpcbe-" + [Guid]::NewGuid().ToString('N') + '.exe')
    try {
        Add-Type -Path $MpcShimSource -OutputAssembly $TempExe -OutputType ConsoleApplication -ErrorAction Stop
        Copy-Item -LiteralPath $TempExe -Destination $MpcShimExe -Force
    }
    finally {
        Remove-Item -LiteralPath $TempExe -Force -ErrorAction SilentlyContinue
    }
    [System.IO.File]::WriteAllText(
        $MpcShimConfig,
        "$MpcYtDlpExe`n--ignore-config",
        [System.Text.Encoding]::UTF8
    )
    $MpcLink = Join-Path $env:APPDATA 'MPC-BE\yt-dlp'
    New-Item -ItemType Directory -Path (Split-Path -Parent $MpcLink) -Force | Out-Null
    Set-ManagedJunction -Link $MpcLink -Target $MpcShimDirectory -Kind 'mpc'
    Write-Output "MPC-BE専用yt-dlp: $(Join-Path $MpcLink 'yt-dlp.exe')"
    Write-Output 'MPC-BEのyt-dlp実行可能ファイルには上記のパスを指定するのじゃ。'
}
#endregion

#region Deno（リポジトリ内）
$DenoDir = Join-Path $RuntimeDir 'tools\deno'
$DenoExe = Join-Path $DenoDir 'deno.exe'
if (-not (Test-Path -LiteralPath $DenoExe -PathType Leaf)) {
    New-Item -ItemType Directory -Path $DenoDir -Force | Out-Null
    $DenoZip = Join-Path $RuntimeDir 'deno-download.zip'
    try {
        Invoke-WebRequest -Uri 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip' -OutFile $DenoZip -UseBasicParsing
        Expand-Archive -LiteralPath $DenoZip -DestinationPath $DenoDir -Force
    }
    finally {
        Remove-Item -LiteralPath $DenoZip -Force -ErrorAction SilentlyContinue
    }
}
if (-not (Test-Path -LiteralPath $DenoExe -PathType Leaf)) {
    throw 'リポジトリ内へDenoをインストールできなかったぞ。'
}
Copy-Item -LiteralPath $DenoExe -Destination (Join-Path $RuntimeBinDir 'deno.exe') -Force
Write-Output "Deno実体: $DenoExe"
#endregion

#region 旧方式の専用ファイルを整理
$OldRoot = Join-Path $env:LOCALAPPDATA 'yt-dlp'
$OldVenv = Join-Path $OldRoot 'venv'
if ((Test-Path -LiteralPath (Join-Path $OldVenv 'pyvenv.cfg')) -and
    (Test-Path -LiteralPath (Join-Path $OldVenv 'Scripts\yt-dlp.exe'))) {
    Remove-Item -LiteralPath $OldVenv -Recurse -Force
    Write-Output "旧venv削除: $OldVenv"
}
$OldUpdater = Join-Path $OldRoot 'auto_update.py'
if ((Test-Path -LiteralPath $OldUpdater -PathType Leaf) -and
    (Select-String -LiteralPath $OldUpdater -SimpleMatch 'yt-dlp-update.lock' -Quiet)) {
    Remove-Item -LiteralPath $OldUpdater -Force
    Write-Output "旧更新スクリプト削除: $OldUpdater"
}
$OldConverter = Join-Path $ConfigDir 'tools\YTSubConverter\YTSubConverter.exe'
if (Test-Path -LiteralPath $OldConverter -PathType Leaf) {
    Remove-Item -LiteralPath $OldConverter -Force
    Write-Output "旧字幕変換ツール削除: $OldConverter"
}
#endregion

#region 完了
Write-Output "セットアップ完了じゃ。"
Write-Output "仮想環境: $VenvDir"
Write-Output "設定: $(Join-Path $ConfigDir 'config')"
Write-Output '新しいターミナルで yt-dlp --version を確認するのじゃ。'
#endregion
