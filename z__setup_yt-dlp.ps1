<#
.SYNOPSIS
    Windowsにyt-dlp Nightly、Python仮想環境、依存ツール、設定を導入するのじゃ。
.DESCRIPTION
    %LOCALAPPDATA%\yt-dlp\venv にPython仮想環境を作成し、pipでyt-dlpと追加依存関係を導入する。
    yt-dlp.cmd をユーザーPATHに登録し、仮想環境を手動で有効化せずにyt-dlpを実行できるようにする。
    wingetでffmpeg、aria2、Denoを準備し、YTSubConverterとWindows用設定ファイルも配置する。
.EXAMPLE
    .\z__setup_yt-dlp.ps1
.EXAMPLE
    .\z__setup_yt-dlp.ps1 -h
.EXAMPLE
    .\z__setup_yt-dlp.ps1 --help
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
$VenvDir = Join-Path $env:LOCALAPPDATA 'yt-dlp\venv'
$BinDir = Join-Path $env:LOCALAPPDATA 'yt-dlp\bin'
$ConfigDir = Join-Path $env:APPDATA 'yt-dlp'
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
New-Item -ItemType Directory -Path $BinDir, $ConfigDir -Force | Out-Null
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
$UpdaterTarget = Join-Path $env:LOCALAPPDATA 'yt-dlp\auto_update.py'
if (-not (Test-Path -LiteralPath $UpdaterSource)) {
    throw '起動時の自動更新スクリプトが見つからんぞ。'
}
Copy-Item -LiteralPath $UpdaterSource -Destination $UpdaterTarget -Force
$ShimPath = Join-Path $BinDir 'yt-dlp.cmd'
$ShimLines = @(
    '@echo off',
    'chcp 932 >nul',
    'if not "%YT_DLP_SKIP_UPDATE%"=="1" if exist "%LOCALAPPDATA%\yt-dlp\auto_update.py" (',
    '    "%LOCALAPPDATA%\yt-dlp\venv\Scripts\python.exe" "%LOCALAPPDATA%\yt-dlp\auto_update.py"',
    ')',
    'if "%~1"=="" goto help',
    'if /I "%~1"=="-h" goto help',
    'if /I "%~1"=="--help" goto help',
    '"%LOCALAPPDATA%\yt-dlp\venv\Scripts\python.exe" -m yt_dlp %*',
    'exit /b %errorlevel%',
    ':help',
    '"%LOCALAPPDATA%\yt-dlp\venv\Scripts\python.exe" -m yt_dlp --help',
    'exit /b %errorlevel%'
)
[System.IO.File]::WriteAllLines($ShimPath, $ShimLines, [System.Text.Encoding]::GetEncoding(932))
$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$PathParts = @($UserPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($PathParts -notcontains $BinDir) {
    [Environment]::SetEnvironmentVariable('Path', (($BinDir, $PathParts) -join ';'), 'User')
}
$env:Path = "$BinDir;$env:Path"
Write-Output "yt-dlpコマンドを登録したぞ: $ShimPath"
Write-Output "起動時のpip更新確認: $UpdaterTarget"
#endregion

#region ffmpeg・aria2・Deno
$Tools = @(
    @{ Command = 'ffmpeg'; Package = 'Gyan.FFmpeg' },
    @{ Command = 'aria2c'; Package = 'aria2.aria2' },
    @{ Command = 'deno'; Package = 'DenoLand.Deno' }
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
$ConverterDir = Join-Path $ConfigDir 'tools\YTSubConverter'
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

$ConverterScript = Join-Path $PSScriptRoot 'z__convert_config.ps1'
if (-not (Test-Path -LiteralPath $ConverterScript)) {
    throw 'z__convert_config.ps1 が見つからんぞ。'
}
& $ConverterScript
if (-not $?) {
    throw 'Windows向け設定ファイルの生成に失敗したぞ。'
}
$GeneratedConfig = Join-Path $PSScriptRoot 'win yt-dlp config'
if (-not (Test-Path -LiteralPath $GeneratedConfig)) {
    throw '変換済み設定ファイルが見つからんぞ。'
}
Copy-Item -LiteralPath $GeneratedConfig -Destination (Join-Path $ConfigDir 'config') -Force
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
    $MpcShimDirectory = Join-Path $env:APPDATA 'MPC-BE\yt-dlp'
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
    Write-Output "MPC-BE専用yt-dlp: $MpcShimExe"
    Write-Output 'MPC-BEのyt-dlp実行可能ファイルには上記のパスを指定するのじゃ。'
}
#endregion

#region 完了
Write-Output "セットアップ完了じゃ。"
Write-Output "仮想環境: $VenvDir"
Write-Output "設定: $(Join-Path $ConfigDir 'config')"
Write-Output '新しいターミナルで yt-dlp --version を確認するのじゃ。'
#endregion
