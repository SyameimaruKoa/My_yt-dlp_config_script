<#
.SYNOPSIS
    Subtitle converter wrapper called by yt-dlp
.PARAMETER VideoPath
    Path to the video file
.NOTES
    Encoding: UTF-8 with BOM
#>
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$VideoPath,
    [switch]$Help
)

$TargetExtensions = @(".srv3")
$AssOutputExtension = ".ass"
$SrtOutputExtension = ".srt"

if ($Help -or [string]::IsNullOrWhiteSpace($VideoPath)) {
    Get-Help -Detailed $MyInvocation.MyCommand.Path
    exit 0
}

function Find-YTSubConverter {
    param([string]$VideoDirectory)
    $candidates = @()
    if ($env:YTSC_PATH) {
        if (Test-Path -LiteralPath $env:YTSC_PATH) {
            if ((Get-Item -LiteralPath $env:YTSC_PATH) -is [System.IO.DirectoryInfo]) {
                $candidates += (Join-Path $env:YTSC_PATH 'YTSubConverter.exe')
            } else {
                $candidates += $env:YTSC_PATH
            }
        }
    }
    $candidates += (Join-Path $PSScriptRoot 'YTSubConverter.exe')
    if ($VideoDirectory) {
        $candidates += (Join-Path $VideoDirectory 'YTSubConverter.exe')
    }
    $cmd = Get-Command 'YTSubConverter.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($c in $candidates | Select-Object -Unique) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

function ConvertTo-SimpleSrt {
    param([string]$InputFile, [string]$OutputFile)
    [xml]$xml = Get-Content -LiteralPath $InputFile -Encoding utf8
    $srtLines = @()
    $index = 1
    foreach ($p in $xml.timedtext.body.p) {
        $startMs = [int]$p.t
        $durationMs = [int]$p.d
        $endMs = $startMs + $durationMs
        $startTime = ConvertTo-SrtTime -Milliseconds $startMs
        $endTime = ConvertTo-SrtTime -Milliseconds $endMs
        $text = $p.InnerText.Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $srtLines += $index
        $srtLines += "$startTime --> $endTime"
        $srtLines += $text
        $srtLines += ""
        $index++
    }
    $srtLines | Out-File -LiteralPath $OutputFile -Encoding utf8 -Force
}

function ConvertTo-SrtTime {
    param([int]$Milliseconds)
    $hours = [int][math]::Floor($Milliseconds / 3600000)
    $minutes = [int][math]::Floor(($Milliseconds % 3600000) / 60000)
    $seconds = [int][math]::Floor(($Milliseconds % 60000) / 1000)
    $ms = [int]($Milliseconds % 1000)
    return ("{0:D2}:{1:D2}:{2:D2},{3:D3}" -f $hours, $minutes, $seconds, $ms)
}

Write-Output "--- YTSubConverter Start ---"
Write-Output "Video: $VideoPath"

$VideoBaseName = [System.IO.Path]::GetFileNameWithoutExtension($VideoPath)
$VideoDirectory = [System.IO.Path]::GetDirectoryName($VideoPath)

$ConverterExePath = Find-YTSubConverter -VideoDirectory $VideoDirectory
if ($ConverterExePath) {
    Write-Output "YTSubConverter: $ConverterExePath"
} else {
    Write-Warning "YTSubConverter.exe not found"
}

$SubtitleExtensions = @('.srv3', '.srt', '.vtt', '.ass')
$LanguageCodes = @('ja', 'en', 'ko', 'zh-Hans', 'zh-Hant', 'vi', 'es', 'fr', 'de', 'ru')
$SubtitleFiles = @()

foreach ($lang in $LanguageCodes) {
    foreach ($ext in $SubtitleExtensions) {
        $possiblePath = Join-Path $VideoDirectory "$VideoBaseName.$lang$ext"
        if (Test-Path -LiteralPath $possiblePath) {
            $SubtitleFiles += Get-Item -LiteralPath $possiblePath
        }
    }
}

foreach ($ext in $SubtitleExtensions) {
    $possiblePath = Join-Path $VideoDirectory "$VideoBaseName$ext"
    if (Test-Path -LiteralPath $possiblePath) {
        $SubtitleFiles += Get-Item -LiteralPath $possiblePath
    }
}

if ($SubtitleFiles.Count -eq 0) {
    Write-Output "No subtitle files found"
    exit 0
}

foreach ($FileObj in $SubtitleFiles) {
    $DownloadedFile = $FileObj.FullName
    $FileExtension = [System.IO.Path]::GetExtension($DownloadedFile).ToLower()
    if ($TargetExtensions -notcontains $FileExtension) { continue }
    
    Write-Output "Processing: $DownloadedFile"
    if (-not (Test-Path -LiteralPath $DownloadedFile)) { continue }
    
    $FileContent = ""
    try {
        $FileContent = Get-Content -LiteralPath $DownloadedFile -Encoding utf8 -Raw -ErrorAction Stop
    } catch {
        Write-Error "Failed to read: $_"
        continue
    }
    
    $NeedsConversion = $false
    if ($FileContent -match '<span') {
        $NeedsConversion = $true
        Write-Output "Detected span tag - using YTSubConverter"
    } elseif ($FileContent -match '<u') {
        $NeedsConversion = $true
        Write-Output "Detected u tag - using YTSubConverter"
    } elseif ($FileContent -match '<pen\s') {
        $NeedsConversion = $true
        Write-Output "Detected pen tag (styled subtitles) - using YTSubConverter"
    }
    
    if ($NeedsConversion -eq $false) {
        Write-Output "Simple XML - converting to SRT"
        $OutputSubtitleFile = [System.IO.Path]::ChangeExtension($DownloadedFile, $SrtOutputExtension)
        try {
            ConvertTo-SimpleSrt -InputFile $DownloadedFile -OutputFile $OutputSubtitleFile
            Write-Output "Converted: $OutputSubtitleFile"
            Remove-Item -LiteralPath $DownloadedFile -Force -ErrorAction Stop
        } catch {
            Write-Warning "Conversion failed: $_"
        }
        continue
    }
    
    if (-not $ConverterExePath) {
        Write-Warning "YTSubConverter.exe not found - skipping"
        continue
    }
    
    $OutputSubtitleFile = [System.IO.Path]::ChangeExtension($DownloadedFile, $AssOutputExtension)
    Write-Output "Converting to ASS: $OutputSubtitleFile"
    try {
        & "$ConverterExePath" "$DownloadedFile" "$OutputSubtitleFile" 2>&1 | Out-Null
        
        if (Test-Path -LiteralPath $OutputSubtitleFile) {
            Write-Output "Converted: $OutputSubtitleFile"
            Remove-Item -LiteralPath $DownloadedFile -Force -ErrorAction Stop
        } else {
            Write-Warning "Conversion may have failed - output file not found (Exit: $LASTEXITCODE)"
        }
    } catch {
        Write-Error "Error: $_"
    }
}

Write-Output "--- YTSubConverter Completed ---"
exit 0
