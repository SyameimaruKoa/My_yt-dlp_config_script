<#
.SYNOPSIS
    yt-dlp から 'after_download' で呼び出され、字幕の中身を判別するラッパーなのじゃ。
.DESCRIPTION
    (ユーザー指示 [2025-09-24] に基づくヘルプ実装)
    拡張子が対象 (例: .srv3) なら中身を読み、<span> や <u> が含まれる場合のみ
    YTSubConverter.exe で .ass ファイルに変換する。
    変換成功後は、元の .srv3 ファイルを削除するぞ。
.PARAMETER DownloadedFile
    [必須] ダウンロードが完了したファイルのパス (yt-dlp から渡される)。
.EXAMPLE
    .\run_sub_converter.ps1 "C:\path\to\simple_lyrics.srv3" (-> 中身を読み、<span> が無いのでスキップ)
    .\run_sub_converter.ps1 "C:\path\to\styled_caption.srv3" (-> 中身を読み、<span> を見つけて .ass に変換し、元の .srv3 を削除)
.NOTES
    文字コード: UTF-8 で保存するんじゃぞ。
#>
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$DownloadedFile
)

#region --- 設定 ---
# (ユーザー指示 [2025-09-24] #region 実装)

# YTSubConverter.exe のパス (このスクリプトと同じフォルダを仮定)
$ConverterExePath = Join-Path $PSScriptRoot "YTSubConverter.exe"

# ★★★ 変換対象か判別する拡張子 (小文字) ★★★
$TargetExtensions = @(
    ".srv3"
    # ".srv2", ".ttml" なども対象にするならここに追加
)

# ★★★ 変換後の拡張子 ★★★
$OutputExtension = ".ass"
#endregion

#region --- メイン処理 ---

# 渡されたファイルの拡張子を小文字で取得
$FileExtension = ""
try {
    $FileExtension = [System.IO.Path]::GetExtension($DownloadedFile).ToLower()
}
catch {
    Write-Warning "渡されたパス ($DownloadedFile) の拡張子が取得できんかった。"
    exit 0 # 何もせず終了
}

# 1. 変換対象の拡張子 (TargetExtensions) 以外なら、即座に終了
if ([string]::IsNullOrEmpty($FileExtension) -or ($TargetExtensions -notcontains $FileExtension)) {
    # (vtt, mp4, m4a, live_chat.json などはここで静かに終了する)
    exit 0
}

# 2. ここに来た = .srv3 など、中身を判別すべきファイル
Write-Output "--- YTSubConverter (PowerShell) 実行判別 ---"

# 必要なファイルの存在確認
if (-not (Test-Path $ConverterExePath)) {
    Write-Error "エラー: YTSubConverter.exe が見つからん！"
    Write-Error "期待したパス: $ConverterExePath"
    exit 1
}
if (-not (Test-Path $DownloadedFile)) {
    Write-Error "エラー: yt-dlp から渡されたはずの字幕ファイルが見つからん！"
    Write-Error "指定されたパス: $DownloadedFile"
    exit 1
}

Write-Output "判別対象: $DownloadedFile"

# 3. ファイルの中身を読み、スタイル (<span>) や ASR (<u>) を含むか判別する
$FileContent = ""
try {
    # ファイルを UTF-8 として読み込む (YouTubeの字幕はUTF-8のはず)
    $FileContent = Get-Content -Path $DownloadedFile -Encoding utf8 -Raw
}
catch {
    Write-Error "エラー: 字幕ファイル ($DownloadedFile) の読み込みに失敗した。"
    exit 1
}

# --- 変換すべきかどうかの判定 ---
$NeedsConversion = $false
if ($FileContent -match '<span') {
    $NeedsConversion = $true
    Write-Output "情報: <span> タグ (スタイル) を検出。YTSubConverter を実行します。"
}
elseif ($FileContent -match '<u') { 
    $NeedsConversion = $true
    Write-Output "情報: <u> タグ (ASR/強調) を検出。YTSubConverter を実行します。"
}

if ($NeedsConversion -eq $false) {
    Write-Output "情報: ファイルは <span> や <u> を含まない単純なXML (Pタグのみ) と判断。"
    Write-Output "情報: 変換をスキップします。" # そなたの動画は全てここに来るはずじゃ
    Write-Output "-----------------------------------"
    exit 0 # ★★★ スキップして正常終了 ★★★
}

# 4. 実行 (NeedsConversion が true の場合のみ)

# (A) 出力ファイルパスを生成する (例: ...\video.ja.srv3 -> ...\video.ja.ass)
$OutputSubtitleFile = [System.IO.Path]::ChangeExtension($DownloadedFile, $OutputExtension)

Write-Output "出力ファイル: $OutputSubtitleFile"
Write-Output "実行コマンド: & `"$ConverterExePath`" `"$DownloadedFile`" `"$OutputSubtitleFile`""

try {
    # (B) & 演算子 (call operator) で実行 (出力パスも渡す！)
    & "$ConverterExePath" "$DownloadedFile" "$OutputSubtitleFile"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "エラー: YTSubConverter.exe の実行に失敗したぞ (ExitCode: $LASTEXITCODE)。"
        exit $LASTEXITCODE
    }

    Write-Output "変換完了じゃ。"
    
    # (C) 元の .srv3 ファイルを削除する
    try {
        Write-Output "情報: 変換元のファイル ($DownloadedFile) を削除します。"
        Remove-Item -Path $DownloadedFile -Force -ErrorAction Stop
        Write-Output "情報: 元ファイルの削除完了。"
    }
    catch {
        Write-Warning "警告: 変換元のファイル ($DownloadedFile) の削除に失敗した: $_"
    }

}
catch {
    Write-Error "スクリプト実行中に致命的なエラーが発生した: $_"
    exit 1
}

Write-Output "-----------------------------------"
exit 0
#endregion