<#
.SYNOPSIS
    'yt-dlp config' (Linux用) を 'win yt-dlp config' (Windows用) に変換するのじゃ。
.DESCRIPTION
    (ユーザー指示 [2025-09-24] に基づくヘルプ実装)
    バッチファイル (z__convert_config.bat) の代わりとなる、完全 PowerShell 版スクリプトじゃ。
    以下の変換処理を実行するぞ。
    1. /tmp を %TEMP% に置換する。
    2. Linux用 --exec (Koa_Discord_Message.sh) をコメントアウトする。
    3. Windows用 --exec (run_sub_converter.ps1 呼び出し) を挿入する。
.EXAMPLE
    .\z__convert_config.ps1
    (このスクリプトを実行するだけで 'win yt-dlp config' が生成される)
.NOTES
    文字コード: UTF-8 で保存するんじゃぞ。
    'yt-dlp config', 'run_sub_converter.ps1' と同じフォルダに置くこと。
#>
param ()

#region --- 設定 ---
# (ユーザー指示 [2025-09-24] #region 実装)

# このスクリプト (.ps1) があるフォルダのパス
$ScriptDirectory = $PSScriptRoot

# 入力ファイル (Linux用 config)
$InputFile = Join-Path $ScriptDirectory "yt-dlp config"
# 出力ファイル (Windows用 config)
$OutputFile = Join-Path $ScriptDirectory "win yt-dlp config"

# Windows用 --exec で呼び出すスクリプトファイル名
$WindowsExecScript = "run_sub_converter.ps1"
#endregion

#region --- メイン処理 ---
Write-Output "PowerShell 変換ロジック (z__convert_config.ps1) を実行中..."
Write-Output "入力: $InputFile"
Write-Output "出力: $OutputFile"

if (-not (Test-Path $InputFile)) {
    Write-Error "エラー: 入力ファイル '$InputFile' が見つからん！"
    Write-Error "このスクリプトと同じフォルダに 'yt-dlp config' を置くんじゃぞ。"
    exit 1
}

# 変換結果を格納する配列
$OutputLines = [System.Collections.Generic.List[string]]::new()

# 変換ロジック本体
try {
    Get-Content -Path $InputFile -Encoding Utf8 | ForEach-Object {
        if ($_ -like '--exec *Koa_Discord_Message.sh*') {
            # --- Linux用execをWindows用に差し替え ---
            $OutputLines.Add('# --- (元) Linux用Discord通知 (無効化) ---')
            $OutputLines.Add(('# ' + $_))
            $OutputLines.Add('# === (新) Windows用 字幕変換 (after_download/拡張子判別) ===')
            
            $ExecScriptPath = Join-Path $ScriptDirectory $WindowsExecScript
            
            # --- ★★★ (ここが修正箇所) ★★★ ---
            # '%%(filepath)q' を囲んでいた余計な '' を削除したぞ！
            # yt-dlp が %%(filepath)q を "C:\path\to\file.srv3" のようなクォート付きパスに
            # 置き換えてから PowerShell に渡してくれる。
            $ExecCommand = '--exec "after_download:powershell.exe -NoProfile -ExecutionPolicy Bypass -File ''{0}'' %%(filepath)q"' -f $ExecScriptPath
            
            $OutputLines.Add($ExecCommand)
        }
        else {
            # --- /tmp を %TEMP% に置換 ---
            $OutputLines.Add(($_ -replace '/tmp', '%TEMP%'))
        }
    }

    # 結果を UTF-8 でファイルに書き出す
    Set-Content -Path $OutputFile -Value $OutputLines -Encoding Utf8 -ErrorAction Stop

    Write-Output "--------------------"
    Write-Output "変換完了じゃ！"
    Write-Output "'$OutputFile' が正常に生成されたはずじゃぞ。"

}
catch {
    Write-Error "エラー: 変換または出力ファイル ($OutputFile) への書き込みに失敗したぞ！"
    Write-Error $_
    exit 1
}
#endregion