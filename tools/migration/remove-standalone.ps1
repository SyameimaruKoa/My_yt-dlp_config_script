<#
.SYNOPSIS
    旧yt-dlp.exe単独実行ファイルを削除するのじゃ。
.DESCRIPTION
    一度だけ使用する移行用スクリプト。
    ユーザーディレクトリ内の既知の単独実行ファイル配置先を確認する。
    仮想環境内のpip実行ファイル、シンボリックリンク、yt-dlp.cmdは削除しない。
.PARAMETER Path
    自動検索対象の代わりに確認するyt-dlp.exeの絶対パス。複数指定可能。
.PARAMETER DryRun
    削除せず、削除対象を表示する。
.EXAMPLE
    .\remove-standalone.ps1
.EXAMPLE
    .\remove-standalone.ps1 --dry-run
.EXAMPLE
    .\remove-standalone.ps1 --path 'C:\Tools\yt-dlp.exe'
.EXAMPLE
    .\remove-standalone.ps1 --help
.NOTES
    文字コード: UTF-8 BOM
#>

#region 引数とヘルプ
$DryRun = $false
$ExplicitPaths = [System.Collections.Generic.List[string]]::new()
for ($Index = 0; $Index -lt $args.Count; $Index++) {
    switch ($args[$Index]) {
        { $_ -in @('-h', '--help') } {
            Get-Help -Detailed $MyInvocation.MyCommand.Path
            exit 0
        }
        { $_ -in @('-DryRun', '--dry-run') } {
            $DryRun = $true
        }
        { $_ -in @('-Path', '--path') } {
            if ($Index + 1 -ge $args.Count) {
                Get-Help -Detailed $MyInvocation.MyCommand.Path
                exit 1
            }
            $Index++
            $ExplicitPaths.Add($args[$Index])
        }
        default {
            Write-Error "不明な引数じゃ: $($args[$Index])"
            exit 1
        }
    }
}
#endregion

#region 削除対象
if ($ExplicitPaths.Count -gt 0) {
    $Targets = @($ExplicitPaths)
}
else {
    $Targets = @(
        (Join-Path $env:LOCALAPPDATA 'yt-dlp\yt-dlp.exe'),
        (Join-Path $env:LOCALAPPDATA 'yt-dlp\bin\yt-dlp.exe'),
        (Join-Path $env:USERPROFILE '.local\bin\yt-dlp.exe'),
        (Join-Path $env:USERPROFILE 'bin\yt-dlp.exe')
    )
}
#endregion

#region 単独実行ファイルの確認と削除
foreach ($Target in ($Targets | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
        Write-Output "対象なし: $Target"
        continue
    }
    $File = Get-Item -LiteralPath $Target -Force
    if ($File.Name -ine 'yt-dlp.exe' -or
        $File.FullName -match '(?i)[\\/]Scripts[\\/]yt-dlp\.exe$' -or
        ($File.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        Write-Output "保持（単独版ではない）: $Target"
        continue
    }
    $Stream = [System.IO.File]::OpenRead($File.FullName)
    try {
        $IsExecutable = ($Stream.ReadByte() -eq 0x4d -and $Stream.ReadByte() -eq 0x5a)
    }
    finally {
        $Stream.Dispose()
    }
    if (-not $IsExecutable) {
        Write-Output "保持（exeではない）: $Target"
        continue
    }
    if ($DryRun) {
        Write-Output "削除予定: $Target"
        continue
    }
    Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
    Write-Output "削除完了: $Target"
}
#endregion
