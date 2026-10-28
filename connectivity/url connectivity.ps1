# ==============================================================================
# SCRIPT:  url connectivity.ps1
# CONTEXT: URL_CURL_CONNECTIVITY_TESTER
# VERSION: V1
# UPDATED: 2026-10-28 00:00:00
# ==============================================================================

# ==============================================================================
# HOW TO RUN THIS SCRIPT
# ------------------------------------------------------------------------------
# This script takes NO command-line parameters - every input (URL or input
# file, interval, comment, output mode, log format, log folder, debug mode)
# is gathered through interactive prompts at runtime.
#
# Option 1 - Run as a saved .ps1 file (recommended):
#   1. Save this file as: url connectivity.ps1
#   2. Open PowerShell and navigate to the folder containing the file.
#   3. Run:  & ".\url connectivity.ps1"
#   4. Follow the on-screen prompts.
#   When run this way, the default log folder offered at the logging prompt
#   will be a "Logs" subfolder created next to this script file.
#
# Option 2 - Paste directly into an open PowerShell console:
#   1. Copy the entire script.
#   2. Paste into a running PowerShell window and press Enter.
#   3. Follow the on-screen prompts.
#   When run this way, the default log folder offered will instead be a
#   "Logs" subfolder next to your current working directory. You can always
#   choose [C]ustom at the log folder prompt to specify a different path.
#
# Continuous Mode:
#   Enter an interval greater than 0 to curl the URL(s) continuously. Press
#   Ctrl+C to stop - the session end log entry and summary are still written.
#
# Curl Options:
#   Every request uses the same curl.exe options defined in $script:CurlArgs
#   below (-I = HEAD request). Edit that one line to change them for all URLs.
#
# Execution Policy:
#   If running as a saved .ps1 and PowerShell blocks it, you may need to
#   allow script execution for the current session:
#     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# ==============================================================================

$VariableContext = "URL_CURL_CONNECTIVITY_TESTER"
$Version         = "V1"
$LastUpdated     = "2026-10-28 00:00:00"
$ScriptName      = $MyInvocation.MyCommand.Name

# Curl options applied to every request.
#   -I  = HEAD request (faster)
#   -s  = hide the progress meter
#   -S  = still show error text when -s is used (e.g. "Could not resolve host")
$script:CurlArgs = @('-I', '-s', '-S')

# ==============================================================================
# HEADER
# ==============================================================================
Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " SCRIPT:  $ScriptName"                                  -ForegroundColor Cyan
Write-Host " CONTEXT: $VariableContext"                             -ForegroundColor Cyan
Write-Host " VERSION: $Version"                                     -ForegroundColor Cyan
Write-Host " UPDATED: $LastUpdated"                                 -ForegroundColor Cyan
Write-Host "****************************************************"   -ForegroundColor White
Write-Host " Script Purpose:"                                       -ForegroundColor Yellow
Write-Host " Tests HTTP/HTTPS connectivity from this host to one or"
Write-Host " more URLs using curl.exe with the same options for every"
Write-Host " request. Resolves each URL's host name/IP and this"
Write-Host " machine's own source host name/IP once at startup."
Write-Host " Outputs a single line per URL showing source, destination,"
Write-Host " HTTP status, response time, and SUCCESS/FAILED."
Write-Host " Status 200-399 = SUCCESS, anything else = FAILED."
Write-Host " Supports single-URL and CSV file input modes, run once"
Write-Host " or continuously on an interval."
Write-Host ""
Write-Host " Input/Steps Required:"                                 -ForegroundColor Yellow
Write-Host " 1. Choose single URL or CSV input file."
Write-Host " 2. Set a test interval (0 = run once)."
Write-Host " 3. Enter an optional comment (single URL mode)."
Write-Host " 4. Configure output mode (Screen / Log File / Both)."
Write-Host " 5. Source host (this machine) is identified automatically"
Write-Host "    - no input required."
Write-Host ""
Write-Host " Curl Options (all requests):"                          -ForegroundColor Yellow
Write-Host (" curl.exe {0} <url>" -f ($script:CurlArgs -join ' '))
Write-Host ""
Write-Host " CSV Input File Format Example:"                        -ForegroundColor Yellow
Write-Host " ----------------------------------------"
Write-Host " URL,Comment"
Write-Host " https://portal.domain.com,Public portal"
Write-Host " https://10.0.5.45/intranetservice,"
Write-Host " #https://disabled.domain.com,Skipped"
Write-Host " ----------------------------------------"
Write-Host " Notes:"
Write-Host "  - Header row is optional; a first column value of"
Write-Host "    'url' or 'target' is auto-detected and skipped."
Write-Host "  - Lines starting with # are skipped."
Write-Host "  - Column 2 (Comment) is optional per row."
Write-Host "****************************************************"   -ForegroundColor White

$runChoice = ""
Write-Host "`nDo you want to run this script?" -ForegroundColor White
while ($runChoice -notin @('y','e')) {
    $runChoice = (Read-Host " [Y]es | [E]xit").ToLower()
    if ($runChoice -notin @('y','e')) {
        Write-Host " Invalid selection. Please enter Y or E." -ForegroundColor Red
    }
}
if ($runChoice -eq 'e') {
    Write-Host "`nExiting script. No action has been taken. Have a great day!" -ForegroundColor Yellow
    exit
}

$clearChoice = ""
Write-Host "`nDo you want to clear the terminal before continuing?" -ForegroundColor White
while ($clearChoice -notin @('y','n')) {
    $clearChoice = (Read-Host " [Y]es | [N]o").ToLower()
    if ($clearChoice -notin @('y','n')) {
        Write-Host " Invalid selection. Please enter Y or N." -ForegroundColor Red
    }
}
if ($clearChoice -eq 'y') { Clear-Host }

Write-Host "Proceeding..." -ForegroundColor Gray
Write-Host "`n--- Execution Started ---" -ForegroundColor Green

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "`n curl.exe was not found on this machine. Exiting." -ForegroundColor Red
    exit
}

# ==============================================================================
# GLOBAL LOGGING STATE  (design template - logging and output v2)
# ==============================================================================
$script:LoggingEnabled   = $false
$script:LogFolder        = $null
$script:LogBaseName      = $null
$script:LogTXTPath       = $null
$script:LogCSVPath       = $null
$script:LogJSONPath      = $null
$script:LogDay           = $null
$script:LogType          = $null
$script:LogPathDisplayed = $false
$script:LogToConsole     = $true
$script:OutputMode       = 'screen'
$script:LogSessionId     = [guid]::NewGuid().Guid

$script:DebugEnabled     = $false
$script:DebugMode        = $null
$script:DebugTXTPath     = $null
$script:DebugCSVPath     = $null
$script:DebugJSONPath    = $null
$script:DebugLogDay      = $null

# Source host identity - resolved once at startup, reused for entire session
$script:SourceHostName     = ''
$script:SourceHostIP       = ''
$script:SourceDisplayLabel = ''

$script:LogFieldOrder = @(
    'Timestamp',
    'LogSessionId',
    'ScriptName',
    'SourceHostName',
    'SourceHostIP',
    'Level',
    'Status',
    'Message',
    'ErrorMessage',
    'TargetInput',
    'ResolvedDNSName',
    'ResolvedIP',
    'HttpStatus',
    'CurlExitCode',
    'ResponseTimeMs',
    'ResultDetail',
    'Comment'
)

# ==============================================================================
# LOGGING HELPERS
# ==============================================================================
function Get-UtcNow      { return [DateTime]::UtcNow }
function Get-UtcDayStamp { return (Get-UtcNow).ToString('yyyyMMdd') }
function Get-Timestamp   { return [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }

function Get-LogColor {
    param([ValidateSet('INFO','SUCCESS','WARN','ERROR','DEBUG')][string]$Level)
    switch ($Level) {
        'INFO'    { return 'White'  }
        'SUCCESS' { return 'Green'  }
        'WARN'    { return 'Yellow' }
        'ERROR'   { return 'Red'    }
        'DEBUG'   { return 'Cyan'   }
    }
}

function Convert-ToFlatString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value)             { return '' }
    if ($Value -is [System.TimeSpan]) { return $Value.ToString() }
    if ($Value -is [System.DateTime]) { return ([datetime]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
    $text = [string]$Value
    $text = $text -replace '[\r\n]+',' '
    return $text.Trim()
}

function New-OrderedLogRow {
    param([hashtable]$Row)
    $ordered = [ordered]@{}
    foreach ($field in $script:LogFieldOrder) {
        $ordered[$field] = if ($Row.ContainsKey($field)) { Convert-ToFlatString $Row[$field] } else { '' }
    }
    return $ordered
}

function Get-SafeFileKey {
    param([string]$Value)
    $safe = $Value -replace '\.','_' -replace '[^a-zA-Z0-9_-]+','_'
    $safe = $safe.Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'general' }
    return $safe
}

function Get-DisplayLogPath {
    if (-not $script:LoggingEnabled) { return 'Logging Disabled' }
    switch ($script:LogType) {
        'txt'  { return $script:LogTXTPath  }
        'csv'  { return $script:LogCSVPath  }
        'json' { return $script:LogJSONPath }
        'all'  { return ($script:LogTXTPath, $script:LogCSVPath, $script:LogJSONPath) -join ' | ' }
        default { return 'Logging Disabled' }
    }
}

function Get-DebugDisplayLogPath {
    if (-not $script:DebugEnabled) { return '' }
    return ($script:DebugTXTPath, $script:DebugCSVPath, $script:DebugJSONPath) -join ' | '
}

# ==============================================================================
# LOG FILE MANAGEMENT
# ==============================================================================
function New-LogFiles {
    if (-not $script:LoggingEnabled) { return }
    if (-not (Test-Path -Path $script:LogFolder)) {
        New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
    }
    $utcDay        = Get-UtcDayStamp
    $script:LogDay = $utcDay

    if ($script:LogType -eq 'txt' -or $script:LogType -eq 'all') {
        $script:LogTXTPath = Join-Path $script:LogFolder ('{0}_{1}.txt' -f $script:LogBaseName, $utcDay)
        if (-not (Test-Path $script:LogTXTPath)) {
            Add-Content -Path $script:LogTXTPath -Value ('=' * 70)
            Add-Content -Path $script:LogTXTPath -Value ('Script Name  : {0}' -f $ScriptName)
            Add-Content -Path $script:LogTXTPath -Value ('Session ID   : {0}' -f $script:LogSessionId)
            Add-Content -Path $script:LogTXTPath -Value ('Started UTC  : {0}' -f (Get-Timestamp))
            Add-Content -Path $script:LogTXTPath -Value ('Source Host  : {0}' -f $script:SourceDisplayLabel)
            Add-Content -Path $script:LogTXTPath -Value ('Computer     : {0}' -f $env:COMPUTERNAME)
            Add-Content -Path $script:LogTXTPath -Value ('User         : {0}' -f $env:USERNAME)
            Add-Content -Path $script:LogTXTPath -Value ('UTC Day      : {0}' -f $utcDay)
            Add-Content -Path $script:LogTXTPath -Value ('Curl Options : {0}' -f ($script:CurlArgs -join ' '))
            Add-Content -Path $script:LogTXTPath -Value ('=' * 70)
            Add-Content -Path $script:LogTXTPath -Value ''
        }
    }
    if ($script:LogType -eq 'csv' -or $script:LogType -eq 'all') {
        $script:LogCSVPath = Join-Path $script:LogFolder ('{0}_{1}.csv' -f $script:LogBaseName, $utcDay)
    }
    if ($script:LogType -eq 'json' -or $script:LogType -eq 'all') {
        $script:LogJSONPath = Join-Path $script:LogFolder ('{0}_{1}.json' -f $script:LogBaseName, $utcDay)
    }
}

function Ensure-LogFiles {
    if (-not $script:LoggingEnabled) { return }
    $utcDay   = Get-UtcDayStamp
    $needsNew =
        (-not $script:LogDay) -or ($script:LogDay -ne $utcDay) -or
        (($script:LogType -in 'txt','all')  -and (-not $script:LogTXTPath  -or $script:LogTXTPath  -notmatch "_$utcDay\.txt$"))  -or
        (($script:LogType -in 'csv','all')  -and (-not $script:LogCSVPath  -or $script:LogCSVPath  -notmatch "_$utcDay\.csv$"))  -or
        (($script:LogType -in 'json','all') -and (-not $script:LogJSONPath -or $script:LogJSONPath -notmatch "_$utcDay\.json$"))
    if ($needsNew) {
        $script:LogTXTPath = $script:LogCSVPath = $script:LogJSONPath = $null
        New-LogFiles
    }
}

function New-DebugLogFiles {
    if (-not $script:DebugEnabled) { return }
    if (-not (Test-Path -Path $script:LogFolder)) {
        New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
    }
    $utcDay              = Get-UtcDayStamp
    $script:DebugLogDay  = $utcDay
    $script:DebugTXTPath  = Join-Path $script:LogFolder ('{0}_{1}_debug.txt'  -f $script:LogBaseName, $utcDay)
    $script:DebugCSVPath  = Join-Path $script:LogFolder ('{0}_{1}_debug.csv'  -f $script:LogBaseName, $utcDay)
    $script:DebugJSONPath = Join-Path $script:LogFolder ('{0}_{1}_debug.json' -f $script:LogBaseName, $utcDay)
    if (-not (Test-Path $script:DebugTXTPath)) {
        Add-Content -Path $script:DebugTXTPath -Value ('=' * 70)
        Add-Content -Path $script:DebugTXTPath -Value ('Script Name  : {0}' -f $ScriptName)
        Add-Content -Path $script:DebugTXTPath -Value ('Session ID   : {0}' -f $script:LogSessionId)
        Add-Content -Path $script:DebugTXTPath -Value ('Started UTC  : {0}' -f (Get-Timestamp))
        Add-Content -Path $script:DebugTXTPath -Value ('Source Host  : {0}' -f $script:SourceDisplayLabel)
        Add-Content -Path $script:DebugTXTPath -Value ('Computer     : {0}' -f $env:COMPUTERNAME)
        Add-Content -Path $script:DebugTXTPath -Value ('User         : {0}' -f $env:USERNAME)
        Add-Content -Path $script:DebugTXTPath -Value ('UTC Day      : {0}' -f $utcDay)
        Add-Content -Path $script:DebugTXTPath -Value ('DEBUG LOG')
        Add-Content -Path $script:DebugTXTPath -Value ('=' * 70)
        Add-Content -Path $script:DebugTXTPath -Value ''
    }
}

function Ensure-DebugLogFiles {
    if (-not $script:DebugEnabled) { return }
    $utcDay   = Get-UtcDayStamp
    $needsNew =
        (-not $script:DebugLogDay) -or ($script:DebugLogDay -ne $utcDay) -or
        (-not $script:DebugTXTPath)  -or ($script:DebugTXTPath  -notmatch ("_{0}_debug\.txt$"  -f $utcDay)) -or
        (-not $script:DebugCSVPath)  -or ($script:DebugCSVPath  -notmatch ("_{0}_debug\.csv$"  -f $utcDay)) -or
        (-not $script:DebugJSONPath) -or ($script:DebugJSONPath -notmatch ("_{0}_debug\.json$" -f $utcDay))
    if ($needsNew) {
        $script:DebugTXTPath = $script:DebugCSVPath = $script:DebugJSONPath = $null
        New-DebugLogFiles
    }
}

# ==============================================================================
# LOG FORMAT WRITERS
# ==============================================================================
function Write-LogToTXT {
    param([string]$Path, [hashtable]$Row)
    $ordered = New-OrderedLogRow -Row $Row
    $pairs   = foreach ($f in $script:LogFieldOrder) { '{0}={1}' -f $f, $ordered[$f] }
    Add-Content -Path $Path -Value ($pairs -join ' | ')
}

function Write-LogToCSV {
    param([string]$Path, [hashtable]$Row)
    $obj = [PSCustomObject](New-OrderedLogRow -Row $Row)
    if (-not (Test-Path -Path $Path)) {
        $obj | Export-Csv -Path $Path -NoTypeInformation
        return
    }
    $fi = Get-Item -Path $Path -ErrorAction SilentlyContinue
    if ($fi -and $fi.Length -eq 0) { $obj | Export-Csv -Path $Path -NoTypeInformation }
    else                           { $obj | Export-Csv -Path $Path -NoTypeInformation -Append }
}

function Write-LogToJSON {
    param([string]$Path, [hashtable]$Row)
    Add-Content -Path $Path -Value ((New-OrderedLogRow -Row $Row) | ConvertTo-Json -Compress -Depth 5)
}

function Write-DebugLogEvent {
    param([hashtable]$Row)
    if (-not $script:DebugEnabled -or $script:DebugMode -ne 'D') { return }
    Ensure-DebugLogFiles
    $dr = @{}
    foreach ($k in $Row.Keys) { $dr[$k] = $Row[$k] }
    if (-not $dr.ContainsKey('Timestamp'))    { $dr.Timestamp    = Get-Timestamp }
    if (-not $dr.ContainsKey('LogSessionId')) { $dr.LogSessionId = $script:LogSessionId }
    Write-LogToTXT  -Path $script:DebugTXTPath  -Row $dr
    Write-LogToCSV  -Path $script:DebugCSVPath  -Row $dr
    Write-LogToJSON -Path $script:DebugJSONPath -Row $dr
}

# ==============================================================================
# PRIMARY LOG ENTRY POINT -- file only, never console
# SourceHostName/SourceHostIP are injected from script-level state on every
# call automatically - no caller needs to pass them in -Data.
# ==============================================================================
function Write-LogEvent {
    param(
        [ValidateSet('INFO','SUCCESS','WARN','ERROR','DEBUG')][string]$Level,
        [string]$Status,
        [string]$Message,
        [hashtable]$Data = @{}
    )

    if (-not $script:LoggingEnabled) { return }

    Ensure-LogFiles

    $row = @{
        Timestamp       = Get-Timestamp
        LogSessionId    = $script:LogSessionId
        ScriptName      = $ScriptName
        SourceHostName  = $script:SourceHostName
        SourceHostIP    = $script:SourceHostIP
        Level           = $Level
        Status          = $Status
        Message         = $Message
        ErrorMessage    = if ($Data.ContainsKey('ErrorMessage'))    { Convert-ToFlatString $Data['ErrorMessage']    } else { '' }
        TargetInput     = if ($Data.ContainsKey('TargetInput'))     { Convert-ToFlatString $Data['TargetInput']     } else { '' }
        ResolvedDNSName = if ($Data.ContainsKey('ResolvedDNSName')) { Convert-ToFlatString $Data['ResolvedDNSName'] } else { '' }
        ResolvedIP      = if ($Data.ContainsKey('ResolvedIP'))      { Convert-ToFlatString $Data['ResolvedIP']      } else { '' }
        HttpStatus      = if ($Data.ContainsKey('HttpStatus'))      { Convert-ToFlatString $Data['HttpStatus']      } else { '' }
        CurlExitCode    = if ($Data.ContainsKey('CurlExitCode'))    { Convert-ToFlatString $Data['CurlExitCode']    } else { '' }
        ResponseTimeMs  = if ($Data.ContainsKey('ResponseTimeMs'))  { Convert-ToFlatString $Data['ResponseTimeMs']  } else { '' }
        ResultDetail    = if ($Data.ContainsKey('ResultDetail'))    { Convert-ToFlatString $Data['ResultDetail']    } else { '' }
        Comment         = if ($Data.ContainsKey('Comment'))         { Convert-ToFlatString $Data['Comment']         } else { '' }
    }

    $isDebug         = ($Level -eq 'DEBUG')
    $writeToMainLogs = $true
    if ($isDebug) {
        if (-not $script:DebugEnabled)     { $writeToMainLogs = $false }
        elseif ($script:DebugMode -eq 'D') { $writeToMainLogs = $false }
    }

    if ($writeToMainLogs) {
        if ($script:LogType -in 'txt','all')  { Write-LogToTXT  -Path $script:LogTXTPath  -Row $row }
        if ($script:LogType -in 'csv','all')  { Write-LogToCSV  -Path $script:LogCSVPath  -Row $row }
        if ($script:LogType -in 'json','all') { Write-LogToJSON -Path $script:LogJSONPath -Row $row }
    }
    if ($isDebug -and $script:DebugEnabled -and $script:DebugMode -eq 'D') {
        Write-DebugLogEvent -Row $row
    }
}

# ==============================================================================
# LOGGING INITIALIZATION  (design template - logging and output v2)
# ==============================================================================
function Read-OutputMode {
    while ($true) {
        $raw = (Read-Host " Output Mode: [S]creen | [L]og File | [B]oth").Trim().ToLower()
        switch ($raw) {
            's' { return 'screen' }
            'l' { return 'log'    }
            'b' { return 'both'   }
            default { Write-Host " Invalid entry. Please select a valid option." -ForegroundColor Yellow }
        }
    }
}

function Read-LogType {
    while ($true) {
        $raw = (Read-Host " Log Format: [T]XT | [C]SV | [J]SON | [A]ll").Trim().ToLower()
        switch ($raw) {
            't'    { return 'txt'  }
            'txt'  { return 'txt'  }
            'c'    { return 'csv'  }
            'csv'  { return 'csv'  }
            'j'    { return 'json' }
            'json' { return 'json' }
            'a'    { return 'all'  }
            'all'  { return 'all'  }
            default { Write-Host " Invalid entry. Please select a valid option." -ForegroundColor Yellow }
        }
    }
}

function Read-LogFolderMode {
    param([string]$DefaultFolder)
    while ($true) {
        Write-Host " Default Log Folder: $DefaultFolder" -ForegroundColor DarkGray
        $raw = (Read-Host " Log Folder: [D]efault | [C]ustom").Trim().ToLower()
        switch ($raw) {
            'd' { return $DefaultFolder }
            'c' {
                $custom = (Read-Host " Enter full folder path for log files").Trim()
                if (-not [string]::IsNullOrWhiteSpace($custom)) { return $custom }
                Write-Host " Invalid path. Please try again." -ForegroundColor Yellow
            }
            default { Write-Host " Invalid entry. Please select a valid option." -ForegroundColor Yellow }
        }
    }
}

function Read-DebugMode {
    while ($true) {
        $raw = (Read-Host " Debug Mode: [I]nsert into main logs | [D]edicated debug log files").Trim().ToLower()
        switch ($raw) {
            'i' { return 'I' }
            'd' { return 'D' }
            default { Write-Host " Invalid entry. Please select a valid option." -ForegroundColor Yellow }
        }
    }
}

function Read-YesNo {
    param([string]$Prompt)
    while ($true) {
        $raw = (Read-Host $Prompt).Trim().ToLower()
        switch ($raw) {
            'y'   { return $true  }
            'yes' { return $true  }
            'n'   { return $false }
            'no'  { return $false }
            default { Write-Host " Invalid entry. Please enter [Y]es or [N]o." -ForegroundColor Yellow }
        }
    }
}

function Initialize-Logging {
    param(
        [string]$ContextKey,
        [string]$DefaultLogFolder = $null
    )

    # Resolve a safe default folder at RUNTIME, not at parameter-bind time.
    # $PSScriptRoot is empty when this script is pasted into an interactive
    # console rather than run as a saved .ps1 file.
    if ([string]::IsNullOrWhiteSpace($DefaultLogFolder)) {
        $baseRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
        $DefaultLogFolder = Join-Path -Path $baseRoot -ChildPath 'Logs'
    }

    Write-Host "`n****************************************************" -ForegroundColor White
    Write-Host " Logging and Output Setup"                              -ForegroundColor Cyan
    Write-Host "****************************************************"   -ForegroundColor White

    $script:OutputMode = Read-OutputMode

    switch ($script:OutputMode) {
        'screen' {
            $script:LogToConsole   = $true
            $script:LoggingEnabled = $false
            Write-Host " Screen-only mode. File logging disabled." -ForegroundColor Yellow
            Write-Host "****************************************************" -ForegroundColor White
            return
        }
        'log' {
            $script:LogToConsole   = $false
            $script:LoggingEnabled = $true
        }
        'both' {
            $script:LogToConsole   = $true
            $script:LoggingEnabled = $true
        }
    }

    $script:LogType     = Read-LogType
    $script:LogFolder   = Read-LogFolderMode -DefaultFolder $DefaultLogFolder
    $script:LogBaseName = ('{0}_{1}' -f (Get-SafeFileKey -Value $ScriptName), (Get-SafeFileKey -Value $ContextKey)).ToLower()

    $script:DebugEnabled = Read-YesNo -Prompt " Enable debug logging? [Y]es | [N]o"
    if ($script:DebugEnabled) { $script:DebugMode = Read-DebugMode }
    else                      { $script:DebugMode = $null }

    $script:LogPathDisplayed = $false
    Ensure-LogFiles

    if ($script:DebugEnabled -and $script:DebugMode -eq 'D') { Ensure-DebugLogFiles }

    Write-Host (" Logging Active -> {0}" -f (Get-DisplayLogPath)) -ForegroundColor Cyan
    $script:LogPathDisplayed = $true

    Write-Host "****************************************************" -ForegroundColor White
}

# ==============================================================================
# SUMMARY TRACKING  (design template - summary output and results syntax v4)
# ==============================================================================
$script:SuccessList = @()
$script:FailureList = @()
$script:ErrorList   = @()
$script:DefaultList = @()

$LabelSuccess = "Succeeded"
$LabelSkipped = "Skipped"
$LabelMissed  = "Missed"
$LabelError   = "Failed"

function Show-ScriptSummary {
    param([string]$Title = "TEST SUMMARY")

    Write-Host "`n--- $Title ---"                                    -ForegroundColor Blue
    Write-Host " Script:          $ScriptName"                      -ForegroundColor Cyan
    Write-Host " Session ID:      $($script:LogSessionId)"          -ForegroundColor Cyan
    Write-Host " Source Host:     $($script:SourceDisplayLabel)"    -ForegroundColor Cyan
    Write-Host " Total Tests:     $($script:DefaultList.Count)"     -ForegroundColor White
    Write-Host " Total Succeeded: $($script:SuccessList.Count)"     -ForegroundColor Green
    Write-Host " Total Failed:    $($script:FailureList.Count)"     -ForegroundColor Red
    Write-Host " Total Errors:    $($script:ErrorList.Count)"       -ForegroundColor Red

    # In continuous mode the same URL is tested many times - list each URL
    # once with its count instead of one line per test.
    foreach ($grp in ($script:SuccessList | Group-Object | Sort-Object Name)) {
        Write-Host (" [+] Succeeded: {0} (x{1})" -f $grp.Name, $grp.Count) -ForegroundColor Green
    }
    foreach ($grp in ($script:FailureList | Group-Object | Sort-Object Name)) {
        Write-Host (" [-] Failed:    {0} (x{1})" -f $grp.Name, $grp.Count) -ForegroundColor Red
    }
    foreach ($grp in ($script:ErrorList | Group-Object | Sort-Object Name)) {
        Write-Host (" [E] Error:     {0} (x{1})" -f $grp.Name, $grp.Count) -ForegroundColor Red
    }

    $missedCount = $script:DefaultList.Count - ($script:SuccessList.Count + $script:FailureList.Count + $script:ErrorList.Count)
    if ($missedCount -gt 0) {
        Write-Host " Total Missed:    $missedCount" -ForegroundColor Red
    } else {
        Write-Host " Total Missed:    0" -ForegroundColor Gray
    }

    $statusColor = if ($missedCount -gt 0 -or $script:ErrorList.Count -gt 0) { "Red" } else { "Blue" }
    Write-Host "--------------------------" -ForegroundColor $statusColor
    Write-Host "Done.`n"                    -ForegroundColor $statusColor
}

# ==============================================================================
# DNS HELPER - reverse lookup with NoPTR fallback (used for destination host
# AND reused as-is for the source host resolution)
# ==============================================================================
function Resolve-TargetDNS {
    param([string]$Target)

    $result = [PSCustomObject]@{
        ResolvedIP      = ''
        ResolvedDNSName = ''
        DisplayLabel    = ''
    }

    $isIP = $Target -match '^\d{1,3}(\.\d{1,3}){3}$'

    if ($isIP) {
        $result.ResolvedIP = $Target
        try {
            $ptr = [System.Net.Dns]::GetHostEntry($Target)
            $result.ResolvedDNSName = $ptr.HostName
            $result.DisplayLabel    = '{0}_{1}' -f $ptr.HostName, $Target
        } catch {
            $result.ResolvedDNSName = 'NoPTR'
            $result.DisplayLabel    = 'NoPTR_{0}' -f $Target
        }
    } else {
        $result.ResolvedDNSName = $Target
        try {
            $fwd = [System.Net.Dns]::GetHostAddresses($Target) |
                   Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                   Select-Object -First 1
            if ($fwd) {
                $result.ResolvedIP   = $fwd.IPAddressToString
                $result.DisplayLabel = '{0}_{1}' -f $Target, $fwd.IPAddressToString
            } else {
                $result.ResolvedIP   = 'UnresolvedIP'
                $result.DisplayLabel = '{0}_UnresolvedIP' -f $Target
            }
        } catch {
            $result.ResolvedIP   = 'UnresolvedIP'
            $result.DisplayLabel = '{0}_UnresolvedIP' -f $Target
        }
    }

    return $result
}

# ==============================================================================
# URL HELPERS
# ==============================================================================
# Adds https:// when no scheme was typed so [Uri] and curl agree on the host.
function Normalize-Url {
    param([string]$Url)
    $u = $Url.Trim()
    if ($u -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $u = 'https://' + $u }
    return $u
}

function Get-UrlHost {
    param([string]$Url)
    try   { return ([Uri]$Url).Host }
    catch { return '' }
}

# ==============================================================================
# CORE CURL TEST - single URL, returns result object, no console output
# ==============================================================================
function Test-SingleUrl {
    param(
        [string]$Url,
        [string]$ResolvedDNSName,
        [string]$ResolvedIP,
        [string]$Comment = ''
    )

    $curlArgs  = $script:CurlArgs
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $output    = @(& curl.exe @curlArgs $Url 2>&1)
    $exitCode  = $LASTEXITCODE
    $stopwatch.Stop()
    $elapsedMs = [int]$stopwatch.ElapsedMilliseconds

    # Output is an array of lines. Take the LAST HTTP status line so a proxy
    # "HTTP/1.1 200 Connection established" line doesn't mask the real one.
    $status = 0
    foreach ($line in $output) {
        if ("$line" -match '^HTTP/\S+\s+(\d{3})') { $status = [int]$Matches[1] }
    }

    $errMsg = ''
    if ($exitCode -ne 0) {
        $errLines = $output | Where-Object { "$_" -match '^curl:' } | ForEach-Object { "$_".Trim() }
        $errMsg   = if ($errLines) { ($errLines -join ' ') } else { "curl exit code $exitCode" }
    } elseif ($status -eq 0) {
        $errMsg = 'No HTTP status line returned'
    }

    $succeeded = ($status -ge 200 -and $status -lt 400)
    if (-not $succeeded -and [string]::IsNullOrWhiteSpace($errMsg)) { $errMsg = "HTTP status $status" }

    $logData = @{
        TargetInput     = $Url
        ResolvedDNSName = $ResolvedDNSName
        ResolvedIP      = $ResolvedIP
        HttpStatus      = $status
        CurlExitCode    = $exitCode
        ResponseTimeMs  = $elapsedMs
        ResultDetail    = if ($succeeded) { "HTTP $status" } else { $errMsg }
        Comment         = $Comment
    }
    if (-not $succeeded) { $logData['ErrorMessage'] = $errMsg }

    if ($succeeded) {
        Write-LogEvent -Level SUCCESS -Status 'URL_SUCCESS' `
            -Message ("curl {0} ({1}) succeeded. HTTP {2} in {3} ms" -f $Url, $ResolvedIP, $status, $elapsedMs) `
            -Data $logData
    } else {
        Write-LogEvent -Level ERROR -Status 'URL_FAILED' `
            -Message ("curl {0} ({1}) failed. HTTP {2}: {3}" -f $Url, $ResolvedIP, $status, $errMsg) `
            -Data $logData
    }

    Write-LogEvent -Level DEBUG -Status 'CURL_RAW_OUTPUT' `
        -Message ("Raw curl output for {0}" -f $Url) `
        -Data @{
            TargetInput  = $Url
            CurlExitCode = $exitCode
            ResultDetail = (($output | ForEach-Object { "$_" }) -join ' || ')
            Comment      = $Comment
        }

    return [PSCustomObject]@{
        Url        = $Url
        Succeeded  = $succeeded
        HttpStatus = $status
        ExitCode   = $exitCode
        ElapsedMs  = $elapsedMs
        Error      = $errMsg
    }
}

# ==============================================================================
# OUTPUT LINE - one line per URL test (screen only)
# Format: MM.dd.yyyy | hh:mm:ss tt | [comment |] SCR:Name_IP | Dest:Name_IP | URL | Status: 200 | 123 ms | SUCCESS
# ==============================================================================
function Write-UrlResultLine {
    param(
        [string]$SourceDisplayLabel,
        [string]$DestDisplayLabel,
        [string]$Url,
        [object]$Result,
        [string]$Comment = ''
    )

    if (-not $script:LogToConsole) { return }

    $datePart = Get-Date -Format "MM.dd.yyyy"
    $timePart = Get-Date -Format "hh:mm:ss tt"

    Write-Host ($datePart + " | " + $timePart + " | ") -NoNewline -ForegroundColor White

    if (-not [string]::IsNullOrWhiteSpace($Comment)) {
        Write-Host $Comment -NoNewline -ForegroundColor Cyan
        Write-Host " | " -NoNewline -ForegroundColor White
    }

    Write-Host ("SCR:" + $SourceDisplayLabel + " | ") -NoNewline -ForegroundColor White
    Write-Host ("Dest:" + $DestDisplayLabel + " | ")  -NoNewline -ForegroundColor White
    Write-Host $Url -NoNewline -ForegroundColor Cyan
    Write-Host " | Status: " -NoNewline -ForegroundColor White

    $color = if ($Result.Succeeded) { 'Green' } else { 'Red' }
    Write-Host $Result.HttpStatus -NoNewline -ForegroundColor $color
    Write-Host (" | {0} ms | " -f $Result.ElapsedMs) -NoNewline -ForegroundColor White

    if ($Result.Succeeded) {
        Write-Host "SUCCESS" -ForegroundColor Green
    } else {
        Write-Host "FAILED" -NoNewline -ForegroundColor Red
        Write-Host (" ({0})" -f $Result.Error) -ForegroundColor DarkGray
    }
}

# ==============================================================================
# TEST RUNNER - resolves host, curls the URL, writes result line
# ==============================================================================
function Invoke-UrlTest {
    param(
        [string]$Url,
        [string]$Comment = ''
    )

    $hostName = Get-UrlHost -Url $Url
    $script:DefaultList += $Url

    if ([string]::IsNullOrWhiteSpace($hostName)) {
        $script:ErrorList += $Url
        Write-Host (" [E] Invalid URL, skipped: {0}" -f $Url) -ForegroundColor Red
        Write-LogEvent -Level ERROR -Status 'URL_INVALID' `
            -Message ("Invalid URL '{0}' - could not parse host" -f $Url) `
            -Data @{ TargetInput = $Url; ErrorMessage = 'Could not parse host from URL'; Comment = $Comment }
        return
    }

    # DNS label is cached per host so continuous mode doesn't re-resolve every pass
    if (-not $script:DnsCache.ContainsKey($hostName)) {
        $script:DnsCache[$hostName] = Resolve-TargetDNS -Target $hostName
        $dnsInfo = $script:DnsCache[$hostName]
        Write-LogEvent -Level INFO -Status 'DNS_RESOLVED' `
            -Message ("DNS resolution for '{0}': DNS={1} IP={2}" -f $hostName, $dnsInfo.ResolvedDNSName, $dnsInfo.ResolvedIP) `
            -Data @{
                TargetInput     = $Url
                ResolvedDNSName = $dnsInfo.ResolvedDNSName
                ResolvedIP      = $dnsInfo.ResolvedIP
                ResultDetail    = 'DNS resolution only'
                Comment         = $Comment
            }
    }
    $dnsInfo = $script:DnsCache[$hostName]

    $result = Test-SingleUrl `
        -Url             $Url `
        -ResolvedDNSName $dnsInfo.ResolvedDNSName `
        -ResolvedIP      $dnsInfo.ResolvedIP `
        -Comment         $Comment

    if ($result.Succeeded) { $script:SuccessList += $Url }
    else                   { $script:FailureList += $Url }

    Write-UrlResultLine `
        -SourceDisplayLabel $script:SourceDisplayLabel `
        -DestDisplayLabel   $dnsInfo.DisplayLabel `
        -Url                $Url `
        -Result             $result `
        -Comment            $Comment
}

function Read-Interval {
    $IntervalRaw = Read-Host ' Enter interval in seconds ("0" = run once)'
    $Interval    = 0
    while (-not [int]::TryParse($IntervalRaw, [ref]$Interval) -or $Interval -lt 0) {
        Write-Host " Invalid interval. Please enter a whole number (0 or greater)." -ForegroundColor Yellow
        $IntervalRaw = Read-Host ' Enter interval in seconds ("0" = run once)'
    }
    return $Interval
}

# ==============================================================================
# MAIN
# ==============================================================================
$script:DnsCache = @{}

Write-Host "`n****************************************************" -ForegroundColor White

# --- Source host identification - resolved once per session, reused for
#     every screen line and every log entry. ---
Write-Host " Resolving source host (this machine)..." -ForegroundColor Gray
$script:SourceInfo         = Resolve-TargetDNS -Target ([System.Net.Dns]::GetHostName())
$script:SourceHostName     = $script:SourceInfo.ResolvedDNSName
$script:SourceHostIP       = $script:SourceInfo.ResolvedIP
$script:SourceDisplayLabel = $script:SourceInfo.DisplayLabel
Write-Host (" Source Host -> {0}" -f $script:SourceDisplayLabel) -ForegroundColor Gray
Write-Host "****************************************************" -ForegroundColor White

$TestType = ""
while ($TestType -notin @('1','2')) {
    $TestType = (Read-Host " Test Mode: [1] Single URL | [2] Input file").Trim()
    if ($TestType -notin @('1','2')) {
        Write-Host " Invalid entry. Please select a valid option." -ForegroundColor Yellow
    }
}

# Each entry: @{ Url = ...; Comment = ... }
$UrlEntries = @()

if ($TestType -eq '1') {

    $UrlRaw = ""
    while ([string]::IsNullOrWhiteSpace($UrlRaw)) {
        $UrlRaw = (Read-Host " Enter the URL (e.g. https://server.domain.com/path)").Trim()
        if ([string]::IsNullOrWhiteSpace($UrlRaw)) {
            Write-Host " No URL entered. Please try again." -ForegroundColor Yellow
        }
    }
    $Url      = Normalize-Url -Url $UrlRaw
    $Interval = Read-Interval
    $Comment  = Read-Host " Enter comment (optional - press Enter to skip)"

    $UrlEntries += @{ Url = $Url; Comment = $Comment }
    $ContextKey  = Get-SafeFileKey -Value (Get-UrlHost -Url $Url)
    $SourceLabel = $Url
    $ModeLabel   = 'SingleUrl'

} elseif ($TestType -eq '2') {

    Write-Host "`n****************************************************" -ForegroundColor White
    Write-Host " Input File Setup"                                       -ForegroundColor Yellow
    Write-Host "****************************************************"   -ForegroundColor White

    $InputFilePath = ""
    while ([string]::IsNullOrWhiteSpace($InputFilePath) -or -not (Test-Path -Path $InputFilePath -PathType Leaf)) {
        $InputFilePath = (Read-Host " Enter the path to the input CSV file").Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($InputFilePath) -or -not (Test-Path -Path $InputFilePath -PathType Leaf)) {
            Write-Host " File not found: $InputFilePath" -ForegroundColor Red
        }
    }

    foreach ($Line in (Get-Content -Path $InputFilePath)) {
        if ([string]::IsNullOrWhiteSpace($Line))          { continue }
        if ($Line.Trim().StartsWith('#'))                  { continue }

        # Split on the first comma only - URLs with query strings may contain more
        $cols = $Line -split ',', 2
        $first = $cols[0].Trim()
        if ($first -match '^(url|target)$')               { continue }
        if ([string]::IsNullOrWhiteSpace($first))          { continue }

        $comment = if ($cols.Count -ge 2) { $cols[1].Trim() } else { '' }
        $UrlEntries += @{ Url = (Normalize-Url -Url $first); Comment = $comment }
    }

    if ($UrlEntries.Count -eq 0) {
        Write-Host " No URLs found in $InputFilePath. Exiting." -ForegroundColor Red
        exit
    }
    Write-Host (" Loaded {0} URL(s) from file." -f $UrlEntries.Count) -ForegroundColor Gray

    $Interval    = Read-Interval
    $ContextKey  = 'multipleurls'
    $SourceLabel = $InputFilePath
    $ModeLabel   = 'FileInput'
}

Initialize-Logging -ContextKey $ContextKey

Write-LogEvent -Level INFO -Status 'SESSION_START' `
    -Message ("Session started. Mode={0} Source={1} URLs={2} Interval={3}s CurlArgs={4}" -f $ModeLabel, $SourceLabel, $UrlEntries.Count, $Interval, ($script:CurlArgs -join ' ')) `
    -Data @{
        TargetInput  = $SourceLabel
        ResultDetail = "Interval=$Interval"
        Comment      = ''
    }

if ($Interval -gt 0) {
    Write-Host ("`n Continuous mode: every {0}s. Press Ctrl+C to stop." -f $Interval) -ForegroundColor Yellow
}
if (-not $script:LogToConsole) {
    Write-Host " Log-only mode: results are written to the log file(s), not the screen." -ForegroundColor Yellow
}

$Pass = 0
try {
    while ($true) {
        $Pass++
        foreach ($entry in $UrlEntries) {
            Invoke-UrlTest -Url $entry.Url -Comment $entry.Comment
        }

        if ($UrlEntries.Count -gt 1) {
            Write-Host "`n[Batch $Pass Complete] $(Get-Date -Format 'MM.dd.yyyy | hh:mm:ss tt')" -ForegroundColor Blue
            Write-LogEvent -Level INFO -Status 'BATCH_COMPLETE' `
                -Message ("Batch {0} complete at {1}" -f $Pass, (Get-Timestamp)) `
                -Data @{
                    TargetInput  = $SourceLabel
                    ResultDetail = 'All URLs processed'
                    Comment      = ''
                }
        }

        if ($Interval -le 0) { break }
        Start-Sleep -Seconds $Interval
    }
}
finally {
    # Runs on normal completion AND on Ctrl+C in continuous mode
    # ==============================================================================
    # SESSION END + SUMMARY
    # ==============================================================================
    Write-LogEvent -Level INFO -Status 'SESSION_END' `
        -Message ("Session ended after {0} pass(es). Succeeded={1} Failed={2} Errors={3}" -f $Pass, $script:SuccessList.Count, $script:FailureList.Count, $script:ErrorList.Count) `
        -Data @{
            ResultDetail = ('Passes={0} Succeeded={1} Failed={2} Errors={3}' -f $Pass, $script:SuccessList.Count, $script:FailureList.Count, $script:ErrorList.Count)
            Comment      = ''
        }

    Show-ScriptSummary -Title "URL CONNECTIVITY TEST SUMMARY"
}
