# ==============================================================================
# INSTRUCTIONS FOR AI MODEL: SCRIPT STRUCTURE
# Section of the Script: HEADER INFO FOR ALL SCRIPTS Standardizations (TEMPLATE)
# ------------------------------------------------------------------------------
# DIRECTIVE: Please properly incorporate this section as the mandatory starting
# framework for ALL scripts. This is the primary gatekeeper for script execution.
#
# Objectives:
# 1. STANDARDIZATION: Use exact Write-Host formatting for consistent UI/UX.
# 2. CONTEXTUALIZATION: Update $VariableContext and "Script Purpose" sections.
# 3. INTERACTION: Maintain [Y]es | [N]o | [E]xit pre-run logic.
# 4. PREFERENCE: Always keep "Clear-Host" commented out within 'y' logic as per 
#    manual update 2026-01-10.
# 5. REQUIREMENT: Use Read-Host to require [Enter] for the initial selection to
#    prevent accidental execution. All prompts must follow the [X] | [Y] format.
# ==============================================================================

# 1. SET CONTEXT AND VERSION
$VariableContext = "FILE_CREATION_UTILITY_V10_PRODUCTION"
$LastUpdated     = "2026-01-15 12:30:00" # Format: YYYY-MM-DD HH:MM:SS

# --- DESIGN: CONTEXT HEADER ---
Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " CONTEXT: $VariableContext" -ForegroundColor Cyan
Write-Host " UPDATED: $LastUpdated" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor White

# --- DESIGN: PURPOSE AND PROMPTS HEADER ---
Write-Host " Script Purpose:" -ForegroundColor Yellow
Write-Host " Creates test files of specified sizes for performance testing,"
Write-Host " file copy validation, and disk space management scenarios."
Write-Host " Utilizes parallel processing for optimal performance."
Write-Host ""
Write-Host " Input/Steps Required:" -ForegroundColor Yellow
Write-Host " 1. Choose destination folder (default or custom path)"
Write-Host " 2. Specify file sizes and metrics (MB or GB)"
Write-Host " 3. Monitor parallel creation with real-time progress"
Write-Host " 4. Review comprehensive summary report"
Write-Host "****************************************************" -ForegroundColor White

# --- INTERACTION: RUN/CLEAR/EXIT (Wait for Enter) ---
Write-Host "`nDo you want to clear script terminal before running?" -ForegroundColor White
$choice = Read-Host " [Y]es | [N]o | [E]xit"
$selection = $choice.ToLower()

switch ($selection) {
    'e' { 
        Write-Host "`nExiting script..." -ForegroundColor Red
        exit 
    }
    'y' { 
        # Clear-Host (Commented out per user preference 2026-01-10)
        Write-Host "Continuing with current terminal view..." -ForegroundColor Gray
    }
    'n' { 
        Write-Host "Proceeding..." -ForegroundColor Gray 
    }
    Default {
        Write-Host "`nInvalid selection. Exiting to prevent accidental execution." -ForegroundColor Red
        exit
    }
}

# ==============================================================================
# START MAIN SCRIPT LOGIC BELOW
# ==============================================================================
Write-Host "`n--- Execution Started ---" -ForegroundColor Green

# ==============================================================================
# SUMMARY REPORT SETUP
# ==============================================================================

$SuccessList = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$SkippedList = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$FailedList  = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$DefaultList = @()

function Show-ScriptSummary {
    param([string]$Title = "PROCESSING SUMMARY")

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "`n--- $Title ---" -ForegroundColor White
    Write-Host "Completed at: $timestamp" -ForegroundColor Gray
    Write-Host "Total Expected:   $($DefaultList.Count)" -ForegroundColor White
    Write-Host "Total Created:    $($SuccessList.Count)" -ForegroundColor Green
    Write-Host "Total Skipped:    $($SkippedList.Count)" -ForegroundColor Yellow
    Write-Host "Total Failed:     $($FailedList.Count)" -ForegroundColor Red

    if ($SuccessList.Count -gt 0) {
        foreach ($item in $SuccessList) { Write-Host " [+] Created: $item" -ForegroundColor Green }
    }
    if ($SkippedList.Count -gt 0) {
        foreach ($item in $SkippedList) { Write-Host " [!] Skipped: $item (Already Exists)" -ForegroundColor Yellow }
    }
    if ($FailedList.Count -gt 0) {
        foreach ($item in $FailedList) { Write-Host " [X] Failed: $item" -ForegroundColor Red }
    }

    $allProcessed = $SuccessList.ToArray() + $SkippedList.ToArray() + $FailedList.ToArray()
    $missedItems  = $DefaultList | Where-Object { $_ -notin $allProcessed }

    if ($missedItems.Count -gt 0) {
        Write-Host "Total Missed:    $($missedItems.Count)" -ForegroundColor Magenta
        foreach ($m in $missedItems) { Write-Host " [?] Missed: $m" -ForegroundColor Magenta }
    } else {
        Write-Host "Total Missed:    0" -ForegroundColor Gray
    }

    $StatusColor = if ($missedItems.Count -gt 0 -or $FailedList.Count -gt 0) { "Red" } else { "White" }
    Write-Host "--------------------------" -ForegroundColor $StatusColor
    Write-Host "Done.`n"
}

# ==============================================================================
# FOLDER SELECTION
# ==============================================================================

$defaultFolder = "$env:USERPROFILE\Documents\filecopytest_files"
Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " Default Path:" -ForegroundColor Yellow
Write-Host " $defaultFolder" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor White

Write-Host ""
$pathChoice = Read-Host " Destination: [D]efault | [C]ustom"
$pathSelection = $pathChoice.ToLower()

switch ($pathSelection) {
    'c' {
        $customPath = Read-Host " >> Enter full custom path"
        if (-not [IO.Path]::IsPathRooted($customPath)) {
            Write-Host "`nERROR: Please provide an absolute path (e.g., C:\MyFolder)" -ForegroundColor Red
            exit
        }
        $folder = $customPath
    }
    'd' {
        $folder = $defaultFolder
        Write-Host "Using default path..." -ForegroundColor Gray
    }
    Default {
        Write-Host "`nInvalid selection. Exiting to prevent accidental execution." -ForegroundColor Red
        exit
    }
}

if (-not (Test-Path $folder)) {
    Write-Host "`nCreating directory: $folder" -ForegroundColor Cyan
    try {
        New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null
        Write-Host "Directory created successfully." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to create directory: $_" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "`nUsing existing directory: $folder" -ForegroundColor Gray
}

# ==============================================================================
# FILE SIZE CONFIGURATION
# ==============================================================================

Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " File Size Configuration" -ForegroundColor Yellow
Write-Host "****************************************************" -ForegroundColor White
Write-Host ""
Write-Host " Enter file sizes separated by commas" -ForegroundColor Cyan
Write-Host " Examples:" -ForegroundColor Gray
Write-Host "   100, 500, 1024, 2048" -ForegroundColor Gray
Write-Host "   1, 5, 10, 50, 100" -ForegroundColor Gray
Write-Host ""

$sizeInput = Read-Host " >> Enter file sizes (numbers only, comma-separated)"

if ([string]::IsNullOrWhiteSpace($sizeInput)) {
    Write-Host "`nERROR: No sizes provided. Exiting." -ForegroundColor Red
    exit
}

Write-Host ""
$metricChoice = Read-Host " Metric: [M]B | [G]B"
$metric = $metricChoice.ToLower()

$multiplier = switch ($metric) {
    'm' { 1MB; 'MB' }
    'g' { 1GB; 'GB' }
    Default {
        Write-Host "`nInvalid metric selection. Exiting." -ForegroundColor Red
        exit
    }
}

$metricLabel = $multiplier[1]
$multiplier = $multiplier[0]

# Parse and validate sizes
$fileSizes = @()
$sizeInput -split ',' | ForEach-Object {
    $size = $_.Trim()
    if ($size -match '^\d+$') {
        $fileSizes += [int64]$size
    } else {
        Write-Host "Warning: Skipping invalid size: $size" -ForegroundColor Yellow
    }
}

if ($fileSizes.Count -eq 0) {
    Write-Host "`nERROR: No valid sizes provided. Exiting." -ForegroundColor Red
    exit
}

$fileSizes = $fileSizes | Sort-Object -Unique

# Ask how many of each size
Write-Host ""
$countInput = Read-Host " >> How many files per size? (Enter a number, default is 1)"
$fileCount = 1

if (-not [string]::IsNullOrWhiteSpace($countInput)) {
    if ($countInput -match '^\d+$' -and [int]$countInput -gt 0) {
        $fileCount = [int]$countInput
    } else {
        Write-Host "Warning: Invalid count, using default of 1" -ForegroundColor Yellow
    }
}

Write-Host "`nFiles to create:" -ForegroundColor Cyan
$fileSpecs = @()
foreach ($size in $fileSizes) {
    # Calculate size in KB for filename
    [int64]$sizeInKB = [int64]$size * ($multiplier / 1KB)
    
    for ($i = 1; $i -le $fileCount; $i++) {
        # Format: file_0000001024_0001.csv (size in KB 10 digits, iteration 4 digits)
        $paddedKB = $sizeInKB.ToString("D10")
        $paddedNum = $i.ToString("D4")
        $fileName = "file_$paddedKB`_$paddedNum.csv"
        
        Write-Host "  - $fileName ($size $metricLabel)" -ForegroundColor White
        
        $fileSpecs += @{
            FileName = $fileName
            Size = $size
            Metric = $metricLabel
            TargetBytes = [int64]$size * $multiplier
            SizeInKB = $sizeInKB
        }
        
        $DefaultList += "$folder\$fileName"
    }
}

# ==============================================================================
# DISK SPACE PRE-CHECK
# ==============================================================================

Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " Disk Space Verification" -ForegroundColor Yellow
Write-Host "****************************************************" -ForegroundColor White

$driveLetter = ([IO.Path]::GetPathRoot($folder)).Substring(0,1)
$drive = Get-PSDrive -Name $driveLetter
[int64]$totalRequiredBytes = ($fileSizes | Measure-Object -Sum).Sum * $multiplier * $fileCount

$requiredGB = [math]::Round($totalRequiredBytes / 1GB, 2)
$availableGB = [math]::Round($drive.Free / 1GB, 2)

Write-Host "Required Space:  $requiredGB GB" -ForegroundColor White
Write-Host "Available Space: $availableGB GB" -ForegroundColor $(if ($drive.Free -ge $totalRequiredBytes) { "Green" } else { "Red" })

if ($drive.Free -lt $totalRequiredBytes) {
    Write-Host "`nERROR: Insufficient disk space!" -ForegroundColor Red
    exit
}

Write-Host ""
$confirmChoice = Read-Host " Proceed with file creation? [Y]es | [N]o"
if ($confirmChoice.ToLower() -ne 'y') {
    Write-Host "`nOperation cancelled by user." -ForegroundColor Yellow
    exit
}

# ==============================================================================
# PARALLEL FILE CREATION ENGINE WITH COPY OPTIMIZATION
# ==============================================================================

Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " Initializing File Creation with Copy Optimization" -ForegroundColor Yellow
Write-Host "****************************************************" -ForegroundColor White

$ThrottleLimit = [Math]::Min(4, [Math]::Max(1, $env:NUMBER_OF_PROCESSORS))
$TotalFiles = $fileSpecs.Count
$UniqueFileSizes = $fileSizes.Count

Write-Host "Strategy: Create $UniqueFileSizes master file(s), then copy for duplicates" -ForegroundColor Cyan
Write-Host "Parallel Threads: $ThrottleLimit" -ForegroundColor Cyan
Write-Host "Total Files:      $TotalFiles" -ForegroundColor Cyan

$Encoding = [System.Text.Encoding]::UTF8

# ==============================================================================
# PHASE 1: CREATE MASTER FILES (One per unique size)
# ==============================================================================

Write-Host "`n--- PHASE 1: Creating Master Files ---" -ForegroundColor Green
Write-Host "Creating one file per size...`n" -ForegroundColor Gray

$masterFiles = @{}
$phaseStartTime = Get-Date

$RunspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
$RunspacePool.Open()

$Jobs = @()

foreach ($size in $fileSizes) {
    [int64]$sizeInKB = [int64]$size * ($multiplier / 1KB)
    [int64]$targetBytes = [int64]$size * $multiplier
    
    $paddedKB = $sizeInKB.ToString("D10")
    $masterFileName = "file_$paddedKB`_master.csv"
    $masterFiles[$size] = "$folder\$masterFileName"
    
    if ($targetBytes -lt 10MB) { $ChunkSize = 4MB }
    elseif ($targetBytes -lt 1GB) { $ChunkSize = 8MB }
    else { $ChunkSize = 16MB }

    $ps = [powershell]::Create()
    $ps.RunspacePool = $RunspacePool

    $ps.AddScript({
        param($fileName, $folder, $targetBytes, $ChunkSize, $Encoding)

        $file = "$folder\$fileName"
        $fs = $null

        try {
            if (Test-Path $file) {
                return @{ Status = 'Exists'; File = $fileName }
            }

            $lines = @(
                "Column1,Column2,Column3,Column4,Column5`r`n",
                "Value1,Value2,Value3,Value4,Value5`r`n",
                "Data1,Data2,Data3,Data4,Data5`r`n",
                "Record1,Record2,Record3,Record4,Record5`r`n",
                "Entry1,Entry2,Entry3,Entry4,Entry5`r`n"
            )
            
            $buffer = New-Object byte[] $ChunkSize
            $lineIndex = 0
            for ($i = 0; $i -lt $ChunkSize; $i++) {
                $currentLine = $lines[$lineIndex % $lines.Count]
                $lineBytes = $Encoding.GetBytes($currentLine)
                $buffer[$i] = $lineBytes[$i % $lineBytes.Length]
                if (($i + 1) % $lineBytes.Length -eq 0) { $lineIndex++ }
            }

            $fs = [IO.File]::Open($file, 'Create', 'Write', 'None')
            [int64]$written = 0

            while ($written -lt $targetBytes) {
                [int64]$remaining = $targetBytes - $written
                [int]$toWrite = if ($remaining -gt $ChunkSize) { $ChunkSize } else { [int]$remaining }
                
                $fs.Write($buffer, 0, $toWrite)
                $written += $toWrite
            }

            $fs.Close()
            $fs.Dispose()
            $fs = $null

            $actualSize = (Get-Item $file -ErrorAction Stop).Length
            if ($actualSize -ne $targetBytes) {
                throw "Size mismatch. Expected: $targetBytes, Actual: $actualSize"
            }

            if ($targetBytes -gt 5GB) {
                $buffer = $null
                [System.GC]::Collect()
            }

            return @{ Status = 'Success'; File = $fileName }

        } catch {
            return @{ Status = 'Failed'; File = $fileName; Error = $_.Exception.Message }
        } finally {
            if ($fs) {
                $fs.Close()
                $fs.Dispose()
            }
        }
    }).AddArgument($masterFileName).AddArgument($folder).AddArgument($targetBytes).AddArgument($ChunkSize).AddArgument($Encoding)

    $Jobs += @{
        PowerShell = $ps
        Handle     = $ps.BeginInvoke()
        FileName   = $masterFileName
        Size       = $size
        TargetBytes = $targetBytes
    }
}

# Monitor master file creation
$lastReported = @{}
$fileStarted = @{}
foreach ($job in $Jobs) {
    $lastReported[$job.FileName] = 0
    $fileStarted[$job.FileName] = $false
}

while ($Jobs | Where-Object { -not $_.Handle.IsCompleted }) {
    Start-Sleep -Seconds 1
    
    foreach ($job in $Jobs) {
        $file = "$folder\$($job.FileName)"
        
        if (Test-Path $file) {
            try {
                if (-not $fileStarted[$job.FileName]) {
                    $targetMB = [math]::Round($job.TargetBytes / 1MB, 2)
                    Write-Host "  $($job.FileName) : Starting ($targetMB MB target)..." -ForegroundColor Cyan
                    $fileStarted[$job.FileName] = $true
                }
                
                $currentSize = (Get-Item $file).Length
                $percent = [Math]::Floor(($currentSize / $job.TargetBytes) * 100)
                
                if ($percent -ge ($lastReported[$job.FileName] + 10) -and $percent -lt 100) {
                    $sizeMB = [math]::Round($currentSize / 1MB, 2)
                    $targetMB = [math]::Round($job.TargetBytes / 1MB, 2)
                    Write-Host "  $($job.FileName) : $percent% ($sizeMB MB / $targetMB MB)" -ForegroundColor Yellow
                    $lastReported[$job.FileName] = $percent
                }
            } catch { }
        }
    }
}

# Collect master file results
Write-Host "`n--- Master Files Created ---" -ForegroundColor Green
$masterSuccess = 0

foreach ($job in $Jobs) {
    try {
        $result = $job.PowerShell.EndInvoke($job.Handle)
        
        if ($result) {
            switch ($result.Status) {
                'Success' {
                    $file = "$folder\$($result.File)"
                    $finalSize = [math]::Round((Get-Item $file).Length / 1MB, 2)
                    Write-Host "  $($result.File) : COMPLETE ($finalSize MB)" -ForegroundColor Green
                    $masterSuccess++
                }
                'Exists' {
                    Write-Host "  $($result.File) : Already exists, will use for copying" -ForegroundColor Yellow
                    $masterSuccess++
                }
                'Failed' {
                    Write-Host "  $($result.File) : FAILED - $($result.Error)" -ForegroundColor Red
                }
            }
        }
    } catch {
        Write-Host "  Job Error: $_" -ForegroundColor Red
    }
    $job.PowerShell.Dispose()
}

$RunspacePool.Close()
$RunspacePool.Dispose()

$phaseElapsed = (Get-Date) - $phaseStartTime
Write-Host "`nPhase 1 completed in $([math]::Round($phaseElapsed.TotalSeconds, 2)) seconds" -ForegroundColor Cyan

if ($masterSuccess -ne $UniqueFileSizes) {
    Write-Host "`nERROR: Not all master files were created successfully. Aborting copy phase." -ForegroundColor Red
    exit
}

# ==============================================================================
# PHASE 2: COPY FILES (Fast file duplication)
# ==============================================================================

if ($fileCount -gt 1) {
    Write-Host "`n--- PHASE 2: Copying Files ---" -ForegroundColor Green
    Write-Host "Creating $($TotalFiles - $UniqueFileSizes) copies...`n" -ForegroundColor Gray

    $copyStartTime = Get-Date
    $copyCount = 0
    $copyErrors = 0

    foreach ($size in $fileSizes) {
        $masterFile = $masterFiles[$size]
        [int64]$sizeInKB = [int64]$size * ($multiplier / 1KB)
        $paddedKB = $sizeInKB.ToString("D10")
        
        Write-Host "  Copying $size $metricLabel files..." -ForegroundColor Cyan
        
        for ($i = 1; $i -le $fileCount; $i++) {
            $paddedNum = $i.ToString("D4")
            $targetFile = "$folder\file_$paddedKB`_$paddedNum.csv"
            
            try {
                if (Test-Path $targetFile) {
                    $SkippedList.Add($targetFile)
                    Write-Host "    file_$paddedKB`_$paddedNum.csv : SKIPPED (exists)" -ForegroundColor Yellow
                } else {
                    Copy-Item -Path $masterFile -Destination $targetFile -Force -ErrorAction Stop
                    $SuccessList.Add($targetFile)
                    $copyCount++
                    
                    # Show progress every 50 copies or for small batches
                    if ($copyCount % 50 -eq 0 -or $fileCount -le 20) {
                        Write-Host "    file_$paddedKB`_$paddedNum.csv : COPIED" -ForegroundColor Green
                    }
                }
            } catch {
                $FailedList.Add("$targetFile - Copy Error: $_")
                $copyErrors++
                Write-Host "    file_$paddedKB`_$paddedNum.csv : FAILED - $_" -ForegroundColor Red
            }
        }
        
        # Remove master file after copying
        try {
            Remove-Item -Path $masterFile -Force -ErrorAction Stop
            Write-Host "  Cleaned up master file" -ForegroundColor Gray
        } catch {
            Write-Host "  Warning: Could not remove master file: $_" -ForegroundColor Yellow
        }
    }

    $copyElapsed = (Get-Date) - $copyStartTime
    Write-Host "`nPhase 2 completed in $([math]::Round($copyElapsed.TotalSeconds, 2)) seconds" -ForegroundColor Cyan
    Write-Host "Copy rate: $([math]::Round($copyCount / $copyElapsed.TotalSeconds, 2)) files/second" -ForegroundColor Cyan

} else {
    # Only 1 file per size - just rename master files
    Write-Host "`n--- Renaming Master Files ---" -ForegroundColor Green
    
    foreach ($size in $fileSizes) {
        $masterFile = $masterFiles[$size]
        [int64]$sizeInKB = [int64]$size * ($multiplier / 1KB)
        $paddedKB = $sizeInKB.ToString("D10")
        $targetFile = "$folder\file_$paddedKB`_0001.csv"
        
        try {
            Move-Item -Path $masterFile -Destination $targetFile -Force -ErrorAction Stop
            $SuccessList.Add($targetFile)
            Write-Host "  Renamed to file_$paddedKB`_0001.csv" -ForegroundColor Green
        } catch {
            $FailedList.Add("$targetFile - Rename Error: $_")
            Write-Host "  Failed to rename: $_" -ForegroundColor Red
        }
    }
}

$elapsed = (Get-Date) - $startTime
$elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 2)
$elapsedSeconds = [math]::Round($elapsed.TotalSeconds, 2)

Write-Host "`n****************************************************" -ForegroundColor White
Write-Host "Total Execution Time: $elapsedMinutes minutes ($elapsedSeconds seconds)" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor White

# ==============================================================================
# FINAL SUMMARY REPORT
# ==============================================================================

Show-ScriptSummary "FILE CREATION RESULTS"