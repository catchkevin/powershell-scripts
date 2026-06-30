#requires -Version 5.1
# ============================================================
# AzCopy Transfer with Live Metrics + Summary
# Supports:
#   - Local <-> Blob and Blob <-> Blob transfers using azcopy.exe
#   - Copy or Move
#   - Serial or Parallel execution model via AzCopy concurrency
#   - TXT / CSV / JSON / ALL logging
#   - Screen / Log / Both output modes
#   - Daily UTC log rollover (one file per type per UTC day)
#   - Ordered fields across TXT / CSV / JSON
#   - Transfer GUID / CopyId for event correlation
#   - Optional debug logging for progress events
#   - ISO 8601 UTC logging timestamps
#   - Log Session ID per script run
#   - AzCopy stdout/stderr parsing for progress logging
#   - SAS validation before execution
#   - Retry + resume tracking
#   - Per-file job detail logging after run completion
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================== 
# HEADER INFO
# ============================================================================== 
$VariableContext = "AzCopy Transfer with Live Metrics + Summary"
$VariableVersion = "Version 1.0.9"

$LastUpdatedUTC = "2026-03-30 21:05:00.000"
$LastUpdatedET  = "2026-03-30 17:05:00.000"
$LastUpdatedCT  = "2026-03-30 16:05:00.000"
$LastUpdatedMT  = "2026-03-30 15:05:00.000"
$LastUpdatedPT  = "2026-03-30 14:05:00.000"
$LastUpdated    = $LastUpdatedUTC

# --- DESIGN: CONTEXT HEADER ---
Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " CONTEXT: $VariableContext" -ForegroundColor Cyan
Write-Host " VERSION: $VariableVersion" -ForegroundColor Cyan
Write-Host " UPDATED: $LastUpdated" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor White

# --- DESIGN: PURPOSE AND PROMPTS HEADER ---
Write-Host " Script Purpose:" -ForegroundColor Yellow
Write-Host " Transfer files or directories with AzCopy using local and/or blob"
Write-Host " endpoints, structured logging, progress parsing, SAS validation,"
Write-Host " retry and resume support, and final execution summary details."
Write-Host ""
Write-Host " Input/Steps Required:" -ForegroundColor Yellow
Write-Host " 1. Select whether to continue with the current terminal view or exit."
Write-Host " 2. Select Copy or Move."
Write-Host " 3. Enter azcopy.exe path, source/destination types and values, logging options, and run the operation."
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
        # Clear-Host (Commented out per user preference)
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

# ------------------------------------------------------------
# Script Metadata
# ------------------------------------------------------------
$script:ScriptName = if ($MyInvocation.MyCommand.Name) {
    [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
} else {
    'AzCopyTransferWithMetrics'
}

# ------------------------------------------------------------
# Global Logging State
# ------------------------------------------------------------
$script:LoggingEnabled   = $false
$script:LogFolder        = $null
$script:LogBaseName      = 'azcopy_transfer_test'
$script:LogTXTPath       = $null
$script:LogCSVPath       = $null
$script:LogJSONPath      = $null
$script:LogDay           = $null
$script:LogType          = $null
$script:LogPathDisplayed = $false
$script:LogToConsole     = $true
$script:OutputMode       = 'both'

# ------------------------------------------------------------
# Debug Logging State
# ------------------------------------------------------------
$script:DebugEnabled     = $false
$script:DebugMode        = $null
$script:DebugTXTPath     = $null
$script:DebugCSVPath     = $null
$script:DebugJSONPath    = $null
$script:DebugLogDay      = $null

# ------------------------------------------------------------
# Script Run State
# ------------------------------------------------------------
$script:RunStartTime     = $null
$script:RunEndTime       = $null
$script:OverwriteAllMode = $false
$script:LogSessionId     = [guid]::NewGuid().Guid

# ------------------------------------------------------------
# AzCopy State
# ------------------------------------------------------------
$script:AzCopyPath             = $null
$script:AzCopyJobId            = $null
$script:AzCopyLogFolder        = $null
$script:AzCopyPlanFolder       = $null
$script:AzCopyRetryCount       = 2
$script:AzCopyRetryDelaySec    = 5
$script:AzCopyResumeOnFailure  = $true
$script:AzCopyOverwriteMode    = 'true'
$script:AzCopyFromTo           = $null
$script:AzCopyLastJobStatus    = $null
$script:AzCopyLastPercent      = $null
$script:AzCopyLastErrorMsg     = $null
$script:AzCopyLastConsoleDisplay = $null
$script:AzCopyLastConsolePercentBucket = -1
$script:AzCopyLastConsoleWriteTime = $null
$script:AzCopyLastBytesTransferred = $null
$script:AzCopyLastBytesTimestamp = $null
$script:AzCopyTempStdOutPath    = $null
$script:AzCopyTempStdErrPath    = $null

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
    'LogSessionId',
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

function Read-DebugMode {
    [CmdletBinding()]
    param()

    while ($true) {
        $raw = (Read-Host 'Debug Mode: [I]nsert in existing logs | Separate [D]ebug Log File and Current Log Files "Both"').Trim().ToLower()
        switch ($raw) {
            'i' { return 'I' }
            'd' { return 'D' }
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
        [int]$Default = 16,
        [int]$Min = 1,
        [int]$Max = 128
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

    [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-LogDateTimeIso {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$DateTimeValue
    )

    $utcValue = $DateTimeValue.ToUniversalTime()
    return $utcValue.ToString('yyyy-MM-ddTHH:mm:ssZ')
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
        return ([datetime]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
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

function Get-DebugDisplayLogPath {
    [CmdletBinding()]
    param()

    if (-not $script:DebugEnabled) {
        return ''
    }

    return ($script:DebugTXTPath, $script:DebugCSVPath, $script:DebugJSONPath) -join '; '
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

function Get-ActionSummaryTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ActionType
    )

    if ($ActionType -eq 'Move') { return 'MOVE SUMMARY' }
    return 'COPY SUMMARY'
}

function Test-IsBlobPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return ($Path -match '^https://.+\.blob\.core\.windows\.net/.+')
}

function Normalize-SasToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )

    $normalized = $Token.Trim()
    if ($normalized.StartsWith('?')) {
        $normalized = $normalized.Substring(1)
    }

    return $normalized
}

function Join-BlobUrlAndToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $cleanUrl = $Url.Trim().TrimEnd('?')
    $cleanTok = Normalize-SasToken -Token $Token
    return "$cleanUrl`?$cleanTok"
}

function Mask-SasForDisplay {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    if (-not (Test-IsBlobPath -Path $Value)) {
        return $Value
    }

    try {
        $uri = [System.Uri]$Value
        $baseUrl = $uri.GetLeftPart([System.UriPartial]::Path)
        $query = $uri.Query.TrimStart('?')

        if ([string]::IsNullOrWhiteSpace($query)) {
            return $baseUrl
        }

        $pairs = @{}
        foreach ($part in ($query -split '&')) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            $kv = $part -split '=', 2
            $k = $kv[0]
            $v = if ($kv.Count -gt 1) { $kv[1] } else { '' }
            $pairs[$k] = $v
        }

        if ($pairs.ContainsKey('sig')) {
            $pairs['sig'] = '***REDACTED***'
        }

        $queryOut = ($pairs.GetEnumerator() | Sort-Object Name | ForEach-Object {
            '{0}={1}' -f $_.Key, $_.Value
        }) -join '&'

        return "$baseUrl?$queryOut"
    }
    catch {
        return ($Value -replace '(sig=)[^&]+', '$1***REDACTED***')
    }
}

function Get-SasExpiryInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BlobUrl
    )

    $result = [PSCustomObject]@{
        HasSas      = $false
        IsExpired   = $false
        ExpiryUtc   = $null
        StartUtc    = $null
        Permissions = $null
        Services    = $null
    }

    if (-not (Test-IsBlobPath -Path $BlobUrl)) {
        return $result
    }

    try {
        $uri = [System.Uri]$BlobUrl
        $query = $uri.Query
        if ([string]::IsNullOrWhiteSpace($query)) {
            return $result
        }

        $query = $query.TrimStart('?')
        $parts = $query -split '&'
        $map = @{}

        foreach ($part in $parts) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            $kv = $part -split '=', 2
            $k = $kv[0]
            $v = if ($kv.Count -gt 1) { [System.Uri]::UnescapeDataString($kv[1]) } else { '' }
            $map[$k] = $v
        }

        $result.HasSas = $map.ContainsKey('sig')
        if ($map.ContainsKey('se')) {
            $expiry = [datetime]::Parse($map['se']).ToUniversalTime()
            $result.ExpiryUtc = $expiry
            $result.IsExpired = ($expiry -le [datetime]::UtcNow)
        }

        if ($map.ContainsKey('st')) { $result.StartUtc = [datetime]::Parse($map['st']).ToUniversalTime() }
        if ($map.ContainsKey('sp')) { $result.Permissions = $map['sp'] }
        if ($map.ContainsKey('ss')) { $result.Services = $map['ss'] }

        return $result
    }
    catch {
        return $result
    }
}

function Test-SasAccessForAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        [Parameter(Mandatory)]
        [string]$Role
    )

    $info = Get-SasExpiryInfo -BlobUrl $Target

    if (-not $info.HasSas) {
        return [PSCustomObject]@{ Valid = $true; Message = "$Role does not appear to use SAS, or token was not present in URL." }
    }

    if ($info.IsExpired) {
        return [PSCustomObject]@{ Valid = $false; Message = "$Role SAS token is expired. Expiry UTC: $($info.ExpiryUtc)" }
    }

    if ($info.StartUtc -and $info.StartUtc -gt [datetime]::UtcNow.AddMinutes(1)) {
        return [PSCustomObject]@{ Valid = $false; Message = "$Role SAS token start time is in the future. Start UTC: $($info.StartUtc)" }
    }

    return [PSCustomObject]@{ Valid = $true; Message = "$Role SAS token appears time-valid. Expiry UTC: $($info.ExpiryUtc)" }
}

function Read-AzCopyPath {
    [CmdletBinding()]
    param()

    while ($true) {
        $path = (Read-Host 'Enter Full Directory Path to azcopy.exe').Trim('"').Trim()
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }

        if (Test-Path -LiteralPath $path -PathType Container) {
            $candidate = Join-Path $path 'azcopy.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }
}

function Read-EndpointType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    while ($true) {
        $raw = (Read-Host "$Prompt [L]ocal | [B]lob").Trim().ToLower()
        switch ($raw) {
            'l' { return 'Local' }
            'b' { return 'Blob' }
            default { }
        }
    }
}

function Read-BlobInfoMode {
    [CmdletBinding()]
    param()

    while ($true) {
        $raw = (Read-Host 'Blob Info: [F]ull URL & Token | [S]eparate input URL & Token').Trim().ToLower()
        switch ($raw) {
            'f' { return 'F' }
            's' { return 'S' }
            default { }
        }
    }
}

function Read-BlobEndpoint {
    [CmdletBinding()]
    param()

    $mode = Read-BlobInfoMode
    if ($mode -eq 'F') {
        return (Read-Host 'Enter Blob SAS URL and Token Combined').Trim()
    }

    $url = (Read-Host 'Enter Blob URL').Trim()
    $tok = (Read-Host 'Enter Blob Token').Trim()
    return (Join-BlobUrlAndToken -Url $url -Token $tok)
}

function Read-SourceOrDestinationEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Source','Destination')]
        [string]$Role
    )

    $type = Read-EndpointType -Prompt "File/Directory $Role type"

    if ($type -eq 'Local') {
        $pathPrompt = if ($Role -eq 'Source') { 'Enter Source Directory Path' } else { 'Enter Destination Directory Path' }
        $path = (Read-Host $pathPrompt).Trim('"').Trim()

        if ($Role -eq 'Source' -and -not (Test-Path -LiteralPath $path)) {
            throw "$Role local path does not exist."
        }

        if ($Role -eq 'Destination' -and -not (Test-Path -LiteralPath $path)) {
            Write-Host "Creating destination folder: $path" -ForegroundColor Yellow
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }

        return [PSCustomObject]@{
            Type         = 'Local'
            Value        = $path
            DisplayValue = $path
        }
    }

    $blobValue = Read-BlobEndpoint
    return [PSCustomObject]@{
        Type         = 'Blob'
        Value        = $blobValue
        DisplayValue = (Mask-SasForDisplay -Value $blobValue)
    }
}

function Get-AzCopyFromToValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceType,
        [Parameter(Mandatory)][string]$DestinationType
    )

    if     ($SourceType -eq 'Local' -and $DestinationType -eq 'Blob')  { return 'LocalBlob'  }
    elseif ($SourceType -eq 'Blob'  -and $DestinationType -eq 'Local') { return 'BlobLocal'  }
    elseif ($SourceType -eq 'Blob'  -and $DestinationType -eq 'Blob')  { return 'BlobBlob'   }
    elseif ($SourceType -eq 'Local' -and $DestinationType -eq 'Local') { return 'LocalLocal' }
    else { return $null }
}

function Initialize-AzCopyFolders {
    [CmdletBinding()]
    param()

    if (-not $script:LogFolder) {
        $script:LogFolder = Join-Path $env:USERPROFILE 'Documents\filecopytest_logs'
    }

    $script:AzCopyLogFolder  = Join-Path $script:LogFolder 'azcopy_logs'
    $script:AzCopyPlanFolder = Join-Path $script:LogFolder 'azcopy_plans'

    foreach ($folder in @($script:AzCopyLogFolder, $script:AzCopyPlanFolder)) {
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }
    }
}

function Try-ConvertFromJson {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    try {
        return ($Text | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

function Get-FirstPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Object,
        [Parameter(Mandatory)]
        [string[]]$CandidateNames
    )

    if ($null -eq $Object) { return $null }

    foreach ($name in $CandidateNames) {
        $prop = $Object.PSObject.Properties[$name]
        if ($prop) {
            return $prop.Value
        }
    }

    return $null
}

function Parse-AzCopyOutputLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line
    )

    $line = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }

    $json = Try-ConvertFromJson -Text $line
    if ($json) {
        $msg        = Get-FirstPropertyValue -Object $json -CandidateNames @('MessageContent','messageContent','Message','message','msg')
        $level      = Get-FirstPropertyValue -Object $json -CandidateNames @('LogLevel','logLevel','Level','level','MessageType','messageType')
        $jobId      = Get-FirstPropertyValue -Object $json -CandidateNames @('JobID','jobId','JobId')
        $percent    = Get-FirstPropertyValue -Object $json -CandidateNames @('PercentComplete','percentComplete','Percent','percent')
        $mbps       = Get-FirstPropertyValue -Object $json -CandidateNames @('ThroughputMBps','throughputMBps','MBps','mbps')
        $fileName   = Get-FirstPropertyValue -Object $json -CandidateNames @('FileName','fileName','EntityName','entityName','Path','path')
        $bytesDone  = Get-FirstPropertyValue -Object $json -CandidateNames @('BytesTransferred','bytesTransferred','TotalBytesTransferred','totalBytesTransferred')
        $totalBytes = Get-FirstPropertyValue -Object $json -CandidateNames @('TotalBytes','totalBytes','TotalFileSize','totalFileSize','TotalBytesExpected','totalBytesExpected')
        $jobStatus  = Get-FirstPropertyValue -Object $json -CandidateNames @('JobStatus','jobStatus','Status','status')
        $errorMsg   = Get-FirstPropertyValue -Object $json -CandidateNames @('ErrorMsg','errorMsg','ErrorMessage','errorMessage')
        $activeConn = Get-FirstPropertyValue -Object $json -CandidateNames @('ActiveConnections','activeConnections')

        if ($msg -and $msg -is [string] -and $msg.Trim().StartsWith('{')) {
            $innerJson = Try-ConvertFromJson -Text $msg
            if ($innerJson) {
                if (-not $jobId)      { $jobId      = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('JobID','jobId','JobId') }
                if (-not $percent)    { $percent    = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('PercentComplete','percentComplete','Percent','percent') }
                if (-not $mbps)       { $mbps       = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('ThroughputMBps','throughputMBps','MBps','mbps') }
                if (-not $fileName)   { $fileName   = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('FileName','fileName','EntityName','entityName','Path','path') }
                if (-not $bytesDone)  { $bytesDone  = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('BytesTransferred','bytesTransferred','TotalBytesTransferred','totalBytesTransferred') }
                if (-not $totalBytes) { $totalBytes = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('TotalBytes','totalBytes','TotalFileSize','totalFileSize','TotalBytesExpected','totalBytesExpected') }
                if (-not $jobStatus)  { $jobStatus  = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('JobStatus','jobStatus','Status','status') }
                if (-not $errorMsg)   { $errorMsg   = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('ErrorMsg','errorMsg','ErrorMessage','errorMessage') }
                if (-not $activeConn) { $activeConn = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('ActiveConnections','activeConnections') }
                $msg = $msg
            }
        }

        $transfersCompleted = Get-FirstPropertyValue -Object $json -CandidateNames @('TransfersCompleted','transfersCompleted')
        $totalTransfersOut  = Get-FirstPropertyValue -Object $json -CandidateNames @('TotalTransfers','totalTransfers')
        if ($msg -and $msg -is [string] -and $msg.Trim().StartsWith('{')) {
            $innerJson = Try-ConvertFromJson -Text $msg
            if ($innerJson) {
                if (-not $transfersCompleted) { $transfersCompleted = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('TransfersCompleted','transfersCompleted') }
                if (-not $totalTransfersOut)  { $totalTransfersOut  = Get-FirstPropertyValue -Object $innerJson -CandidateNames @('TotalTransfers','totalTransfers') }
            }
        }

        return [PSCustomObject]@{
            RawLine            = $line
            IsJson             = $true
            Level              = $level
            Message            = $msg
            JobId              = $jobId
            Percent            = $percent
            MBps               = $mbps
            FileName           = $fileName
            BytesTransferred   = $bytesDone
            TotalBytes         = $totalBytes
            JobStatus          = $jobStatus
            ErrorMessage       = $errorMsg
            ActiveConnections  = $activeConn
            TransfersCompleted = $transfersCompleted
            TotalTransfers     = $totalTransfersOut
        }
    }

    $percent = $null
    $mbps    = $null
    $jobId   = $null
    $file    = $null

    if ($line -match '([0-9]+(?:\.[0-9]+)?)\s*%') {
        $percent = [double]$matches[1]
    }

    if ($line -match '([0-9]+(?:\.[0-9]+)?)\s*(Mb/s|MB/s|Mbits/sec|MiB/s)') {
        $mbps = [double]$matches[1]
    }

    if ($line -match 'Job\s+([0-9a-fA-F-]{36})') {
        $jobId = $matches[1]
    }
    elseif ($line -match '([0-9a-fA-F-]{36})') {
        $jobId = $matches[1]
    }

    if ($line -match '->\s*(.+)$') {
        $file = $matches[1]
    }

    return [PSCustomObject]@{
        RawLine            = $line
        IsJson             = $false
        Level              = $null
        Message            = $line
        JobId              = $jobId
        Percent            = $percent
        MBps               = $mbps
        FileName           = $file
        BytesTransferred   = $null
        TotalBytes         = $null
        JobStatus          = $null
        ErrorMessage       = $null
        ActiveConnections  = $null
        TransfersCompleted = $null
        TotalTransfers     = $null
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
            Add-Content -Path $script:LogTXTPath -Value ('Script Name   : {0}' -f $script:ScriptName)
            Add-Content -Path $script:LogTXTPath -Value ('Session ID    : {0}' -f $script:LogSessionId)
            Add-Content -Path $script:LogTXTPath -Value ('Started UTC   : {0}' -f (Get-LogDateTimeIso -DateTimeValue (Get-UtcNow)))
            Add-Content -Path $script:LogTXTPath -Value ('Computer      : {0}' -f $env:COMPUTERNAME)
            Add-Content -Path $script:LogTXTPath -Value ('User          : {0}' -f $env:USERNAME)
            Add-Content -Path $script:LogTXTPath -Value ('UTC Day       : {0}' -f $utcDay)
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

function New-DebugLogFiles {
    [CmdletBinding()]
    param()

    if (-not $script:DebugEnabled) { return }

    if (-not (Test-Path -Path $script:LogFolder)) {
        New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
    }

    $utcDay = Get-UtcDayStamp
    $script:DebugLogDay = $utcDay

    $script:DebugTXTPath  = Join-Path $script:LogFolder ("{0}_{1}_debug.txt"  -f $script:LogBaseName, $utcDay)
    $script:DebugCSVPath  = Join-Path $script:LogFolder ("{0}_{1}_debug.csv"  -f $script:LogBaseName, $utcDay)
    $script:DebugJSONPath = Join-Path $script:LogFolder ("{0}_{1}_debug.json" -f $script:LogBaseName, $utcDay)

    if (-not (Test-Path $script:DebugTXTPath)) {
        Add-Content -Path $script:DebugTXTPath -Value ('=' * 70)
        Add-Content -Path $script:DebugTXTPath -Value ('Script Name   : {0}' -f $script:ScriptName)
        Add-Content -Path $script:DebugTXTPath -Value ('Session ID    : {0}' -f $script:LogSessionId)
        Add-Content -Path $script:DebugTXTPath -Value ('Started UTC   : {0}' -f (Get-LogDateTimeIso -DateTimeValue (Get-UtcNow)))
        Add-Content -Path $script:DebugTXTPath -Value ('Computer      : {0}' -f $env:COMPUTERNAME)
        Add-Content -Path $script:DebugTXTPath -Value ('User          : {0}' -f $env:USERNAME)
        Add-Content -Path $script:DebugTXTPath -Value ('UTC Day       : {0}' -f $utcDay)
        Add-Content -Path $script:DebugTXTPath -Value ('=' * 70)
        Add-Content -Path $script:DebugTXTPath -Value ''
    }
}

function Ensure-DebugLogFiles {
    [CmdletBinding()]
    param()

    if (-not $script:DebugEnabled) { return }

    $utcDay = Get-UtcDayStamp

    $needsNewDebugFiles =
        (-not $script:DebugLogDay) -or
        ($script:DebugLogDay -ne $utcDay) -or
        (-not $script:DebugTXTPath) -or
        (-not $script:DebugCSVPath) -or
        (-not $script:DebugJSONPath) -or
        ($script:DebugTXTPath  -notmatch ("_{0}_debug\.txt$"  -f $utcDay)) -or
        ($script:DebugCSVPath  -notmatch ("_{0}_debug\.csv$"  -f $utcDay)) -or
        ($script:DebugJSONPath -notmatch ("_{0}_debug\.json$" -f $utcDay))

    if ($needsNewDebugFiles) {
        $script:DebugTXTPath  = $null
        $script:DebugCSVPath  = $null
        $script:DebugJSONPath = $null
        New-DebugLogFiles
    }
}

# ------------------------------------------------------------
# Logging Writers
# ------------------------------------------------------------
function Write-StructuredTextLogToPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $orderedData = New-OrderedLogRow -Row $Data
    $pairs = foreach ($field in $script:LogFieldOrder) {
        '{0}={1}' -f $field, $orderedData[$field]
    }

    Add-Content -Path $Path -Value (($pairs -join ' | '))
}

function Write-StructuredCsvLogToPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Row
    )

    $orderedRow = New-OrderedLogRow -Row $Row
    $obj = [PSCustomObject]$orderedRow

    if (-not (Test-Path -Path $Path)) {
        $obj | Export-Csv -Path $Path -NoTypeInformation
        return
    }

    $fileInfo = Get-Item -Path $Path -ErrorAction SilentlyContinue
    if ($fileInfo -and $fileInfo.Length -eq 0) {
        $obj | Export-Csv -Path $Path -NoTypeInformation
    }
    else {
        $obj | Export-Csv -Path $Path -NoTypeInformation -Append
    }
}

function Write-StructuredJsonLogToPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Row
    )

    $orderedObject = New-OrderedLogRow -Row $Row
    $jsonLine = ($orderedObject | ConvertTo-Json -Compress -Depth 5)
    Add-Content -Path $Path -Value $jsonLine
}

function Write-StructuredTextLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    if (-not $script:LoggingEnabled) { return }
    Ensure-LogFiles
    if (-not $script:LogTXTPath) { return }
    Write-StructuredTextLogToPath -Path $script:LogTXTPath -Data $Data
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
    Write-StructuredCsvLogToPath -Path $script:LogCSVPath -Row $Row
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
    Write-StructuredJsonLogToPath -Path $script:LogJSONPath -Row $Row
}

function Write-DebugLogEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Row
    )

    if (-not $script:DebugEnabled) { return }
    if ($script:DebugMode -ne 'D') { return }

    Ensure-DebugLogFiles

    if (-not $Row.ContainsKey('Timestamp')) {
        $Row.Timestamp = Get-Timestamp
    }

    $debugRow = @{}
    foreach ($key in $Row.Keys) {
        $debugRow[$key] = $Row[$key]
    }

    if (-not $debugRow.ContainsKey('LogSessionId')) {
        $debugRow.LogSessionId = $script:LogSessionId
    }

    $debugRow.LogFile = Get-DebugDisplayLogPath

    Write-StructuredTextLogToPath -Path $script:DebugTXTPath -Data $debugRow
    Write-StructuredCsvLogToPath  -Path $script:DebugCSVPath -Row $debugRow
    Write-StructuredJsonLogToPath -Path $script:DebugJSONPath -Row $debugRow
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

    if (-not $Row.ContainsKey('LogSessionId')) {
        $Row.LogSessionId = $script:LogSessionId
    }

    $status = ''
    if ($Row.ContainsKey('Status')) {
        $status = [string]$Row.Status
    }

    $isProgressEvent = ($status -eq 'Progress')
    $writeToMainLogs = $true

    if ($isProgressEvent) {
        if (-not $script:DebugEnabled) {
            $writeToMainLogs = $false
        }
        elseif ($script:DebugMode -eq 'D') {
            $writeToMainLogs = $false
        }
    }

    if ($writeToMainLogs) {
        $mainRow = @{}
        foreach ($key in $Row.Keys) {
            $mainRow[$key] = $Row[$key]
        }

        $mainRow.LogFile = Get-DisplayLogPath

        if ($script:LogType -eq 'txt' -or $script:LogType -eq 'all') {
            Write-StructuredTextLog -Data $mainRow
        }

        if ($script:LogType -eq 'csv' -or $script:LogType -eq 'all') {
            Write-StructuredCsvLog -Row $mainRow
        }

        if ($script:LogType -eq 'json' -or $script:LogType -eq 'all') {
            Write-StructuredJsonLog -Row $mainRow
        }
    }

    if ($script:DebugEnabled -and $script:DebugMode -eq 'D') {
        Write-DebugLogEvent -Row $Row
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

    $script:LoggingEnabled = Read-YesNo 'Enable file logging?'
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

    $script:DebugEnabled = Read-YesNo 'Debug Enable?'
    if ($script:DebugEnabled) {
        $script:DebugMode = Read-DebugMode
    }
    else {
        $script:DebugMode = $null
    }

    $script:LogPathDisplayed = $false
    Ensure-LogFiles

    if ($script:DebugEnabled -and $script:DebugMode -eq 'D') {
        Ensure-DebugLogFiles
    }
}

function Format-ByteSizeMB {
    [CmdletBinding()]
    param(
        [AllowNull()]$Bytes
    )

    if ($null -eq $Bytes -or [string]::IsNullOrWhiteSpace([string]$Bytes)) {
        return 'n/a'
    }

    try {
        return ('{0:N2} MB' -f ([double]$Bytes / 1MB))
    }
    catch {
        return 'n/a'
    }
}

function Get-ShortJobId {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$JobId
    )

    if ([string]::IsNullOrWhiteSpace($JobId)) {
        return 'Pending'
    }

    if ($JobId.Length -le 8) {
        return $JobId
    }

    return $JobId.Substring(0, 8) + '...'
}

function Write-AzCopyConsoleProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$ParsedLine
    )

    if (-not $script:LogToConsole) { return }

    $now = Get-Date
    $displayLine = $null

    if ($ParsedLine.Percent -ne $null -and "$($ParsedLine.Percent)" -ne '') {
        $pct = [math]::Round([double]$ParsedLine.Percent, 2)
        $pctBucket = [int][math]::Floor($pct)
        $done = Format-ByteSizeMB -Bytes $ParsedLine.BytesTransferred
        $total = Format-ByteSizeMB -Bytes $ParsedLine.TotalBytes
        $active = if ($ParsedLine.ActiveConnections -ne $null -and "$($ParsedLine.ActiveConnections)" -ne '') { [string]$ParsedLine.ActiveConnections } else { '-' }
        $state = if (-not [string]::IsNullOrWhiteSpace([string]$ParsedLine.JobStatus)) { [string]$ParsedLine.JobStatus } else { 'InProgress' }
        $completedTransfers = if ($ParsedLine.PSObject.Properties['TransfersCompleted'] -and -not [string]::IsNullOrWhiteSpace([string]$ParsedLine.TransfersCompleted)) { [string]$ParsedLine.TransfersCompleted } else { '' }
        $totalTransfers = if ($ParsedLine.PSObject.Properties['TotalTransfers'] -and -not [string]::IsNullOrWhiteSpace([string]$ParsedLine.TotalTransfers)) { [string]$ParsedLine.TotalTransfers } else { '' }

        $instantMBps = ''
        try {
            if ($ParsedLine.BytesTransferred -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$ParsedLine.BytesTransferred)) {
                $currBytes = [double]$ParsedLine.BytesTransferred
                if ($script:AzCopyLastBytesTransferred -ne $null -and $script:AzCopyLastBytesTimestamp) {
                    $elapsedSec = ($now - $script:AzCopyLastBytesTimestamp).TotalSeconds
                    if ($elapsedSec -gt 0) {
                        $deltaBytes = $currBytes - [double]$script:AzCopyLastBytesTransferred
                        if ($deltaBytes -ge 0) {
                            $instantMBps = [math]::Round(($deltaBytes / 1MB) / $elapsedSec, 2)
                        }
                    }
                }
                $script:AzCopyLastBytesTransferred = $currBytes
                $script:AzCopyLastBytesTimestamp = $now
            }
        }
        catch { }

        $shouldWrite = $false
        if ($state -eq 'Completed' -or $state -eq 'Failed') {
            $shouldWrite = $true
        }
        elseif ($script:AzCopyLastConsolePercentBucket -lt 0) {
            $shouldWrite = $true
        }
        elseif ($pctBucket -ge ($script:AzCopyLastConsolePercentBucket + 1)) {
            $shouldWrite = $true
        }
        elseif ($script:AzCopyLastConsoleWriteTime -and (($now - $script:AzCopyLastConsoleWriteTime).TotalSeconds -ge 30)) {
            $shouldWrite = $true
        }

        if (-not $shouldWrite) { return }

        $transferText = if ($completedTransfers -ne '' -and $totalTransfers -ne '') { ' | Files: {0}/{1}' -f $completedTransfers, $totalTransfers } else { '' }
        $speedText = if ($instantMBps -ne '') { ' | {0,7:N2} MB/s' -f [double]$instantMBps } else { '' }
        $displayLine = ('{0} | {1,6:N2}% | {2} / {3} | Active: {4,3}{5}{6} | Job: {7} | {8}' -f `
            $now.ToString('yyyy-MM-dd HH:mm:ss'),
            $pct,
            $done,
            $total,
            $active,
            $transferText,
            $speedText,
            (Get-ShortJobId -JobId $script:AzCopyJobId),
            $state)

        $script:AzCopyLastConsolePercentBucket = $pctBucket
        $script:AzCopyLastConsoleWriteTime = $now
    }
    else {
        $message = [string]$ParsedLine.Message
        if ([string]::IsNullOrWhiteSpace($message)) { return }
        if ($message.Trim().StartsWith('{')) { return }

        $messageLower = $message.ToLowerInvariant()
        if (($messageLower -notmatch 'scanning') -and ($messageLower -notmatch 'empty folders')) {
            return
        }

        $displayLine = ('{0} | {1}' -f $now.ToString('yyyy-MM-dd HH:mm:ss'), $message)
    }

    if ([string]::IsNullOrWhiteSpace($displayLine)) { return }
    if ($script:AzCopyLastConsoleDisplay -eq $displayLine) { return }

    Write-Host $displayLine
    $script:AzCopyLastConsoleDisplay = $displayLine
}

function Write-AzCopyProgressEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CopyId,
        [Parameter(Mandatory)][string]$ActionType,
        [Parameter(Mandatory)][string]$CopyMethod,
        [Parameter(Mandatory)][int]$ParallelCount,
        [Parameter(Mandatory)][string]$WorkerId,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][datetime]$StartTime,
        [Parameter(Mandatory)][object]$ParsedLine
    )

    if ($ParsedLine.JobId -and -not $script:AzCopyJobId) {
        $script:AzCopyJobId = [string]$ParsedLine.JobId
    }

    if ($ParsedLine.JobStatus) {
        $script:AzCopyLastJobStatus = [string]$ParsedLine.JobStatus
    }

    if ($ParsedLine.ErrorMessage -and -not [string]::IsNullOrWhiteSpace([string]$ParsedLine.ErrorMessage)) {
        $script:AzCopyLastErrorMsg = [string]$ParsedLine.ErrorMessage
    }

    $percent = if ($null -ne $ParsedLine.Percent -and "$($ParsedLine.Percent)" -ne '') { $ParsedLine.Percent } else { '' }
    if ($percent -ne '') { $script:AzCopyLastPercent = $percent }
    $mbps = if ($null -ne $ParsedLine.MBps -and "$($ParsedLine.MBps)" -ne '') { $ParsedLine.MBps } else { '' }

    $message = if (-not [string]::IsNullOrWhiteSpace($ParsedLine.Message)) {
        $ParsedLine.Message
    }
    else {
        $ParsedLine.RawLine
    }

    $row = @{
        Timestamp         = Get-Timestamp
        LogSessionId      = $script:LogSessionId
        CopyId            = $CopyId
        EventType         = Get-EventType -ActionType $ActionType
        Status            = 'Progress'
        CopyMethod        = $CopyMethod
        ParallelCount     = $ParallelCount
        WorkerId          = $WorkerId
        FileName          = $ParsedLine.FileName
        SourcePath        = $SourcePath
        DestinationPath   = $DestinationPath
        FileSizeBytes     = ''
        FileSizeKB        = ''
        FileSizeMB        = ''
        FileSizeGB        = ''
        FileSizeTB        = ''
        BytesTransferred  = $ParsedLine.BytesTransferred
        Percent           = $percent
        MBps              = $mbps
        GBps              = if ($mbps -ne '') { [math]::Round(([double]$mbps / 1024), 4) } else { '' }
        ETA               = ''
        StartTime         = $StartTime
        EndTime           = ''
        TotalTime         = ''
        AverageSpeedMBps  = ''
        LogFile           = ''
        Message           = $message
        ErrorMessage      = ''
    }

    if ($script:LoggingEnabled) {
        Write-LogEvent -Row $row
    }

    Write-AzCopyConsoleProgress -ParsedLine $ParsedLine
}

function Get-AzCopyVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AzCopyPath
    )

    try {
        $output = & $AzCopyPath --version 2>&1
        return (($output | Out-String).Trim())
    }
    catch {
        return 'Unknown'
    }
}

function Get-AzCopyJobShowJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AzCopyPath,
        [Parameter(Mandatory)][string]$JobId
    )

    try {
        $output = & $AzCopyPath jobs show $JobId --with-status=All --output-type=json 2>&1
        $text = ($output | Out-String).Trim()
        return (Try-ConvertFromJson -Text $text)
    }
    catch {
        return $null
    }
}

function Write-AzCopyPerFileJobDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AzCopyPath,
        [Parameter(Mandatory)][string]$JobId,
        [Parameter(Mandatory)][string]$CopyId,
        [Parameter(Mandatory)][string]$ActionType,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$CopyMethod,
        [Parameter(Mandatory)][int]$ParallelCount,
        [Parameter(Mandatory)][datetime]$StartTime
    )

    $jobJson = Get-AzCopyJobShowJson -AzCopyPath $AzCopyPath -JobId $JobId
    if (-not $jobJson) { return }

    $collections = @()
    foreach ($name in @('Transfers','transfers','Details','details','Entries','entries')) {
        $prop = $jobJson.PSObject.Properties[$name]
        if ($prop -and $prop.Value) {
            if ($prop.Value -is [System.Collections.IEnumerable] -and -not ($prop.Value -is [string])) {
                $collections += @($prop.Value)
            }
        }
    }

    foreach ($transfer in $collections) {
        $status = Get-FirstPropertyValue -Object $transfer -CandidateNames @('Status','status','TransferStatus','transferStatus')
        $src    = Get-FirstPropertyValue -Object $transfer -CandidateNames @('Source','source','Src','src')
        $dst    = Get-FirstPropertyValue -Object $transfer -CandidateNames @('Destination','destination','Dst','dst')
        $name   = Get-FirstPropertyValue -Object $transfer -CandidateNames @('EntityName','entityName','FileName','fileName','RelativePath','relativePath')
        $size   = Get-FirstPropertyValue -Object $transfer -CandidateNames @('ContentLength','contentLength','BytesOverWire','bytesOverWire','Size','size')
        $err    = Get-FirstPropertyValue -Object $transfer -CandidateNames @('ErrorMsg','errorMsg','ErrorMessage','errorMessage','Description','description')

        $statusOut = switch -Regex ($status) {
            'Success' { 'Complete' }
            'Failed'  { 'Failed' }
            default   { 'Progress' }
        }

        Write-LogEvent -Row @{
            Timestamp         = Get-Timestamp
            LogSessionId      = $script:LogSessionId
            CopyId            = $CopyId
            EventType         = Get-EventType -ActionType $ActionType
            Status            = $statusOut
            CopyMethod        = $CopyMethod
            ParallelCount     = $ParallelCount
            WorkerId          = 'AzCopy-JobShow'
            FileName          = $name
            SourcePath        = if ($src) { $src } else { $SourcePath }
            DestinationPath   = if ($dst) { $dst } else { $DestinationPath }
            FileSizeBytes     = $size
            FileSizeKB        = if ($size) { [math]::Round(([double]$size / 1KB), 2) } else { '' }
            FileSizeMB        = if ($size) { [math]::Round(([double]$size / 1MB), 2) } else { '' }
            FileSizeGB        = if ($size) { [math]::Round(([double]$size / 1GB), 2) } else { '' }
            FileSizeTB        = if ($size) { [math]::Round(([double]$size / 1TB), 4) } else { '' }
            BytesTransferred  = $size
            Percent           = if ($statusOut -eq 'Complete') { 100 } else { '' }
            MBps              = ''
            GBps              = ''
            ETA               = ''
            StartTime         = $StartTime
            EndTime           = ''
            TotalTime         = ''
            AverageSpeedMBps  = ''
            LogFile           = ''
            Message           = "Per-file AzCopy transfer detail captured from jobs show."
            ErrorMessage      = $err
        }
    }
}

function Invoke-AzCopyResumeJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AzCopyPath,
        [Parameter(Mandatory)][string]$JobId
    )

    try {
        $output = & $AzCopyPath jobs resume $JobId --output-type=json 2>&1
        return [PSCustomObject]@{
            Success = $true
            Output  = ($output | Out-String)
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Output  = $_.Exception.Message
        }
    }
}

# ------------------------------------------------------------
# Summary Function
# ------------------------------------------------------------
function Show-ScriptSummary {
    param(
        [string]$Title = 'FILE COPY RESULTS',
        [string]$ActionType = 'Copy'
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
    Write-Host "Transfer Start Time:  $copyStartTime" -ForegroundColor White
    Write-Host "Transfer End Time:    $copyEndTime" -ForegroundColor White
    Write-Host "Transfer Duration:    $copyDuration" -ForegroundColor White
    Write-Host "Session ID:           $($script:LogSessionId)" -ForegroundColor White
    Write-Host "AzCopy Job ID:        $($script:AzCopyJobId)" -ForegroundColor White
    Write-Host "Total Expected:       $($expectedItems.Count)" -ForegroundColor White
    Write-Host "Total Copied:         $($copiedItems.Count)" -ForegroundColor Green
    Write-Host "Total Skipped:        $($skippedItems.Count)" -ForegroundColor Yellow
    Write-Host "Total Failed:         $($failedItems.Count)" -ForegroundColor Red

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
        Write-Host "Total Missed:         $($missedItems.Count)" -ForegroundColor Red
        foreach ($m in $missedItems) {
            Write-Host " [X] Missed: $m" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Total Missed:         0" -ForegroundColor Gray
    }

    $statusColor = if (($failedItems.Count + $missedItems.Count) -gt 0) { 'Red' } else { 'Blue' }
    Write-Host '--------------------------' -ForegroundColor $statusColor
    Write-Host 'All transfer operations completed.'
    Write-Host ''
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

    $azCopyPath  = Read-AzCopyPath
    $source      = Read-SourceOrDestinationEndpoint -Role 'Source'
    $destination = Read-SourceOrDestinationEndpoint -Role 'Destination'

    if ($source.Type -eq 'Local' -and $destination.Type -eq 'Local') {
        throw 'AzCopy for this script should be used with at least one Blob endpoint. Local-to-Local is not supported in this AzCopy version.'
    }

    $copyMethod = Read-CopyMethod
    $parallelCount = if ($copyMethod -eq 'Parallel') {
        Read-ParallelCount -Default 16 -Min 1 -Max 128
    }
    else {
        1
    }

    $overwriteMode = 'true'
    while ($true) {
        $raw = (Read-Host 'Overwrite existing destination data? [Y]es | [N]o | [P]rompt-if-supported').Trim().ToLower()
        switch ($raw) {
            'y' { $overwriteMode = 'true'; break }
            'n' { $overwriteMode = 'false'; break }
            'p' { $overwriteMode = 'prompt'; break }
            default { continue }
        }

        break
    }

    $retryCount = 2
    $retryRaw = Read-Host 'Retry Count on failure (Default: 2)'
    if (-not [string]::IsNullOrWhiteSpace($retryRaw)) {
        $parsed = 0
        if ([int]::TryParse($retryRaw, [ref]$parsed) -and $parsed -ge 0 -and $parsed -le 20) {
            $retryCount = $parsed
        }
    }

    $resumeOnFailure = Read-YesNo 'Resume failed AzCopy job when possible?'
    $fromTo = Get-AzCopyFromToValue -SourceType $source.Type -DestinationType $destination.Type

    return [PSCustomObject]@{
        ActionType         = $ActionType
        AzCopyPath         = $azCopyPath
        SourceType         = $source.Type
        Source             = $source.Value
        SourceDisplay      = $source.DisplayValue
        DestinationType    = $destination.Type
        Destination        = $destination.Value
        DestinationDisplay = $destination.DisplayValue
        CopyMethod         = $copyMethod
        ParallelCount      = $parallelCount
        OverwriteMode      = $overwriteMode
        RetryCount         = $retryCount
        ResumeOnFailure    = $resumeOnFailure
        FromTo             = $fromTo
    }
}

# ------------------------------------------------------------
# Main Processing
# ------------------------------------------------------------

function Read-AppendedFileLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [long]$StartPosition
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{
            Lines       = @()
            NewPosition = $StartPosition
        }
    }

    $fileInfo = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $fileInfo) {
        return [PSCustomObject]@{
            Lines       = @()
            NewPosition = $StartPosition
        }
    }

    if ($fileInfo.Length -lt $StartPosition) {
        $StartPosition = 0
    }

    $stream = $null
    $reader = $null

    try {
        $stream = New-Object System.IO.FileStream(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )

        [void]$stream.Seek($StartPosition, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream)

        $lines = New-Object System.Collections.Generic.List[string]
        while (($line = $reader.ReadLine()) -ne $null) {
            [void]$lines.Add($line)
        }

        $newPosition = $stream.Position

        return [PSCustomObject]@{
            Lines       = @($lines)
            NewPosition = $newPosition
        }
    }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
}

function Process-AzCopyOutputLines {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$Lines = @(),

        [Parameter(Mandatory)]
        [string]$StreamName,

        [Parameter(Mandatory)]
        [string]$CopyId,

        [Parameter(Mandatory)]
        [pscustomobject]$InputObject,

        [Parameter(Mandatory)]
        [string]$WorkerId,

        [Parameter(Mandatory)]
        [datetime]$StartTime
    )

    if (-not $Lines -or $Lines.Count -eq 0) {
        return
    }

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $parsed = Parse-AzCopyOutputLine -Line $line
        if ($parsed) {
            Write-AzCopyProgressEvent -CopyId $CopyId -ActionType $InputObject.ActionType -CopyMethod $InputObject.CopyMethod -ParallelCount $InputObject.ParallelCount -WorkerId $WorkerId -SourcePath $InputObject.SourceDisplay -DestinationPath $InputObject.DestinationDisplay -StartTime $StartTime -ParsedLine $parsed
        }
    }
}


function Invoke-AzCopyTransfer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$InputObject
    )

    $script:AzCopyPath            = $InputObject.AzCopyPath
    $script:AzCopyRetryCount      = $InputObject.RetryCount
    $script:AzCopyResumeOnFailure = $InputObject.ResumeOnFailure
    $script:AzCopyOverwriteMode   = $InputObject.OverwriteMode
    $script:AzCopyFromTo          = $InputObject.FromTo
    $script:AzCopyJobId           = $null
    $script:AzCopyLastConsoleDisplay = $null
    $script:AzCopyLastConsolePercentBucket = -1
    $script:AzCopyLastConsoleWriteTime = $null
    $script:AzCopyLastBytesTransferred = $null
    $script:AzCopyLastBytesTimestamp = $null

    Initialize-AzCopyFolders

    $sourceValidation = if ($InputObject.SourceType -eq 'Blob') {
        Test-SasAccessForAction -Target $InputObject.Source -Role 'Source'
    } else {
        [PSCustomObject]@{ Valid = $true; Message = 'Source is local path.' }
    }

    $destinationValidation = if ($InputObject.DestinationType -eq 'Blob') {
        Test-SasAccessForAction -Target $InputObject.Destination -Role 'Destination'
    } else {
        [PSCustomObject]@{ Valid = $true; Message = 'Destination is local path.' }
    }

    if (-not $sourceValidation.Valid)      { throw $sourceValidation.Message }
    if (-not $destinationValidation.Valid) { throw $destinationValidation.Message }

    $copyId    = [guid]::NewGuid().Guid
    $workerId  = 'AzCopy-1'
    $startTime = Get-Date
    $attempt   = 0
    $completed = $false

    $script:DefaultList = @('AzCopy Transfer')

    $azVersion = Get-AzCopyVersion -AzCopyPath $InputObject.AzCopyPath

    if ($script:LogToConsole) {
        Write-Host ''
        Write-Host 'AzCopy Transfer with Live Metrics + Summary' -ForegroundColor Cyan
        Write-Host "AzCopy Version     : $azVersion" -ForegroundColor White
        Write-Host "Source             : $($InputObject.SourceDisplay)" -ForegroundColor White
        Write-Host "Destination        : $($InputObject.DestinationDisplay)" -ForegroundColor White
        Write-Host "Copy Method        : $($InputObject.CopyMethod)" -ForegroundColor White
        Write-Host "Parallel Count     : $($InputObject.ParallelCount)" -ForegroundColor White
        Write-Host "Overwrite Mode     : $($InputObject.OverwriteMode)" -ForegroundColor White
        Write-Host "Resume On Failure  : $($InputObject.ResumeOnFailure)" -ForegroundColor White
        Write-Host "Retry Count        : $($InputObject.RetryCount)" -ForegroundColor White
        Write-Host "AzCopy Log Folder  : $script:AzCopyLogFolder" -ForegroundColor White
        Write-Host "AzCopy Plan Folder : $script:AzCopyPlanFolder" -ForegroundColor White
        Write-Host '-------------------------------------------------------------' -ForegroundColor DarkGray
    }

    if ($script:LoggingEnabled) {
        Write-LogEvent -Row @{
            Timestamp         = Get-Timestamp
            LogSessionId      = $script:LogSessionId
            CopyId            = $copyId
            EventType         = Get-EventType -ActionType $InputObject.ActionType
            Status            = 'Start'
            CopyMethod        = $InputObject.CopyMethod
            ParallelCount     = $InputObject.ParallelCount
            WorkerId          = $workerId
            FileName          = ''
            SourcePath        = $InputObject.SourceDisplay
            DestinationPath   = $InputObject.DestinationDisplay
            FileSizeBytes     = ''
            FileSizeKB        = ''
            FileSizeMB        = ''
            FileSizeGB        = ''
            FileSizeTB        = ''
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
            Message           = "AzCopy transfer started. Source validation: $($sourceValidation.Message) Destination validation: $($destinationValidation.Message)"
            ErrorMessage      = ''
        }
    }

    while (-not $completed -and $attempt -le $InputObject.RetryCount) {
        $attempt++

        $argList = New-Object System.Collections.Generic.List[string]
        foreach ($arg in @(
            'copy',
            $InputObject.Source,
            $InputObject.Destination,
            '--recursive=true',
            "--overwrite=$($InputObject.OverwriteMode)",
            '--output-type=json',
            '--output-level=default',
            '--log-level=INFO'
        )) {
            [void]$argList.Add($arg)
        }

        if ($InputObject.FromTo) {
            [void]$argList.Add("--from-to=$($InputObject.FromTo)")
        }

        if ($InputObject.ActionType -eq 'Move') {
            [void]$argList.Add('--delete-source=true')
        }

        $quotedArgs = (($argList | ForEach-Object {
            if ($_ -match '[\s"]') {
                '"' + (($_ -replace '"','\"')) + '"'
            }
            else {
                $_
            }
        }) -join ' ')

        $stdOutPath = Join-Path $env:TEMP ("azcopy_stdout_{0}_{1}_{2}.log" -f (Get-UtcDayStamp), $script:LogSessionId, $attempt)
        $stdErrPath = Join-Path $env:TEMP ("azcopy_stderr_{0}_{1}_{2}.log" -f (Get-UtcDayStamp), $script:LogSessionId, $attempt)
        $script:AzCopyTempStdOutPath = $stdOutPath
        $script:AzCopyTempStdErrPath = $stdErrPath

        if (Test-Path -LiteralPath $stdOutPath) { Remove-Item -LiteralPath $stdOutPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stdErrPath) { Remove-Item -LiteralPath $stdErrPath -Force -ErrorAction SilentlyContinue }

        if ($script:LogToConsole) {
            Write-Host "Starting AzCopy attempt $attempt of $($InputObject.RetryCount + 1)..." -ForegroundColor Cyan
        }

        $previousConcurrency = [System.Environment]::GetEnvironmentVariable('AZCOPY_CONCURRENCY_VALUE', 'Process')
        $previousLogLocation = [System.Environment]::GetEnvironmentVariable('AZCOPY_LOG_LOCATION', 'Process')
        $previousPlanLocation = [System.Environment]::GetEnvironmentVariable('AZCOPY_JOB_PLAN_LOCATION', 'Process')

        [System.Environment]::SetEnvironmentVariable('AZCOPY_CONCURRENCY_VALUE', [string]$InputObject.ParallelCount, 'Process')
        [System.Environment]::SetEnvironmentVariable('AZCOPY_LOG_LOCATION', $script:AzCopyLogFolder, 'Process')
        [System.Environment]::SetEnvironmentVariable('AZCOPY_JOB_PLAN_LOCATION', $script:AzCopyPlanFolder, 'Process')

        $process = Start-Process -FilePath $InputObject.AzCopyPath -ArgumentList $quotedArgs -RedirectStandardOutput $stdOutPath -RedirectStandardError $stdErrPath -PassThru -WindowStyle Hidden

        $stdoutPos = 0L
        $stderrPos = 0L

        while (-not $process.HasExited) {
            $stdoutRead = Read-AppendedFileLines -Path $stdOutPath -StartPosition $stdoutPos
            $stdoutPos = $stdoutRead.NewPosition
            Process-AzCopyOutputLines -Lines $stdoutRead.Lines -StreamName 'STDOUT' -CopyId $copyId -InputObject $InputObject -WorkerId $workerId -StartTime $startTime

            $stderrRead = Read-AppendedFileLines -Path $stdErrPath -StartPosition $stderrPos
            $stderrPos = $stderrRead.NewPosition
            Process-AzCopyOutputLines -Lines $stderrRead.Lines -StreamName 'STDERR' -CopyId $copyId -InputObject $InputObject -WorkerId $workerId -StartTime $startTime

            Start-Sleep -Milliseconds 300
        }

        $process.WaitForExit()

        [System.Environment]::SetEnvironmentVariable('AZCOPY_CONCURRENCY_VALUE', $previousConcurrency, 'Process')
        [System.Environment]::SetEnvironmentVariable('AZCOPY_LOG_LOCATION', $previousLogLocation, 'Process')
        [System.Environment]::SetEnvironmentVariable('AZCOPY_JOB_PLAN_LOCATION', $previousPlanLocation, 'Process')

        $stdoutRead = Read-AppendedFileLines -Path $stdOutPath -StartPosition $stdoutPos
        $stdoutPos = $stdoutRead.NewPosition
        Process-AzCopyOutputLines -Lines $stdoutRead.Lines -StreamName 'STDOUT' -CopyId $copyId -InputObject $InputObject -WorkerId $workerId -StartTime $startTime

        $stderrRead = Read-AppendedFileLines -Path $stdErrPath -StartPosition $stderrPos
        $stderrPos = $stderrRead.NewPosition
        Process-AzCopyOutputLines -Lines $stderrRead.Lines -StreamName 'STDERR' -CopyId $copyId -InputObject $InputObject -WorkerId $workerId -StartTime $startTime

        $exitCode = $process.ExitCode
        $endTime  = Get-Date
        $duration = $endTime - $startTime

        $jobCompletedSuccessfully = (
            ($script:AzCopyLastJobStatus -eq 'Completed') -and
            (($script:AzCopyLastErrorMsg -eq $null) -or [string]::IsNullOrWhiteSpace([string]$script:AzCopyLastErrorMsg))
        )

        $isSuccess = ($exitCode -eq 0) -or (($null -eq $exitCode -or [string]::IsNullOrWhiteSpace([string]$exitCode)) -and $jobCompletedSuccessfully)

        if ($isSuccess) {
            $completed = $true

            if ($script:LoggingEnabled) {
                Write-LogEvent -Row @{
                    Timestamp         = Get-Timestamp
                    LogSessionId      = $script:LogSessionId
                    CopyId            = $copyId
                    EventType         = Get-EventType -ActionType $InputObject.ActionType
                    Status            = 'Complete'
                    CopyMethod        = $InputObject.CopyMethod
                    ParallelCount     = $InputObject.ParallelCount
                    WorkerId          = $workerId
                    FileName          = ''
                    SourcePath        = $InputObject.SourceDisplay
                    DestinationPath   = $InputObject.DestinationDisplay
                    FileSizeBytes     = ''
                    FileSizeKB        = ''
                    FileSizeMB        = ''
                    FileSizeGB        = ''
                    FileSizeTB        = ''
                    BytesTransferred  = ''
                    Percent           = 100
                    MBps              = ''
                    GBps              = ''
                    ETA               = '00:00:00'
                    StartTime         = $startTime
                    EndTime           = $endTime
                    TotalTime         = $duration
                    AverageSpeedMBps  = ''
                    LogFile           = ''
                    Message           = "AzCopy transfer completed successfully. JobId: $($script:AzCopyJobId) FinalStatus: $($script:AzCopyLastJobStatus)"
                    ErrorMessage      = ''
                }
            }

            if ($script:AzCopyJobId -and $script:LoggingEnabled) {
                Write-AzCopyPerFileJobDetails -AzCopyPath $InputObject.AzCopyPath -JobId $script:AzCopyJobId -CopyId $copyId -ActionType $InputObject.ActionType -SourcePath $InputObject.SourceDisplay -DestinationPath $InputObject.DestinationDisplay -CopyMethod $InputObject.CopyMethod -ParallelCount $InputObject.ParallelCount -StartTime $startTime
            }

            $script:SuccessList += 'AzCopy Transfer'
        }
        else {
            $resumeTried = $false
            $resumeSucceeded = $false
            $resumeOutput = ''

            if ($script:AzCopyResumeOnFailure -and $script:AzCopyJobId) {
                $resumeTried = $true
                $resumeResult = Invoke-AzCopyResumeJob -AzCopyPath $InputObject.AzCopyPath -JobId $script:AzCopyJobId
                $resumeSucceeded = $resumeResult.Success
                $resumeOutput = $resumeResult.Output
            }

            $errTail = @()
            if (Test-Path -LiteralPath $stdErrPath) {
                $errTail += @(Get-Content -LiteralPath $stdErrPath -Tail 10 -ErrorAction SilentlyContinue)
            }
            if (Test-Path -LiteralPath $stdOutPath) {
                $errTail += @(Get-Content -LiteralPath $stdOutPath -Tail 10 -ErrorAction SilentlyContinue)
            }
            $errText = if ($errTail.Count -gt 0) { ($errTail -join ' || ') } else { 'See AzCopy raw output log for details.' }

            if ($script:LoggingEnabled) {
                Write-LogEvent -Row @{
                    Timestamp         = Get-Timestamp
                    LogSessionId      = $script:LogSessionId
                    CopyId            = $copyId
                    EventType         = Get-EventType -ActionType $InputObject.ActionType
                    Status            = 'Failed'
                    CopyMethod        = $InputObject.CopyMethod
                    ParallelCount     = $InputObject.ParallelCount
                    WorkerId          = $workerId
                    FileName          = ''
                    SourcePath        = $InputObject.SourceDisplay
                    DestinationPath   = $InputObject.DestinationDisplay
                    FileSizeBytes     = ''
                    FileSizeKB        = ''
                    FileSizeMB        = ''
                    FileSizeGB        = ''
                    FileSizeTB        = ''
                    BytesTransferred  = ''
                    Percent           = ''
                    MBps              = ''
                    GBps              = ''
                    ETA               = ''
                    StartTime         = $startTime
                    EndTime           = $endTime
                    TotalTime         = $duration
                    AverageSpeedMBps  = ''
                    LogFile           = ''
                    Message           = "AzCopy failed on attempt $attempt. ResumeTried=$resumeTried ResumeSucceeded=$resumeSucceeded JobId=$($script:AzCopyJobId) FinalStatus=$($script:AzCopyLastJobStatus)"
                    ErrorMessage      = "ExitCode=$exitCode | LastError=$($script:AzCopyLastErrorMsg) | $errText"
                }
            }

            if ($attempt -le $InputObject.RetryCount) {
                if ($script:LogToConsole) {
                    Write-Host "AzCopy attempt $attempt failed. Retrying in $($script:AzCopyRetryDelaySec) seconds..." -ForegroundColor Yellow
                }
                Start-Sleep -Seconds $script:AzCopyRetryDelaySec
            }
            else {
                $script:FailedList += 'AzCopy Transfer'
                throw "AzCopy failed after $attempt attempt(s). ExitCode=$exitCode JobId=$($script:AzCopyJobId) FinalStatus=$($script:AzCopyLastJobStatus). Review the AzCopy output/log above for the exact flag or command error."
            }
        }

        if (Test-Path -LiteralPath $stdOutPath) {
            Remove-Item -LiteralPath $stdOutPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $stdErrPath) {
            Remove-Item -LiteralPath $stdErrPath -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path Env:AZCOPY_CONCURRENCY_VALUE) {
        Remove-Item Env:AZCOPY_CONCURRENCY_VALUE -ErrorAction SilentlyContinue
    }
    $script:AzCopyTempStdOutPath = $null
    $script:AzCopyTempStdErrPath = $null
}

# ------------------------------------------------------------
# Script Entry Point
# ------------------------------------------------------------
try {
    $actionType = Read-ActionType

    Write-Host ('Starting script: {0}' -f $script:ScriptName) -ForegroundColor Cyan

    $script:RunStartTime = Get-Date
    $script:OverwriteAllMode = $false
    $script:LogSessionId = [guid]::NewGuid().Guid

    $inputs = Read-ScriptInputs -ActionType $actionType
    Initialize-Logging
    Invoke-AzCopyTransfer -InputObject $inputs

    $script:RunEndTime = Get-Date

    if ($script:LogToConsole) {
        Write-Host ''
        Show-ScriptSummary -Title 'AZCOPY TRANSFER RESULTS' -ActionType $actionType
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
