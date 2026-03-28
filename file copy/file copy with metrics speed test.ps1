#requires -Version 5.1
# ==============================================================================
# SCRIPT NAME: File Copy / Move Utility
# VERSION: 2.0
# LAST UPDATED: 2026-03-28
# AUTHOR: Kevin Ludwig / ChatGPT Collaboration
# CONTEXT: FILE_TRANSFER_UTILITY_V2
# ==============================================================================

# ==============================================================================
# DESCRIPTION
# ------------------------------------------------------------------------------
# High-performance PowerShell utility for copying or moving files with:
# - Real-time progress monitoring (MB/s, ETA, Percent)
# - Structured logging (TXT, CSV, JSON, ALL)
# - Flexible file selection (Individual, Multiple, All)
# - Wildcard file matching support
# - Parallel processing (1–64 workers)
# - Overwrite controls with [A]ll option
# - Clean console output (mode-aware)
# - UTC-based daily log rotation
#
# Designed for:
# - File transfer testing
# - Performance benchmarking
# - Bulk operations
# - Operational / production tooling
# ==============================================================================

# ==============================================================================
# FEATURES
# ------------------------------------------------------------------------------
# ✔ Copy or Move operations
# ✔ Individual file selection
# ✔ Multiple file selection (wildcard + indexed selection)
# ✔ All files in directory
# ✔ Parallel file processing (configurable threads)
# ✔ Structured logging with consistent schema
# ✔ Real-time throughput metrics
# ✔ CopyId (GUID) tracking for each file
# ✔ Clean output modes (Screen, Log, Both)
# ==============================================================================

# ==============================================================================
# PROMPT SYSTEM STANDARD
# ------------------------------------------------------------------------------
# All prompts follow:
# - Bracket format: [X]Option | [Y]Option
# - Single-letter input + Enter required
# - Case-insensitive handling
#
# Example:
# Action: [C]ontinue | [Q]uit
# ==============================================================================

# ==============================================================================
# LOGGING BEHAVIOR
# ------------------------------------------------------------------------------
# - Logs are created per UTC day
# - One file per day per log type
# - Existing logs are appended
# - Supports:
#     TXT  -> Human readable
#     CSV  -> Structured tabular
#     JSON -> Structured object (NDJSON format)
#
# Log fields include:
# Timestamp, CopyId, Status, FileName, Paths,
# File sizes, Throughput, ETA, Duration, Errors
# ==============================================================================

# ==============================================================================
# OUTPUT BEHAVIOR
# ------------------------------------------------------------------------------
# Individual Mode:
#   - Full detail (header + summary + progress)
#
# Multiple / All Modes:
#   - Progress only during execution
#   - Final summary only (reduced noise)
# ==============================================================================

# ==============================================================================
# NOTES
# ------------------------------------------------------------------------------
# - Parallel processing is whole-file based (no file splitting)
# - Optimized for throughput and observability
# - Designed to be safe for production usage
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# Script Metadata
# ------------------------------------------------------------
$script:ScriptName = if ($MyInvocation.MyCommand.Name) {
    [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
} else {
    'FileCopySpeedTest'
}

# ------------------------------------------------------------
# Global Logging State
# ------------------------------------------------------------
$script:LoggingEnabled   = $false
$script:LogFolder        = $null
$script:LogBaseName      = 'copy_file_test'
$script:LogTXTPath       = $null
$script:LogCSVPath       = $null
$script:LogJSONPath      = $null
$script:LogDay           = $null
$script:LogType          = $null
$script:LogPathDisplayed = $false
$script:LogToConsole     = $true
$script:OutputMode       = 'both'

# ------------------------------------------------------------
# Script Run State
# ------------------------------------------------------------
$script:RunStartTime        = $null
$script:RunEndTime          = $null
$script:OverwriteAllMode    = $false

# ------------------------------------------------------------
# Summary Arrays
# ------------------------------------------------------------
$script:SuccessList = @()
$script:SkippedList = @()
$script:DefaultList = @()
$script:FailedList  = @()

# ------------------------------------------------------------
# Shared Log Field Order
# ------------------------------------------------------------
$script:LogFieldOrder = @(
    'Timestamp',
    'CopyId',
    'EventType',
    'Status',
    'CopyMethod',
    'ParallelCount',
    'WorkerId',
    'FileName',
    'SourcePath',
    'DestinationPath',
    'FileSizeBytes',
    'FileSizeKB',
    'FileSizeMB',
    'FileSizeGB',
    'FileSizeTB',
    'BytesTransferred',
    'Percent',
    'MBps',
    'GBps',
    'ETA',
    'StartTime',
    'EndTime',
    'TotalTime',
    'AverageSpeedMBps',
    'LogFile',
    'Message',
    'ErrorMessage'
)

# ------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------
function Read-YesNo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    while ($true) {
        $inputValue = (Read-Host "$Prompt [Y]es | [N]o").Trim().ToLower()

        switch ($inputValue) {
            'y' { return $true }
            'n' { return $false }
            default { }
        }
    }
}

function Read-OverwriteChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )

    while ($true) {
        $inputValue = (Read-Host "Overwrite file '$FileName'? [Y]es | [N]o |OR| [A]ll").Trim().ToLower()

        switch ($inputValue) {
            'y' { return 'Y' }
            'n' { return 'N' }
            'a' { return 'A' }
            default { }
        }
    }
}

function Read-ActionType {
    [CmdletBinding()]
    param()

    while ($true) {
        $raw = (Read-Host "Please Select: [C]opy | [M]ove").Trim().ToLower()

        switch ($raw) {
            'c' { return 'Copy' }
            'm' { return 'Move' }
            default { }
        }
    }
}

function Read-SourceMode {
    [CmdletBinding()]
    param()

    while ($true) {
        Write-Host ""
        $raw = (Read-Host "Copy Mode: [I]ndividual File | [M]ultiple Files | [A]ll Files in Directory").Trim().ToLower()

        switch ($raw) {
            'i' { return 'I' }
            'm' { return 'M' }
            'a' { return 'A' }
            default { }
        }
    }
}

function Read-IndividualFileMode {
    [CmdletBinding()]
    param()

    while ($true) {
        Write-Host ""
        $raw = (Read-Host "Please Select: [K]now File Name |OR| [L]ist Files in Directory").Trim().ToLower()

        switch ($raw) {
            'k' { return 'K' }
            'l' { return 'L' }
            default { }
        }
    }
}

function Read-MultipleFileMode {
    [CmdletBinding()]
    param()

    while ($true) {
        Write-Host ""
        $raw = (Read-Host "Please Select: [K]now File(s) Name w/Wildcard Use |OR| [L]ist Files in Directory").Trim().ToLower()

        switch ($raw) {
            'k' { return 'K' }
            'l' { return 'L' }
            default { }
        }
    }
}

function Read-LogType {
    [CmdletBinding()]
    param()

    while ($true) {
        $raw = (Read-Host "Log Type: [T]XT | [C]SV | [J]SON | [A]ll").Trim().ToLower()
        switch ($raw) {
            't' { return 'txt' }
            'c' { return 'csv' }
            'j' { return 'json' }
            'a' { return 'all' }
            default { }
        }
    }
}

function Read-OutputMode {
    [CmdletBinding()]
    param()

    while ($true) {
        $raw = (Read-Host "Output Mode: [S]creen | [L]og | [B]oth").Trim().ToLower()
        switch ($raw) {
            's' { return 'screen' }
            'l' { return 'log' }
            'b' { return 'both' }
            default { }
        }
    }
}

function Read-CopyMethod {
    [CmdletBinding()]
    param()

    while ($true) {
        $raw = (Read-Host "Copy Method: [S]erial | [P]arallel").Trim().ToLower()
        switch ($raw) {
            's' { return 'Serial' }
            'p' { return 'Parallel' }
            default { }
        }
    }
}

function Read-ParallelCount {
    [CmdletBinding()]
    param(
        [int]$Default = 4,
        [int]$Min = 1,
        [int]$Max = 64
    )

    while ($true) {
        $raw = Read-Host "Enter Parallel Copy Count [$Min-$Max] (Default: $Default)"
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $Default
        }

        $parsed = 0
        if ([int]::TryParse($raw, [ref]$parsed)) {
            if ($parsed -ge $Min -and $parsed -le $Max) {
                return $parsed
            }
        }
    }
}

function Read-LogFolderMode {
    [CmdletBinding()]
    param()

    while ($true) {
        $raw = (Read-Host "Log Folder: [D]efault | [C]ustom").Trim().ToLower()
        switch ($raw) {
            'd' { return 'default' }
            'c' { return 'custom' }
            default { }
        }
    }
}

function Get-Timestamp {
    [CmdletBinding()]
    param()

    Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
}

function Get-UtcNow {
    [CmdletBinding()]
    param()

    [DateTime]::UtcNow
}

function Get-UtcDayStamp {
    [CmdletBinding()]
    param()

    (Get-UtcNow).ToString('yyyyMMdd')
}

function Get-ProgressIntervalSeconds {
    [CmdletBinding()]
    param()

    return 0.25
}

function Convert-ToFlatString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return '' }

    if ($Value -is [System.TimeSpan]) {
        return $Value.ToString()
    }

    if ($Value -is [System.DateTime]) {
        return $Value.ToString('yyyy-MM-dd HH:mm:ss')
    }

    $text = [string]$Value
    $text = $text -replace '[\r\n]+', ' '
    $text = $text.Trim()
    return $text
}

function Get-DisplayLogPath {
    [CmdletBinding()]
    param()

    if (-not $script:LoggingEnabled) {
        return 'Logging Disabled'
    }

    switch ($script:LogType) {
        'txt'  { return $script:LogTXTPath }
        'csv'  { return $script:LogCSVPath }
        'json' { return $script:LogJSONPath }
        'all'  { return ($script:LogTXTPath, $script:LogCSVPath, $script:LogJSONPath) -join '; ' }
        default { return 'Logging Disabled' }
    }
}

function Get-FileSizeInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )

    [PSCustomObject]@{
        Bytes = $Bytes
        KB    = [math]::Round($Bytes / 1KB, 2)
        MB    = [math]::Round($Bytes / 1MB, 2)
        GB    = [math]::Round($Bytes / 1GB, 2)
        TB    = [math]::Round($Bytes / 1TB, 4)
    }
}

function New-OrderedLogRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Row
    )

    $ordered = [ordered]@{}
    foreach ($field in $script:LogFieldOrder) {
        if ($Row.ContainsKey($field)) {
            $ordered[$field] = Convert-ToFlatString $Row[$field]
        }
        else {
            $ordered[$field] = ''
        }
    }

    return $ordered
}

function Get-EventType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ActionType
    )

    if ($ActionType -eq 'Move') { return 'FileMove' }
    return 'FileCopy'
}

function Get-ActionPresentParticiple {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ActionType
    )

    if ($ActionType -eq 'Move') { return 'Moving' }
    return 'Copying'
}

function Get-ActionSummaryTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ActionType
    )

    if ($ActionType -eq 'Move') { return 'MOVE SUMMARY' }
    return 'COPY SUMMARY'
}

function Show-CopyHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [pscustomobject]$SizeInfo,

        [Parameter(Mandatory)]
        [string]$LogDisplay,

        [Parameter(Mandatory)]
        [string]$ActionType
    )

    Write-Host ''
    Write-Host ("{0}: {1}" -f (Get-ActionPresentParticiple -ActionType $ActionType), $FileName) -ForegroundColor Cyan
    Write-Host "Size   : Bytes=$($SizeInfo.Bytes) | KB=$($SizeInfo.KB) | MB=$($SizeInfo.MB) | GB=$($SizeInfo.GB) | TB=$($SizeInfo.TB)"
    Write-Host "Log    : $LogDisplay"
    Write-Host '-------------------------------------------------------------'
}

function Get-CopySummaryText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [pscustomobject]$SizeInfo,

        [Parameter(Mandatory)]
        [datetime]$StartTime,

        [Parameter(Mandatory)]
        [datetime]$EndTime,

        [Parameter(Mandatory)]
        [timespan]$TotalTime,

        [Parameter(Mandatory)]
        [double]$AverageSpeedMBps,

        [Parameter(Mandatory)]
        [string]$CopyId,

        [Parameter(Mandatory)]
        [string]$ActionType
    )

@"
================ $(Get-ActionSummaryTitle -ActionType $ActionType) ================
File            : $FileName
File Size Bytes : $($SizeInfo.Bytes)
File Size KB    : $($SizeInfo.KB)
File Size MB    : $($SizeInfo.MB)
File Size GB    : $($SizeInfo.GB)
File Size TB    : $($SizeInfo.TB)
Start Time      : $StartTime
End Time        : $EndTime
Total Time      : $TotalTime
Average Speed   : $AverageSpeedMBps MB/s
Copy ID         : $CopyId
=============================================
"@
}

function Show-SelectedFilesForConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$Files
    )

    Write-Host ""
    Write-Host "Selected Files:" -ForegroundColor Cyan
    foreach ($file in $Files) {
        Write-Host $file.Name
    }
}

function Select-FileFromDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$Files
    )

    if (-not $Files -or $Files.Count -eq 0) {
        throw 'No files found in source directory.'
    }

    Write-Host ""
    Write-Host "Files in Directory:" -ForegroundColor Cyan

    for ($i = 0; $i -lt $Files.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $Files[$i].Name)
    }

    while ($true) {
        $raw = Read-Host "Enter File Number"
        $selection = 0

        if ([int]::TryParse($raw, [ref]$selection)) {
            if ($selection -ge 1 -and $selection -le $Files.Count) {
                return $Files[$selection - 1]
            }
        }
    }
}

function Select-MultipleFilesFromDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$Files
    )

    if (-not $Files -or $Files.Count -eq 0) {
        throw 'No files found in source directory.'
    }

    Write-Host ""
    Write-Host "Files in Directory:" -ForegroundColor Cyan

    for ($i = 0; $i -lt $Files.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $Files[$i].Name)
    }

    while ($true) {
        $raw = Read-Host "Enter File Numbers (comma separated)"
        $parts = @($raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $selectedIndexes = New-Object System.Collections.Generic.List[int]
        $isValid = $true

        foreach ($part in $parts) {
            $n = 0
            if (-not [int]::TryParse($part, [ref]$n)) {
                $isValid = $false
                break
            }

            if ($n -lt 1 -or $n -gt $Files.Count) {
                $isValid = $false
                break
            }

            if (-not $selectedIndexes.Contains($n)) {
                $selectedIndexes.Add($n) | Out-Null
            }
        }

        if ($isValid -and $selectedIndexes.Count -gt 0) {
            $selectedFiles = @()
            foreach ($idx in ($selectedIndexes | Sort-Object)) {
                $selectedFiles += $Files[$idx - 1]
            }
            return $selectedFiles
        }
    }
}

function Resolve-IndividualFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir
    )

    $fileMode = Read-IndividualFileMode

    if ($fileMode -eq 'K') {
        $fileName = Read-Host 'Enter Filename'
        $fullPath = Join-Path $SourceDir $fileName

        if (Test-Path $fullPath) {
            return (Get-Item $fullPath)
        }

        $matches = @(Get-ChildItem -Path $SourceDir -File | Where-Object {
            $_.BaseName -eq $fileName
        })

        if ($matches.Count -eq 1) {
            return $matches[0]
        }

        if ($matches.Count -gt 1) {
            Write-Host ""
            Write-Host "Multiple files matched that base name:" -ForegroundColor Yellow
            return (Select-FileFromDirectory -Files $matches)
        }

        throw 'Source file does not exist.'
    }

    $files = @(Get-ChildItem -Path $SourceDir -File)
    return (Select-FileFromDirectory -Files $files)
}

function Resolve-MultipleFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir
    )

    while ($true) {
        $fileMode = Read-MultipleFileMode

        if ($fileMode -eq 'K') {
            $pattern = Read-Host 'Enter File Name or Wildcard Pattern'

            $matches = @()

            if ($pattern.Contains('*') -or $pattern.Contains('?')) {
                $matches = @(Get-ChildItem -Path $SourceDir -File | Where-Object { $_.Name -like $pattern })
            }
            else {
                $exactPath = Join-Path $SourceDir $pattern
                if (Test-Path $exactPath) {
                    $matches = @((Get-Item $exactPath))
                }
                else {
                    $matches = @(Get-ChildItem -Path $SourceDir -File | Where-Object {
                        $_.BaseName -eq $pattern
                    })
                }
            }

            if ($matches.Count -eq 0) {
                throw 'No files matched the provided file name or wildcard pattern.'
            }

            Show-SelectedFilesForConfirmation -Files $matches
            $confirm = Read-YesNo "Confirm copy/move list?"
            if ($confirm) {
                return @($matches)
            }

            continue
        }

        $files = @(Get-ChildItem -Path $SourceDir -File)
        $selectedFiles = @(Select-MultipleFilesFromDirectory -Files $files)

        Show-SelectedFilesForConfirmation -Files $selectedFiles
        $confirm = Read-YesNo "Confirm copy/move list?"
        if ($confirm) {
            return $selectedFiles
        }
    }
}

# ------------------------------------------------------------
# Logging File Management
# ------------------------------------------------------------
function New-LogFiles {
    [CmdletBinding()]
    param()

    if (-not $script:LoggingEnabled) { return }

    if (-not (Test-Path -Path $script:LogFolder)) {
        New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
    }

    $utcDay = Get-UtcDayStamp
    $script:LogDay = $utcDay

    if ($script:LogType -eq 'txt' -or $script:LogType -eq 'all') {
        $script:LogTXTPath = Join-Path $script:LogFolder ("{0}_{1}.txt" -f $script:LogBaseName, $utcDay)

        if (-not (Test-Path $script:LogTXTPath)) {
            Add-Content -Path $script:LogTXTPath -Value ('=' * 70)
            Add-Content -Path $script:LogTXTPath -Value ('Script Name : {0}' -f $script:ScriptName)
            Add-Content -Path $script:LogTXTPath -Value ('Started UTC : {0}' -f (Get-UtcNow).ToString('yyyy-MM-dd HH:mm:ss'))
            Add-Content -Path $script:LogTXTPath -Value ('Computer    : {0}' -f $env:COMPUTERNAME)
            Add-Content -Path $script:LogTXTPath -Value ('User        : {0}' -f $env:USERNAME)
            Add-Content -Path $script:LogTXTPath -Value ('UTC Day     : {0}' -f $utcDay)
            Add-Content -Path $script:LogTXTPath -Value ('=' * 70)
            Add-Content -Path $script:LogTXTPath -Value ''
        }
    }

    if ($script:LogType -eq 'csv' -or $script:LogType -eq 'all') {
        $script:LogCSVPath = Join-Path $script:LogFolder ("{0}_{1}.csv" -f $script:LogBaseName, $utcDay)
    }

    if ($script:LogType -eq 'json' -or $script:LogType -eq 'all') {
        $script:LogJSONPath = Join-Path $script:LogFolder ("{0}_{1}.json" -f $script:LogBaseName, $utcDay)
    }
}

function Ensure-LogFiles {
    [CmdletBinding()]
    param()

    if (-not $script:LoggingEnabled) { return }

    $utcDay = Get-UtcDayStamp

    $needsNewFiles =
        (-not $script:LogDay) -or
        ($script:LogDay -ne $utcDay) -or
        (($script:LogType -eq 'txt'  -or $script:LogType -eq 'all') -and ((-not $script:LogTXTPath)  -or ($script:LogTXTPath  -notmatch "_$utcDay\.txt$"))) -or
        (($script:LogType -eq 'csv'  -or $script:LogType -eq 'all') -and ((-not $script:LogCSVPath)  -or ($script:LogCSVPath  -notmatch "_$utcDay\.csv$"))) -or
        (($script:LogType -eq 'json' -or $script:LogType -eq 'all') -and ((-not $script:LogJSONPath) -or ($script:LogJSONPath -notmatch "_$utcDay\.json$")))

    if ($needsNewFiles) {
        $script:LogTXTPath = $null
        $script:LogCSVPath = $null
        $script:LogJSONPath = $null
        New-LogFiles
    }

    if (-not $script:LogPathDisplayed -and $script:LogToConsole) {
        Write-Host ('Logging Enabled -> {0}' -f (Get-DisplayLogPath)) -ForegroundColor Cyan
        $script:LogPathDisplayed = $true
    }
}

# ------------------------------------------------------------
# Logging Writers
# ------------------------------------------------------------
function Write-StructuredTextLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    if (-not $script:LoggingEnabled) { return }

    Ensure-LogFiles
    if (-not $script:LogTXTPath) { return }

    $orderedData = New-OrderedLogRow -Row $Data

    $pairs = foreach ($field in $script:LogFieldOrder) {
        '{0}={1}' -f $field, $orderedData[$field]
    }

    Add-Content -Path $script:LogTXTPath -Value (($pairs -join ' | '))
}

function Write-StructuredCsvLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Row
    )

    if (-not $script:LoggingEnabled) { return }

    Ensure-LogFiles
    if (-not $script:LogCSVPath) { return }

    $orderedRow = New-OrderedLogRow -Row $Row
    $obj = [PSCustomObject]$orderedRow

    if (-not (Test-Path -Path $script:LogCSVPath)) {
        $obj | Export-Csv -Path $script:LogCSVPath -NoTypeInformation
        return
    }

    $fileInfo = Get-Item -Path $script:LogCSVPath -ErrorAction SilentlyContinue
    if ($fileInfo -and $fileInfo.Length -eq 0) {
        $obj | Export-Csv -Path $script:LogCSVPath -NoTypeInformation
    }
    else {
        $obj | Export-Csv -Path $script:LogCSVPath -NoTypeInformation -Append
    }
}

function Write-StructuredJsonLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Row
    )

    if (-not $script:LoggingEnabled) { return }

    Ensure-LogFiles
    if (-not $script:LogJSONPath) { return }

    $orderedObject = New-OrderedLogRow -Row $Row
    $jsonLine = ($orderedObject | ConvertTo-Json -Compress -Depth 5)
    Add-Content -Path $script:LogJSONPath -Value $jsonLine
}

function Write-LogEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Row
    )

    if (-not $script:LoggingEnabled) { return }

    Ensure-LogFiles

    if (-not $Row.ContainsKey('Timestamp')) {
        $Row.Timestamp = Get-Timestamp
    }

    $Row.LogFile = Get-DisplayLogPath

    if ($script:LogType -eq 'txt' -or $script:LogType -eq 'all') {
        Write-StructuredTextLog -Data $Row
    }

    if ($script:LogType -eq 'csv' -or $script:LogType -eq 'all') {
        Write-StructuredCsvLog -Row $Row
    }

    if ($script:LogType -eq 'json' -or $script:LogType -eq 'all') {
        Write-StructuredJsonLog -Row $Row
    }
}

function Initialize-Logging {
    [CmdletBinding()]
    param(
        [string]$DefaultLogFolder = (Join-Path -Path $env:USERPROFILE -ChildPath 'Documents\filecopytest_logs')
    )

    $script:OutputMode = Read-OutputMode

    switch ($script:OutputMode) {
        'screen' {
            $script:LogToConsole   = $true
            $script:LoggingEnabled = $false
            Write-Host 'Screen-only mode selected. File logging disabled.' -ForegroundColor Yellow
            return
        }
        'log' {
            $script:LogToConsole = $false
        }
        'both' {
            $script:LogToConsole = $true
        }
    }

    $script:LoggingEnabled = Read-YesNo "Enable file logging?"
    if (-not $script:LoggingEnabled) {
        Write-Host 'File logging disabled for this run.' -ForegroundColor Yellow
        return
    }

    $script:LogType = Read-LogType

    Write-Host ""
    Write-Host "Default Log Folder: $DefaultLogFolder" -ForegroundColor DarkGray
    $logFolderMode = Read-LogFolderMode

    if ($logFolderMode -eq 'default') {
        $script:LogFolder = $DefaultLogFolder
    }
    else {
        $script:LogFolder = Read-Host 'Enter full folder path for log files'
    }

    $script:LogPathDisplayed = $false
    Ensure-LogFiles
}

# ------------------------------------------------------------
# Summary Function
# ------------------------------------------------------------
function Show-ScriptSummary {
    param(
        [string]$Title = "FILE COPY RESULTS",
        [string]$ActionType = "Copy"
    )

    $expectedItems = @($script:DefaultList)
    $copiedItems   = @($script:SuccessList)
    $skippedItems  = @($script:SkippedList)
    $failedItems   = @($script:FailedList)
    $allProcessed  = @($copiedItems + $skippedItems + $failedItems)
    $missedItems   = @($expectedItems | Where-Object { $_ -notin $allProcessed })

    $copyStartTime = if ($script:RunStartTime) { $script:RunStartTime } else { '' }
    $copyEndTime   = if ($script:RunEndTime)   { $script:RunEndTime } else { '' }
    $copyDuration  = if ($script:RunStartTime -and $script:RunEndTime) { $script:RunEndTime - $script:RunStartTime } else { '' }

    Write-Host "`n--- $Title ---" -ForegroundColor Blue
    Write-Host "Copy Start Time:  $copyStartTime" -ForegroundColor White
    Write-Host "Copy End Time:    $copyEndTime" -ForegroundColor White
    Write-Host "Copy Duration:    $copyDuration" -ForegroundColor White
    Write-Host "Total Expected:   $($expectedItems.Count)" -ForegroundColor White
    Write-Host "Total Copied:     $($copiedItems.Count)" -ForegroundColor Green
    Write-Host "Total Skipped:    $($skippedItems.Count)" -ForegroundColor Yellow
    Write-Host "Total Failed:     $($failedItems.Count)" -ForegroundColor Red

    if ($copiedItems.Count -gt 0) {
        foreach ($item in $copiedItems) {
            Write-Host " [+] Copied: $item" -ForegroundColor Green
        }
    }

    if ($skippedItems.Count -gt 0) {
        foreach ($item in $skippedItems) {
            Write-Host " [!] Skipped: $item" -ForegroundColor Yellow
        }
    }

    if ($failedItems.Count -gt 0) {
        foreach ($item in $failedItems) {
            Write-Host " [X] Failed: $item" -ForegroundColor Red
        }
    }

    if ($missedItems.Count -gt 0) {
        Write-Host "Total Missed:     $($missedItems.Count)" -ForegroundColor Red
        foreach ($m in $missedItems) {
            Write-Host " [X] Missed: $m" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Total Missed:     0" -ForegroundColor Gray
    }

    $statusColor = if (($failedItems.Count + $missedItems.Count) -gt 0) { 'Red' } else { 'Blue' }
    Write-Host "--------------------------" -ForegroundColor $statusColor
    Write-Host "All copy/move operations completed."
    Write-Host ""
}

# ------------------------------------------------------------
# Input Functions
# ------------------------------------------------------------
function Read-ScriptInputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ActionType
    )

    $mode = Read-SourceMode

    $sourceFiles = @()
    $sourceDir = Read-Host 'Enter Source Directory'

    if (-not (Test-Path $sourceDir)) {
        throw 'Source directory does not exist.'
    }

    $copyMethod = 'Serial'
    $parallelCount = 1

    if ($mode -eq 'I') {
        $selectedFile = Resolve-IndividualFile -SourceDir $sourceDir
        $sourceFiles += $selectedFile
    }
    elseif ($mode -eq 'M') {
        $selectedFiles = Resolve-MultipleFiles -SourceDir $sourceDir
        $sourceFiles += $selectedFiles
    }
    else {
        $sourceFiles = @(Get-ChildItem -Path $sourceDir -File)
        if ($sourceFiles.Count -eq 0) {
            throw 'No files found in source directory.'
        }
    }

    if ($sourceFiles.Count -gt 1) {
        $copyMethod = Read-CopyMethod
        if ($copyMethod -eq 'Parallel') {
            $parallelCount = Read-ParallelCount -Default 4 -Min 1 -Max 64
        }
    }

    $destFolder = Read-Host 'Enter Destination Folder Path'
    if (-not (Test-Path $destFolder)) {
        Write-Host "Creating destination folder: $destFolder" -ForegroundColor Yellow
        New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
    }

    return [PSCustomObject]@{
        ActionType    = $ActionType
        Mode          = $mode
        SourceDir     = $sourceDir
        SourceFiles   = $sourceFiles
        DestFolder    = $destFolder
        CopyMethod    = $copyMethod
        ParallelCount = $parallelCount
    }
}

# ------------------------------------------------------------
# Single File / Serial Worker
# ------------------------------------------------------------
function Copy-OneFileSerial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory)]
        [string]$DestFolder,

        [Parameter(Mandatory)]
        [string]$CopyMethod,

        [Parameter(Mandatory)]
        [int]$ParallelCount,

        [Parameter(Mandatory)]
        [string]$WorkerId,

        [Parameter(Mandatory)]
        [string]$ActionType,

        [Parameter(Mandatory)]
        [bool]$ShowPerFileOutput
    )

    $copyId     = [guid]::NewGuid().Guid
    $sourcePath = $File.FullName
    $destPath   = Join-Path $DestFolder $File.Name
    $fileSize   = $File.Length
    $sizeInfo   = Get-FileSizeInfo -Bytes $fileSize
    $eventType  = Get-EventType -ActionType $ActionType
    $actionWord = $ActionType

    if (Test-Path $destPath) {
        $overwrite = $true

        if (-not $script:OverwriteAllMode) {
            $overwriteChoice = Read-OverwriteChoice -FileName $File.Name
            switch ($overwriteChoice) {
                'Y' { $overwrite = $true }
                'N' { $overwrite = $false }
                'A' {
                    $overwrite = $true
                    $script:OverwriteAllMode = $true
                }
            }
        }

        if (-not $overwrite) {
            if ($script:LogToConsole) {
                Write-Host "Skipping $($File.Name)" -ForegroundColor Yellow
            }

            if ($script:LoggingEnabled) {
                Write-LogEvent -Row @{
                    Timestamp         = Get-Timestamp
                    CopyId            = $copyId
                    EventType         = $eventType
                    Status            = 'Skipped'
                    CopyMethod        = $CopyMethod
                    ParallelCount     = $ParallelCount
                    WorkerId          = $WorkerId
                    FileName          = $File.Name
                    SourcePath        = $sourcePath
                    DestinationPath   = $destPath
                    FileSizeBytes     = $sizeInfo.Bytes
                    FileSizeKB        = $sizeInfo.KB
                    FileSizeMB        = $sizeInfo.MB
                    FileSizeGB        = $sizeInfo.GB
                    FileSizeTB        = $sizeInfo.TB
                    BytesTransferred  = 0
                    Percent           = 0
                    MBps              = ''
                    GBps              = ''
                    ETA               = ''
                    StartTime         = ''
                    EndTime           = ''
                    TotalTime         = ''
                    AverageSpeedMBps  = ''
                    LogFile           = ''
                    Message           = "$actionWord operation skipped because overwrite was not approved."
                    ErrorMessage      = ''
                }
            }

            $script:SkippedList += $File.Name
            return
        }
    }

    $bufferSize  = 4MB
    $buffer      = New-Object byte[] $bufferSize
    $bytesCopied = 0
    $startTime   = Get-Date
    $lastLogTime = $startTime
    $lastBytes   = 0

    if ($script:LogToConsole -and $ShowPerFileOutput) {
        Show-CopyHeader -FileName $File.Name -SizeInfo $sizeInfo -LogDisplay (Get-DisplayLogPath) -ActionType $ActionType
    }

    if ($script:LoggingEnabled) {
        Write-LogEvent -Row @{
            Timestamp         = Get-Timestamp
            CopyId            = $copyId
            EventType         = $eventType
            Status            = 'Start'
            CopyMethod        = $CopyMethod
            ParallelCount     = $ParallelCount
            WorkerId          = $WorkerId
            FileName          = $File.Name
            SourcePath        = $sourcePath
            DestinationPath   = $destPath
            FileSizeBytes     = $sizeInfo.Bytes
            FileSizeKB        = $sizeInfo.KB
            FileSizeMB        = $sizeInfo.MB
            FileSizeGB        = $sizeInfo.GB
            FileSizeTB        = $sizeInfo.TB
            BytesTransferred  = 0
            Percent           = 0
            MBps              = 0
            GBps              = 0
            ETA               = ''
            StartTime         = $startTime
            EndTime           = ''
            TotalTime         = ''
            AverageSpeedMBps  = ''
            LogFile           = ''
            Message           = "$actionWord operation started."
            ErrorMessage      = ''
        }
    }

    $fsSource = $null
    $fsDest   = $null

    try {
        $fsSource = [System.IO.File]::OpenRead($sourcePath)
        $fsDest   = [System.IO.File]::Open($destPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

        while (($read = $fsSource.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fsDest.Write($buffer, 0, $read)
            $bytesCopied += $read

            $now = Get-Date
            $elapsed = ($now - $lastLogTime).TotalSeconds

            if ($elapsed -ge (Get-ProgressIntervalSeconds)) {
                $deltaBytes = $bytesCopied - $lastBytes
                $mbps = [math]::Round(($deltaBytes / 1MB) / $elapsed, 2)
                $gbps = [math]::Round(($deltaBytes / 1GB) / $elapsed, 4)
                $percent = if ($fileSize -gt 0) {
                    [math]::Round(($bytesCopied / $fileSize) * 100, 2)
                } else {
                    100
                }

                $totalElapsed = ($now - $startTime).TotalSeconds
                if ($totalElapsed -gt 0 -and $bytesCopied -gt 0) {
                    $avgRate = $bytesCopied / $totalElapsed
                    if ($avgRate -gt 0 -and $fileSize -gt $bytesCopied) {
                        $remainingSeconds = ($fileSize - $bytesCopied) / $avgRate
                        $eta = (New-TimeSpan -Seconds $remainingSeconds).ToString('hh\:mm\:ss')
                    }
                    else {
                        $eta = '00:00:00'
                    }
                }
                else {
                    $eta = '00:00:00'
                }

                $ts = $now.ToString('yyyy-MM-dd HH:mm:ss')

                if ($script:LogToConsole) {
                    Write-Host (
                        '{0} | {1,6}% | {2,8:N0}/{3,8:N0} MB | {4,6} MB/s | ETA {5} | CopyId {6} | ParallelCount {7}' -f
                        $ts,
                        $percent,
                        ($bytesCopied / 1MB),
                        ($fileSize / 1MB),
                        $mbps,
                        $eta,
                        $copyId,
                        $ParallelCount
                    )
                }

                if ($script:LoggingEnabled) {
                    Write-LogEvent -Row @{
                        Timestamp         = $ts
                        CopyId            = $copyId
                        EventType         = $eventType
                        Status            = 'Progress'
                        CopyMethod        = $CopyMethod
                        ParallelCount     = $ParallelCount
                        WorkerId          = $WorkerId
                        FileName          = $File.Name
                        SourcePath        = $sourcePath
                        DestinationPath   = $destPath
                        FileSizeBytes     = $sizeInfo.Bytes
                        FileSizeKB        = $sizeInfo.KB
                        FileSizeMB        = $sizeInfo.MB
                        FileSizeGB        = $sizeInfo.GB
                        FileSizeTB        = $sizeInfo.TB
                        BytesTransferred  = $bytesCopied
                        Percent           = $percent
                        MBps              = $mbps
                        GBps              = $gbps
                        ETA               = $eta
                        StartTime         = $startTime
                        EndTime           = ''
                        TotalTime         = ''
                        AverageSpeedMBps  = ''
                        LogFile           = ''
                        Message           = "$actionWord progress update."
                        ErrorMessage      = ''
                    }
                }

                $lastLogTime = $now
                $lastBytes   = $bytesCopied
            }
        }

        if ($ActionType -eq 'Move') {
            if ($fsSource) {
                $fsSource.Dispose()
                $fsSource = $null
            }
            if ($fsDest) {
                $fsDest.Dispose()
                $fsDest = $null
            }

            Remove-Item -Path $sourcePath -Force
        }

        $finalPercent = 100
        $finalTs = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $finalEta = '00:00:00'

        if ($script:LogToConsole -and $bytesCopied -gt 0) {
            Write-Host (
                '{0} | {1,6}% | {2,8:N0}/{3,8:N0} MB | {4,6} MB/s | ETA {5} | CopyId {6} | ParallelCount {7}' -f
                $finalTs,
                $finalPercent,
                ($bytesCopied / 1MB),
                ($fileSize / 1MB),
                0,
                $finalEta,
                $copyId,
                $ParallelCount
            )
        }

        if ($script:LoggingEnabled -and $bytesCopied -gt 0) {
            Write-LogEvent -Row @{
                Timestamp         = $finalTs
                CopyId            = $copyId
                EventType         = $eventType
                Status            = 'Progress'
                CopyMethod        = $CopyMethod
                ParallelCount     = $ParallelCount
                WorkerId          = $WorkerId
                FileName          = $File.Name
                SourcePath        = $sourcePath
                DestinationPath   = $destPath
                FileSizeBytes     = $sizeInfo.Bytes
                FileSizeKB        = $sizeInfo.KB
                FileSizeMB        = $sizeInfo.MB
                FileSizeGB        = $sizeInfo.GB
                FileSizeTB        = $sizeInfo.TB
                BytesTransferred  = $bytesCopied
                Percent           = 100
                MBps              = ''
                GBps              = ''
                ETA               = $finalEta
                StartTime         = $startTime
                EndTime           = ''
                TotalTime         = ''
                AverageSpeedMBps  = ''
                LogFile           = ''
                Message           = "$actionWord progress update."
                ErrorMessage      = ''
            }
        }

        $endTime = Get-Date
        $totalTime = $endTime - $startTime
        $avgMBps = if ($totalTime.TotalSeconds -gt 0) {
            [math]::Round(($fileSize / 1MB) / $totalTime.TotalSeconds, 2)
        } else {
            0
        }

        $summary = Get-CopySummaryText -FileName $File.Name -SizeInfo $sizeInfo -StartTime $startTime -EndTime $endTime -TotalTime $totalTime -AverageSpeedMBps $avgMBps -CopyId $copyId -ActionType $ActionType

        if ($script:LogToConsole -and $ShowPerFileOutput) {
            Write-Host $summary -ForegroundColor Green
        }

        if ($script:LoggingEnabled) {
            Write-LogEvent -Row @{
                Timestamp         = Get-Timestamp
                CopyId            = $copyId
                EventType         = $eventType
                Status            = 'Complete'
                CopyMethod        = $CopyMethod
                ParallelCount     = $ParallelCount
                WorkerId          = $WorkerId
                FileName          = $File.Name
                SourcePath        = $sourcePath
                DestinationPath   = $destPath
                FileSizeBytes     = $sizeInfo.Bytes
                FileSizeKB        = $sizeInfo.KB
                FileSizeMB        = $sizeInfo.MB
                FileSizeGB        = $sizeInfo.GB
                FileSizeTB        = $sizeInfo.TB
                BytesTransferred  = $bytesCopied
                Percent           = 100
                MBps              = ''
                GBps              = ''
                ETA               = '00:00:00'
                StartTime         = $startTime
                EndTime           = $endTime
                TotalTime         = $totalTime
                AverageSpeedMBps  = $avgMBps
                LogFile           = ''
                Message           = "$actionWord operation completed successfully."
                ErrorMessage      = ''
            }
        }

        $script:SuccessList += $File.Name
    }
    catch {
        $errMsg = $_.Exception.Message

        if ($script:LogToConsole) {
            Write-Host "Failed to process file '$($File.Name)': $errMsg" -ForegroundColor Red
        }

        if ($script:LoggingEnabled) {
            Write-LogEvent -Row @{
                Timestamp         = Get-Timestamp
                CopyId            = $copyId
                EventType         = $eventType
                Status            = 'Failed'
                CopyMethod        = $CopyMethod
                ParallelCount     = $ParallelCount
                WorkerId          = $WorkerId
                FileName          = $File.Name
                SourcePath        = $sourcePath
                DestinationPath   = $destPath
                FileSizeBytes     = $sizeInfo.Bytes
                FileSizeKB        = $sizeInfo.KB
                FileSizeMB        = $sizeInfo.MB
                FileSizeGB        = $sizeInfo.GB
                FileSizeTB        = $sizeInfo.TB
                BytesTransferred  = $bytesCopied
                Percent           = if ($fileSize -gt 0) { [math]::Round(($bytesCopied / $fileSize) * 100, 2) } else { 0 }
                MBps              = ''
                GBps              = ''
                ETA               = ''
                StartTime         = $startTime
                EndTime           = Get-Date
                TotalTime         = ''
                AverageSpeedMBps  = ''
                LogFile           = ''
                Message           = "$actionWord operation failed."
                ErrorMessage      = $errMsg
            }
        }

        $script:FailedList += $File.Name
    }
    finally {
        if ($fsSource) { $fsSource.Dispose() }
        if ($fsDest)   { $fsDest.Dispose() }
    }
}

# ------------------------------------------------------------
# Parallel Support
# ------------------------------------------------------------
function Ensure-ThreadJobAvailable {
    [CmdletBinding()]
    param()

    if (Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue) {
        return
    }

    throw "Start-ThreadJob is not available. Use PowerShell 7, or install/import the ThreadJob module before using Parallel mode."
}

function Invoke-FileCopyParallel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$InputObject
    )

    Ensure-ThreadJobAvailable

    $script:DefaultList = @($InputObject.SourceFiles.Name)

    $queue = [System.Collections.Generic.Queue[object]]::new()
    foreach ($file in $InputObject.SourceFiles) {
        $queue.Enqueue($file)
    }

    $activeJobs = @()
    $workerCounter = 0
    $copyMethod = $InputObject.CopyMethod
    $parallelCount = $InputObject.ParallelCount
    $actionType = $InputObject.ActionType
    $eventType = Get-EventType -ActionType $actionType

    while ($queue.Count -gt 0 -or $activeJobs.Count -gt 0) {

        while ($queue.Count -gt 0 -and $activeJobs.Count -lt $parallelCount) {
            $file = $queue.Dequeue()
            $workerCounter++
            $workerId = "Worker-{0}" -f $workerCounter
            $copyId = [guid]::NewGuid().Guid
            $destPath = Join-Path $InputObject.DestFolder $file.Name
            $sizeInfo = Get-FileSizeInfo -Bytes $file.Length

            if (Test-Path $destPath) {
                $overwrite = $true

                if (-not $script:OverwriteAllMode) {
                    $overwriteChoice = Read-OverwriteChoice -FileName $file.Name
                    switch ($overwriteChoice) {
                        'Y' { $overwrite = $true }
                        'N' { $overwrite = $false }
                        'A' {
                            $overwrite = $true
                            $script:OverwriteAllMode = $true
                        }
                    }
                }

                if (-not $overwrite) {
                    if ($script:LogToConsole) {
                        Write-Host "Skipping $($file.Name)" -ForegroundColor Yellow
                    }

                    if ($script:LoggingEnabled) {
                        Write-LogEvent -Row @{
                            Timestamp         = Get-Timestamp
                            CopyId            = $copyId
                            EventType         = $eventType
                            Status            = 'Skipped'
                            CopyMethod        = $copyMethod
                            ParallelCount     = $parallelCount
                            WorkerId          = $workerId
                            FileName          = $file.Name
                            SourcePath        = $file.FullName
                            DestinationPath   = $destPath
                            FileSizeBytes     = $sizeInfo.Bytes
                            FileSizeKB        = $sizeInfo.KB
                            FileSizeMB        = $sizeInfo.MB
                            FileSizeGB        = $sizeInfo.GB
                            FileSizeTB        = $sizeInfo.TB
                            BytesTransferred  = 0
                            Percent           = 0
                            MBps              = ''
                            GBps              = ''
                            ETA               = ''
                            StartTime         = ''
                            EndTime           = ''
                            TotalTime         = ''
                            AverageSpeedMBps  = ''
                            LogFile           = ''
                            Message           = "$actionType operation skipped because overwrite was not approved."
                            ErrorMessage      = ''
                        }
                    }

                    $script:SkippedList += $file.Name
                    continue
                }
            }

            if ($script:LoggingEnabled) {
                Write-LogEvent -Row @{
                    Timestamp         = Get-Timestamp
                    CopyId            = $copyId
                    EventType         = $eventType
                    Status            = 'Start'
                    CopyMethod        = $copyMethod
                    ParallelCount     = $parallelCount
                    WorkerId          = $workerId
                    FileName          = $file.Name
                    SourcePath        = $file.FullName
                    DestinationPath   = $destPath
                    FileSizeBytes     = $sizeInfo.Bytes
                    FileSizeKB        = $sizeInfo.KB
                    FileSizeMB        = $sizeInfo.MB
                    FileSizeGB        = $sizeInfo.GB
                    FileSizeTB        = $sizeInfo.TB
                    BytesTransferred  = 0
                    Percent           = 0
                    MBps              = 0
                    GBps              = 0
                    ETA               = ''
                    StartTime         = Get-Date
                    EndTime           = ''
                    TotalTime         = ''
                    AverageSpeedMBps  = ''
                    LogFile           = ''
                    Message           = "$actionType operation started."
                    ErrorMessage      = ''
                }
            }

            $job = Start-ThreadJob -Name $workerId -ArgumentList @(
                $file.FullName,
                $destPath,
                $file.Name,
                $file.Length,
                $copyId,
                $workerId,
                $copyMethod,
                $parallelCount,
                $actionType
            ) -ScriptBlock {
                param(
                    $sourcePath,
                    $destPath,
                    $fileName,
                    $fileSize,
                    $copyId,
                    $workerId,
                    $copyMethod,
                    $parallelCount,
                    $actionType
                )

                $eventType = if ($actionType -eq 'Move') { 'FileMove' } else { 'FileCopy' }
                $bufferSize = 4MB
                $buffer = New-Object byte[] $bufferSize
                $bytesCopied = 0
                $startTime = Get-Date
                $lastLogTime = $startTime
                $lastBytes = 0
                $events = New-Object System.Collections.Generic.List[object]

                $sizeInfo = [PSCustomObject]@{
                    Bytes = $fileSize
                    KB    = [math]::Round($fileSize / 1KB, 2)
                    MB    = [math]::Round($fileSize / 1MB, 2)
                    GB    = [math]::Round($fileSize / 1GB, 2)
                    TB    = [math]::Round($fileSize / 1TB, 4)
                }

                $fsSource = $null
                $fsDest = $null

                try {
                    $fsSource = [System.IO.File]::OpenRead($sourcePath)
                    $fsDest   = [System.IO.File]::Open($destPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

                    while (($read = $fsSource.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $fsDest.Write($buffer, 0, $read)
                        $bytesCopied += $read

                        $now = Get-Date
                        $elapsed = ($now - $lastLogTime).TotalSeconds

                        if ($elapsed -ge 0.25) {
                            $deltaBytes = $bytesCopied - $lastBytes
                            $mbps = [math]::Round(($deltaBytes / 1MB) / $elapsed, 2)
                            $gbps = [math]::Round(($deltaBytes / 1GB) / $elapsed, 4)
                            $percent = if ($fileSize -gt 0) {
                                [math]::Round(($bytesCopied / $fileSize) * 100, 2)
                            } else {
                                100
                            }

                            $totalElapsed = ($now - $startTime).TotalSeconds
                            if ($totalElapsed -gt 0 -and $bytesCopied -gt 0) {
                                $avgRate = $bytesCopied / $totalElapsed
                                if ($avgRate -gt 0 -and $fileSize -gt $bytesCopied) {
                                    $remainingSeconds = ($fileSize - $bytesCopied) / $avgRate
                                    $eta = (New-TimeSpan -Seconds $remainingSeconds).ToString('hh\:mm\:ss')
                                }
                                else {
                                    $eta = '00:00:00'
                                }
                            }
                            else {
                                $eta = '00:00:00'
                            }

                            $events.Add([PSCustomObject]@{
                                Timestamp         = $now.ToString('yyyy-MM-dd HH:mm:ss')
                                CopyId            = $copyId
                                EventType         = $eventType
                                Status            = 'Progress'
                                CopyMethod        = $copyMethod
                                ParallelCount     = $parallelCount
                                WorkerId          = $workerId
                                FileName          = $fileName
                                SourcePath        = $sourcePath
                                DestinationPath   = $destPath
                                FileSizeBytes     = $sizeInfo.Bytes
                                FileSizeKB        = $sizeInfo.KB
                                FileSizeMB        = $sizeInfo.MB
                                FileSizeGB        = $sizeInfo.GB
                                FileSizeTB        = $sizeInfo.TB
                                BytesTransferred  = $bytesCopied
                                Percent           = $percent
                                MBps              = $mbps
                                GBps              = $gbps
                                ETA               = $eta
                                StartTime         = $startTime
                                EndTime           = ''
                                TotalTime         = ''
                                AverageSpeedMBps  = ''
                                LogFile           = ''
                                Message           = "$actionType progress update."
                                ErrorMessage      = ''
                            })

                            $lastLogTime = $now
                            $lastBytes   = $bytesCopied
                        }
                    }

                    if ($actionType -eq 'Move') {
                        if ($fsSource) {
                            $fsSource.Dispose()
                            $fsSource = $null
                        }
                        if ($fsDest) {
                            $fsDest.Dispose()
                            $fsDest = $null
                        }

                        Remove-Item -Path $sourcePath -Force
                    }

                    if ($bytesCopied -gt 0) {
                        $events.Add([PSCustomObject]@{
                            Timestamp         = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                            CopyId            = $copyId
                            EventType         = $eventType
                            Status            = 'Progress'
                            CopyMethod        = $copyMethod
                            ParallelCount     = $parallelCount
                            WorkerId          = $workerId
                            FileName          = $fileName
                            SourcePath        = $sourcePath
                            DestinationPath   = $destPath
                            FileSizeBytes     = $sizeInfo.Bytes
                            FileSizeKB        = $sizeInfo.KB
                            FileSizeMB        = $sizeInfo.MB
                            FileSizeGB        = $sizeInfo.GB
                            FileSizeTB        = $sizeInfo.TB
                            BytesTransferred  = $bytesCopied
                            Percent           = 100
                            MBps              = ''
                            GBps              = ''
                            ETA               = '00:00:00'
                            StartTime         = $startTime
                            EndTime           = ''
                            TotalTime         = ''
                            AverageSpeedMBps  = ''
                            LogFile           = ''
                            Message           = "$actionType progress update."
                            ErrorMessage      = ''
                        })
                    }

                    $endTime = Get-Date
                    $totalTime = $endTime - $startTime
                    $avgMBps = if ($totalTime.TotalSeconds -gt 0) {
                        [math]::Round(($fileSize / 1MB) / $totalTime.TotalSeconds, 2)
                    } else {
                        0
                    }

                    [PSCustomObject]@{
                        ResultType        = 'Complete'
                        ActionType        = $actionType
                        Timestamp         = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        CopyId            = $copyId
                        EventType         = $eventType
                        Status            = 'Complete'
                        CopyMethod        = $copyMethod
                        ParallelCount     = $parallelCount
                        WorkerId          = $workerId
                        FileName          = $fileName
                        SourcePath        = $sourcePath
                        DestinationPath   = $destPath
                        FileSizeBytes     = $sizeInfo.Bytes
                        FileSizeKB        = $sizeInfo.KB
                        FileSizeMB        = $sizeInfo.MB
                        FileSizeGB        = $sizeInfo.GB
                        FileSizeTB        = $sizeInfo.TB
                        BytesTransferred  = $bytesCopied
                        Percent           = 100
                        MBps              = ''
                        GBps              = ''
                        ETA               = '00:00:00'
                        StartTime         = $startTime
                        EndTime           = $endTime
                        TotalTime         = $totalTime
                        AverageSpeedMBps  = $avgMBps
                        LogFile           = ''
                        Message           = "$actionType operation completed successfully."
                        ErrorMessage      = ''
                        ProgressEvents    = $events
                    }
                }
                catch {
                    [PSCustomObject]@{
                        ResultType        = 'Failed'
                        ActionType        = $actionType
                        Timestamp         = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        CopyId            = $copyId
                        EventType         = $eventType
                        Status            = 'Failed'
                        CopyMethod        = $copyMethod
                        ParallelCount     = $parallelCount
                        WorkerId          = $workerId
                        FileName          = $fileName
                        SourcePath        = $sourcePath
                        DestinationPath   = $destPath
                        FileSizeBytes     = $sizeInfo.Bytes
                        FileSizeKB        = $sizeInfo.KB
                        FileSizeMB        = $sizeInfo.MB
                        FileSizeGB        = $sizeInfo.GB
                        FileSizeTB        = $sizeInfo.TB
                        BytesTransferred  = $bytesCopied
                        Percent           = if ($fileSize -gt 0) { [math]::Round(($bytesCopied / $fileSize) * 100, 2) } else { 0 }
                        MBps              = ''
                        GBps              = ''
                        ETA               = ''
                        StartTime         = $startTime
                        EndTime           = Get-Date
                        TotalTime         = ''
                        AverageSpeedMBps  = ''
                        LogFile           = ''
                        Message           = "$actionType operation failed."
                        ErrorMessage      = $_.Exception.Message
                        ProgressEvents    = $events
                    }
                }
                finally {
                    if ($fsSource) { $fsSource.Dispose() }
                    if ($fsDest)   { $fsDest.Dispose() }
                }
            }

            $activeJobs += [PSCustomObject]@{
                Job      = $job
                FileName = $file.Name
                WorkerId = $workerId
            }
        }

        $completed = @($activeJobs | Where-Object { $_.Job.State -in @('Completed','Failed','Stopped') })

        foreach ($item in $completed) {
            $result = Receive-Job -Job $item.Job -Wait -AutoRemoveJob

            if ($result.ProgressEvents) {
                foreach ($evt in $result.ProgressEvents) {
                    if ($script:LoggingEnabled) {
                        $row = @{}
                        foreach ($field in $script:LogFieldOrder) {
                            $row[$field] = $evt.$field
                        }
                        Write-LogEvent -Row $row
                    }

                    if ($script:LogToConsole) {
                        $displayMBps = if ([string]::IsNullOrWhiteSpace([string]$evt.MBps)) { 0 } else { [double]$evt.MBps }
                        Write-Host (
                            '{0} | {1,6}% | {2,8:N0}/{3,8:N0} MB | {4,6} MB/s | ETA {5} | CopyId {6} | ParallelCount {7}' -f
                            $evt.Timestamp,
                            [double]$evt.Percent,
                            ([double]$evt.BytesTransferred / 1MB),
                            [double]$evt.FileSizeMB,
                            $displayMBps,
                            $evt.ETA,
                            $evt.CopyId,
                            $evt.ParallelCount
                        )
                    }
                }
            }

            if ($result.ResultType -eq 'Complete') {
                if ($script:LoggingEnabled) {
                    $row = @{}
                    foreach ($field in $script:LogFieldOrder) {
                        $row[$field] = $result.$field
                    }
                    Write-LogEvent -Row $row
                }

                $script:SuccessList += $result.FileName
            }
            else {
                if ($script:LoggingEnabled) {
                    $row = @{}
                    foreach ($field in $script:LogFieldOrder) {
                        $row[$field] = $result.$field
                    }
                    Write-LogEvent -Row $row
                }

                if ($script:LogToConsole) {
                    Write-Host "Failed to process file '$($result.FileName)': $($result.ErrorMessage)" -ForegroundColor Red
                }

                $script:FailedList += $result.FileName
            }

            $activeJobs = @($activeJobs | Where-Object { $_.Job.Id -ne $item.Job.Id })
        }

        if ($activeJobs.Count -gt 0) {
            Start-Sleep -Milliseconds 300
        }
    }
}

# ------------------------------------------------------------
# Main Processing
# ------------------------------------------------------------
function Invoke-FileCopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$InputObject
    )

    $showPerFileOutput = ($InputObject.Mode -eq 'I')

    if ($InputObject.SourceFiles.Count -gt 1 -and $InputObject.CopyMethod -eq 'Parallel') {
        Invoke-FileCopyParallel -InputObject $InputObject
        return
    }

    $script:DefaultList = @($InputObject.SourceFiles.Name)

    foreach ($file in $InputObject.SourceFiles) {
        Copy-OneFileSerial `
            -File $file `
            -DestFolder $InputObject.DestFolder `
            -CopyMethod $InputObject.CopyMethod `
            -ParallelCount $InputObject.ParallelCount `
            -WorkerId 'Worker-1' `
            -ActionType $InputObject.ActionType `
            -ShowPerFileOutput $showPerFileOutput
    }
}

# ------------------------------------------------------------
# Script Entry Point
# ------------------------------------------------------------
try {
    Write-Host "`n****************************************************" -ForegroundColor White
    $choice = Read-Host "Action: [C]ontinue | [Q]uit"
    $selection = $choice.Trim().ToLower()

    if ($selection -eq 'q') {
        Write-Host "User requested exit." -ForegroundColor Red
        exit
    }

    $actionType = Read-ActionType

    Write-Host ('Starting script: {0}' -f $script:ScriptName) -ForegroundColor Cyan

    $script:RunStartTime = Get-Date
    $script:OverwriteAllMode = $false

    $inputs = Read-ScriptInputs -ActionType $actionType
    Initialize-Logging
    Invoke-FileCopy -InputObject $inputs

    $script:RunEndTime = Get-Date

    if ($script:LogToConsole) {
        Write-Host ''
        Show-ScriptSummary -Title 'FILE COPY RESULTS' -ActionType $actionType
    }
}
catch {
    $script:RunEndTime = Get-Date
    $err = $_
    if ($script:LogToConsole) {
        Write-Host "Script ended with an error: $($err.Exception.Message)" -ForegroundColor Red
    }
    throw
}
finally {
    if ($script:LogToConsole) {
        Write-Host 'Script finished.' -ForegroundColor Cyan
    }
}