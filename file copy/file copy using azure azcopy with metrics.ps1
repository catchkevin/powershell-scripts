# ============================================================
# Hybrid AzCopy Copy Tool with Local/Blob + 1s Metrics
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
# AzCopy Path
# -------------------------
do {
    $AzCopyExe = (Read-Host 'Enter full path to azcopy.exe').Trim('"')
    if (-not (Test-Path $AzCopyExe)) {
        Write-Host 'Invalid azcopy.exe path.' -ForegroundColor Red
    }
} until (Test-Path $AzCopyExe)

# -------------------------
# Copy Direction
# -------------------------
do {
    Write-Host ''
    Write-Host 'Copy Direction:'
    Write-Host '[L] Local → Local'
    Write-Host '[B] Local → Blob'
    Write-Host '[D] Blob → Local'
    $direction = (Read-Host 'Enter choice').ToUpper()
} until ($direction -in @('L','B','D'))

# -------------------------
# Copy Mode
# -------------------------
do {
    Write-Host ''
    Write-Host 'Copy ["S"pecific File] or ["A"ll Files] in a Directory'
    $mode = (Read-Host 'Enter choice').ToUpper()
} until ($mode -in @('S','A'))

# -------------------------
# Blob Auth (if needed)
# -------------------------
$BlobBaseUrl = $null
$BlobSas     = $null
$BlobFullUrl = $null

if ($direction -in @('B','D')) {
    do {
        Write-Host ''
        Write-Host 'Blob Auth Type:'
        Write-Host '[F] Full SAS URL (URL includes token)'
        Write-Host '[S] URL and SAS Token Separate'
        $authMode = (Read-Host 'Enter choice').ToUpper()
    } until ($authMode -in @('F','S'))

    if ($authMode -eq 'F') {
        $BlobFullUrl = Read-Host 'Enter FULL Blob SAS URL'
    }
    else {
        $BlobBaseUrl = Read-Host 'Enter Blob URL (no token)'
        $BlobSas = Read-Host 'Enter SAS Token (starting with ?)'
    }
}

# -------------------------
# Source Selection
# -------------------------
$sourceItems = @()

if ($direction -ne 'D') {
    if ($mode -eq 'S') {
        $srcDir  = Read-Host 'Enter Source Directory'
        $file    = Read-Host 'Enter Filename'
        $path    = Join-Path $srcDir $file
        if (-not (Test-Path $path)) { Write-Error 'Source file not found'; exit }
        $sourceItems = Get-Item $path
    }
    else {
        $srcDir = Read-Host 'Enter Source Directory'
        if (-not (Test-Path $srcDir)) { Write-Error 'Directory not found'; exit }
        $sourceItems = Get-ChildItem $srcDir -File
    }
}
else {
    # Blob source
    if ($mode -eq 'S') {
        $blobPath = Read-Host 'Enter Blob Path (container/file)'
        $sourceItems = @($blobPath)
    }
    else {
        $blobPath = Read-Host 'Enter Blob Directory (container/path)'
        $sourceItems = @($blobPath)
    }
}

# -------------------------
# Destination (local)
# -------------------------
if ($direction -ne 'B') {
    $destFolder = Read-Host 'Enter Destination Folder'
    if (-not (Test-Path $destFolder)) {
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
    }
}

# -------------------------
# Prompt for Logging Folder
# -------------------------
$defaultLogDir = "$env:USERPROFILE\Documents\filecopytest_logs"
$logDirInput = Read-Host "Enter log folder path (Press Enter to use default: $defaultLogDir)"
if ([string]::IsNullOrWhiteSpace($logDirInput)) {
    $metricsDir = $defaultLogDir
} else {
    $metricsDir = $logDirInput
}
if (-not (Test-Path $metricsDir)) {
    try {
        New-Item -ItemType Directory -Path $metricsDir -Force | Out-Null
    } catch {
        Write-Error "Cannot create log folder at $metricsDir. Please check permissions."
        exit
    }
}

# -------------------------
# Ensure .azcopy log folder exists
# -------------------------
$azLogDir = "$env:USERPROFILE\.azcopy"
if (-not (Test-Path $azLogDir)) {
    New-Item -ItemType Directory -Path $azLogDir | Out-Null
}

# ============================================================
# COPY LOOP
# ============================================================
foreach ($item in $sourceItems) {

    $start = Get-Date
    $stamp = (Get-Date).ToString("HHmmss_yyyyMMdd")
    $metricsLog = Join-Path $metricsDir "${stamp}_azurecopy.csv"

    'Time,BytesTransferred,Percent,MBps,GBps,ETA' | Out-File $metricsLog -Encoding UTF8

    # Build source/destination paths
    if ($direction -eq 'L') {
        $src = "`"$($item.FullName)`""
        $dst = "`"$destFolder`""
        $totalBytes = $item.Length
    }
    elseif ($direction -eq 'B') {
        $src = "`"$($item.FullName)`""
        $dst = if ($authMode -eq 'F') { "`"$BlobFullUrl`"" }
               else { "`"$BlobBaseUrl/$($item.Name)$BlobSas`"" }
        $totalBytes = $item.Length
    }
    else {
        $src = if ($authMode -eq 'F') { "`"$BlobFullUrl`"" }
               else { "`"$BlobBaseUrl/$item$BlobSas`"" }
        $dst = "`"$destFolder`""
        $totalBytes = 1
    }

    Write-Host ''
    Write-Host "Starting transfer..." -ForegroundColor Cyan

    # -------------------------
    # Start AzCopy via call operator (&)
    # -------------------------
    $azArgs = @(
        'copy'
        $src
        $dst
        '--overwrite=true'
        '--log-level=INFO'
        '--output-type=text'
    )

    # Start AzCopy in background job so we can monitor metrics
    $job = Start-Job -ScriptBlock { param($exe, $args) & $exe @args } -ArgumentList $AzCopyExe, $azArgs

    $lastBytes = 0
    $lastTime  = Get-Date

    # -------------------------
    # 1-Second Metrics Loop
    # -------------------------
    do {
        Start-Sleep 1
        $now = Get-Date

        # Parse last 200 lines of latest AzCopy log
        $log = Get-ChildItem $azLogDir -Filter '*.log' |
               Sort-Object LastWriteTime -Descending |
               Select-Object -First 1

        if ($log) {
            $line = Get-Content $log.FullName -Tail 200 | Select-String 'BytesTransferred'
            if ($line -and $line.Line -match 'BytesTransferred:\s+(\d+)') {
                $bytes = [int64]$matches[1]
                $delta = $bytes - $lastBytes
                $sec   = ($now - $lastTime).TotalSeconds
                if ($sec -le 0) { continue }

                $mbps = [math]::Round(($delta / 1MB) / $sec, 2)
                $gbps = [math]::Round(($delta / 1GB) / $sec, 4)
                $pct  = if ($totalBytes -gt 1) { [math]::Round(($bytes / $totalBytes) * 100,2) } else { 0 }

                $avg = $bytes / ($now - $start).TotalSeconds
                $eta = if ($totalBytes -gt 1) { (New-TimeSpan -Seconds (($totalBytes - $bytes)/$avg)).ToString('hh\:mm\:ss') } else { 'N/A' }

                $ts = $now.ToString('yyyy-MM-dd HH:mm:ss')
                Write-Host "$ts | $pct% | $mbps MB/s | ETA $eta"

                "$ts,$bytes,$pct,$mbps,$gbps,$eta" | Out-File $metricsLog -Append -Encoding UTF8

                $lastBytes = $bytes
                $lastTime  = $now
            }
        }

    } while (Get-Job -Id $job.Id | Where-Object { $_.State -ne 'Completed' })

    # Cleanup background job
    Receive-Job -Id $job.Id | Out-Null
    Remove-Job -Id $job.Id

    Write-Host 'Transfer completed.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'All operations complete.' -ForegroundColor Cyan
