# ============================================================
# Hybrid AzCopy File Copy with 1-Second Metrics + Logging
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
            default { Write-Host 'Enter ["Y"es | "N"o]' -ForegroundColor Yellow }
        }
    }
}

# -------------------------
# Validate AzCopy
# -------------------------
if (-not (Get-Command azcopy -ErrorAction SilentlyContinue)) {
    Write-Error 'AzCopy is not installed or not in PATH.'
    exit
}

# -------------------------
# Copy Mode
# -------------------------
do {
    Write-Host ''
    Write-Host 'Copy ["S"pecific File] or ["A"ll Files] in a Directory'
    Write-Host 'Note: (Answer must be S or A)'
    $mode = (Read-Host 'Enter choice').Trim().ToUpper()
} until ($mode -in @('S','A'))

# -------------------------
# Source selection
# -------------------------
$sourceFiles = @()

if ($mode -eq 'S') {
    $sourceDir = Read-Host 'Enter Source Directory'
    $fileName  = Read-Host 'Enter Filename'

    $fullPath = Join-Path $sourceDir $fileName
    if (-not (Test-Path $fullPath)) {
        Write-Error 'Source file does not exist.'
        exit
    }

    $sourceFiles = Get-Item $fullPath
}
else {
    $sourceDir = Read-Host 'Enter Source Directory'
    if (-not (Test-Path $sourceDir)) {
        Write-Error 'Source directory does not exist.'
        exit
    }

    $sourceFiles = Get-ChildItem $sourceDir -File
    if (-not $sourceFiles) {
        Write-Error 'No files found.'
        exit
    }
}

# -------------------------
# Destination
# -------------------------
$destFolder = Read-Host 'Enter Destination Folder'
if (-not (Test-Path $destFolder)) {
    New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
}

# -------------------------
# Log directory
# -------------------------
$metricsLogDir = "$env:USERPROFILE\Documents\filecopytest_logs"
if (-not (Test-Path $metricsLogDir)) {
    New-Item -Path $metricsLogDir -ItemType Directory | Out-Null
}

# ============================================================
# COPY LOOP
# ============================================================
foreach ($file in $sourceFiles) {

    $startTime = Get-Date
    $timestamp = $startTime.ToString('yyyyMMdd_HHmmss')

    $metricsLog = "$metricsLogDir\copy_file_test_$($file.BaseName)_$timestamp.csv"
    $azLogDir   = "$env:USERPROFILE\.azcopy"

    'Time,BytesTransferred,Percent,MBps,GBps,ETA' |
        Out-File $metricsLog -Encoding UTF8

    $totalBytes = $file.Length
    $destPath   = Join-Path $destFolder $file.Name

    if (Test-Path $destPath) {
        if (-not (Read-YesNo "Destination file '$($file.Name)' exists. Overwrite")) {
            continue
        }
    }

    Write-Host ''
    Write-Host "Starting copy: $($file.Name)" -ForegroundColor Cyan
    Write-Host "Size: $([math]::Round($totalBytes / 1GB,2)) GB"
    Write-Host '-------------------------------------------------------------'

    # Capture baseline AzCopy log count
    $existingLogs = Get-ChildItem $azLogDir -Filter '*.log' | Sort-Object LastWriteTime

    # Start AzCopy
    $azArgs = @(
        'copy'
        "`"$($file.FullName)`""
        "`"$destFolder`""
        '--overwrite=true'
        '--from-to=LocalLocal'
        '--log-level=INFO'
        '--output-type=text'
    )

    $proc = Start-Process azcopy `
        -ArgumentList ($azArgs -join ' ') `
        -NoNewWindow `
        -PassThru

    # Wait for AzCopy log file to appear
    do {
        Start-Sleep -Milliseconds 500
        $newLogs = Get-ChildItem $azLogDir -Filter '*.log' |
                   Where-Object { $_.LastWriteTime -gt $startTime }
    } until ($newLogs)

    $azLog = $newLogs | Sort-Object LastWriteTime | Select-Object -Last 1

    $lastBytes = 0
    $lastTime  = Get-Date

    # -------------------------
    # 1-Second Metrics Loop
    # -------------------------
    while (-not $proc.HasExited) {

        Start-Sleep 1
        $now = Get-Date

        # Extract latest byte count from AzCopy log
        $lines = Get-Content $azLog.FullName -Tail 200 -ErrorAction SilentlyContinue
        $byteLine = $lines | Select-String 'BytesTransferred'

        if ($byteLine) {
            if ($byteLine.Line -match 'BytesTransferred:\s+(\d+)') {
                $bytesCopied = [int64]$matches[1]

                $deltaBytes = $bytesCopied - $lastBytes
                $elapsed = ($now - $lastTime).TotalSeconds
                if ($elapsed -le 0) { continue }

                $mbps = [math]::Round(($deltaBytes / 1MB) / $elapsed, 2)
                $gbps = [math]::Round(($deltaBytes / 1GB) / $elapsed, 4)
                $percent = [math]::Round(($bytesCopied / $totalBytes) * 100, 2)

                $avgRate = $bytesCopied / ($now - $startTime).TotalSeconds
                $etaSec = ($totalBytes - $bytesCopied) / $avgRate
                $eta = (New-TimeSpan -Seconds $etaSec).ToString('hh\:mm\:ss')

                $ts = $now.ToString('yyyy-MM-dd HH:mm:ss')

                $output = "{0} | {1,6}% | {2,8:N0}/{3,8:N0} MB | {4,6} MB/s | ETA {5}" -f `
                    $ts, $percent,
                    ($bytesCopied / 1MB),
                    ($totalBytes / 1MB),
                    $mbps,
                    $eta

                Write-Host $output

                "$ts,$bytesCopied,$percent,$mbps,$gbps,$eta" |
                    Out-File $metricsLog -Append -Encoding UTF8

                $lastBytes = $bytesCopied
                $lastTime  = $now
            }
        }
    }

    # -------------------------
    # Summary
    # -------------------------
    $endTime = Get-Date
    $totalTime = $endTime - $startTime
    $avgMBps = [math]::Round(($totalBytes / 1MB) / $totalTime.TotalSeconds, 2)

    $summary = @"
================ COPY SUMMARY ================
File           : $($file.Name)
Size           : $([math]::Round($totalBytes / 1GB,2)) GB
Start Time     : $startTime
End Time       : $endTime
Total Time     : $totalTime
Average Speed  : $avgMBps MB/s
Metrics Log    : $metricsLog
=============================================
"@

    Write-Host ''
    Write-Host $summary -ForegroundColor Green
    $summary | Out-File $metricsLog -Append -Encoding UTF8
}

Write-Host ''
Write-Host 'All transfers completed.' -ForegroundColor Cyan
