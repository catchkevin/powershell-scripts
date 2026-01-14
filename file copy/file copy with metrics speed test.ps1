# ============================================================
# File Copy Speed Test with Logging, Throughput & ETA
# Supports: Single File OR All Files in Directory
# ============================================================

# -------------------------
# Helper: Yes/No prompt
# -------------------------
function Read-YesNo {
    param([Parameter(Mandatory)][string]$Prompt)

    while ($true) {
        $raw = (Read-Host "$Prompt [`"Y`"es | `"N`"o]").Trim().ToLower()
        switch ($raw) {
            'y'   { return $true }
            'yes' { return $true }
            'n'   { return $false }
            'no'  { return $false }
            default {
                Write-Host 'Please enter ["Y"es | "N"o].' -ForegroundColor Yellow
            }
        }
    }
}

# -------------------------
# Copy Mode Selection
# -------------------------
while ($true) {
    Write-Host ''
    Write-Host 'Copy ["S"pecific File] or ["A"ll Files] in a Directory'
    Write-Host 'Note: (You are looking for an answer as S or A)'
    $mode = (Read-Host 'Enter choice').Trim().ToUpper()

    if ($mode -in @('S','A')) { break }
    Write-Host 'Please enter S or A.' -ForegroundColor Yellow
}

# -------------------------
# Source selection
# -------------------------
$sourceFiles = @()

if ($mode -eq 'S') {

    $sourceDir = Read-Host 'Enter Source Directory'
    if (-not (Test-Path $sourceDir)) {
        Write-Error 'Source directory does not exist.'
        exit
    }

    $fileName = Read-Host 'Enter Filename'
    $fullPath = Join-Path $sourceDir $fileName

    if (-not (Test-Path $fullPath)) {
        Write-Error 'Source file does not exist.'
        exit
    }

    $sourceFiles += Get-Item $fullPath
}
else {
    $sourceDir = Read-Host 'Enter Source Directory'
    if (-not (Test-Path $sourceDir)) {
        Write-Error 'Source directory does not exist.'
        exit
    }

    $sourceFiles = Get-ChildItem -Path $sourceDir -File
    if ($sourceFiles.Count -eq 0) {
        Write-Error 'No files found in source directory.'
        exit
    }
}

# -------------------------
# Destination folder
# -------------------------
$destFolder = Read-Host 'Enter Destination Folder Path'
if (-not (Test-Path $destFolder)) {
    Write-Host "Creating destination folder: $destFolder" -ForegroundColor Yellow
    New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
}

# -------------------------
# Log folder
# -------------------------
$logFolder = "$env:USERPROFILE\Documents\filecopytest_logs"
if (-not (Test-Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory | Out-Null
}

# ============================================================
# COPY EACH FILE
# ============================================================
foreach ($file in $sourceFiles) {

    $sourcePath = $file.FullName
    $destPath   = Join-Path $destFolder $file.Name

    if (Test-Path $destPath) {
        if (-not (Read-YesNo "Destination file '$($file.Name)' exists. Overwrite")) {
            Write-Host "Skipping $($file.Name)"
            continue
        }
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logFile = "$logFolder\copy_file_test_$($file.BaseName)_$timestamp.csv"

    'Time,BytesTransferred,Percent,MBps,GBps,ETA' |
        Out-File -FilePath $logFile -Encoding UTF8

    $fileSize    = $file.Length
    $bufferSize  = 4MB
    $buffer      = New-Object byte[] $bufferSize
    $bytesCopied = 0

    $startTime   = Get-Date
    $lastLogTime = $startTime
    $lastBytes   = 0

    Write-Host ''
    Write-Host "Copying: $($file.Name)" -ForegroundColor Cyan
    Write-Host "Size   : $([math]::Round($fileSize / 1GB,2)) GB"
    Write-Host "Log    : $logFile"
    Write-Host '-------------------------------------------------------------'

    try {
        $fsSource = [System.IO.File]::OpenRead($sourcePath)
        $fsDest   = [System.IO.File]::OpenWrite($destPath)
    }
    catch {
        Write-Error "Failed to open streams for $($file.Name): $_"
        continue
    }

    while (($read = $fsSource.Read($buffer, 0, $buffer.Length)) -gt 0) {

        $fsDest.Write($buffer, 0, $read)
        $bytesCopied += $read

        $now = Get-Date
        $elapsed = ($now - $lastLogTime).TotalSeconds

        if ($elapsed -ge 1) {

            $deltaBytes = $bytesCopied - $lastBytes
            $mbps = [math]::Round(($deltaBytes / 1MB) / $elapsed, 2)
            $gbps = [math]::Round(($deltaBytes / 1GB) / $elapsed, 4)
            $percent = [math]::Round(($bytesCopied / $fileSize) * 100, 2)

            $totalElapsed = ($now - $startTime).TotalSeconds
            $avgRate = $bytesCopied / $totalElapsed
            $remainingSeconds = ($fileSize - $bytesCopied) / $avgRate
            $eta = (New-TimeSpan -Seconds $remainingSeconds).ToString('hh\:mm\:ss')

            $ts = $now.ToString('yyyy-MM-dd HH:mm:ss')

            Write-Host (
                '{0} | {1,6}% | {2,8:N0}/{3,8:N0} MB | {4,6} MB/s | ETA {5}' -f
                $ts,
                $percent,
                ($bytesCopied / 1MB),
                ($fileSize / 1MB),
                $mbps,
                $eta
            )

            "$ts,$bytesCopied,$percent,$mbps,$gbps,$eta" |
                Out-File -FilePath $logFile -Append -Encoding UTF8

            $lastLogTime = $now
            $lastBytes   = $bytesCopied
        }
    }

    $fsSource.Close()
    $fsDest.Close()

    $endTime = Get-Date
    $totalTime = $endTime - $startTime
    $avgMBps = [math]::Round(($fileSize / 1MB) / $totalTime.TotalSeconds, 2)

    $summary = @"
================ COPY SUMMARY ================
File            : $($file.Name)
File Size       : $([math]::Round($fileSize / 1GB,2)) GB
Start Time      : $startTime
End Time        : $endTime
Total Time      : $totalTime
Average Speed   : $avgMBps MB/s
Log File        : $logFile
=============================================
"@

    Write-Host $summary -ForegroundColor Green
    $summary | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Write-Host ''
Write-Host 'All copy operations completed.' -ForegroundColor Cyan
