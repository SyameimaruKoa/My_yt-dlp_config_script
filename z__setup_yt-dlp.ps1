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
$ShimPath = Join-Path $BinDir 'yt-dlp.cmd'
$ShimLines = @(
    '@echo off',
    'chcp 932 >nul',
    'if "%~1"=="" goto help',
    'if /I "%~1"=="-h" goto help',
    'if /I "%~1"=="--help" goto help',
    ('"{0}" -m yt_dlp %*' -f $VenvPython),
    'exit /b %errorlevel%',
    ':help',
    ('"{0}" -m yt_dlp --help' -f $VenvPython),
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
if ($LASTEXITCODE -ne 0) {
    throw 'Windows向け設定ファイルの生成に失敗したぞ。'
}
$GeneratedConfig = Join-Path $PSScriptRoot 'win yt-dlp config'
if (-not (Test-Path -LiteralPath $GeneratedConfig)) {
    throw '変換済み設定ファイルが見つからんぞ。'
}
Copy-Item -LiteralPath $GeneratedConfig -Destination (Join-Path $ConfigDir 'config') -Force
#endregion

#region 完了
Write-Output "セットアップ完了じゃ。"
Write-Output "仮想環境: $VenvDir"
Write-Output "設定: $(Join-Path $ConfigDir 'config')"
Write-Output '新しいターミナルで yt-dlp --version を確認するのじゃ。'
#endregion
