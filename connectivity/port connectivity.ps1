# ==============================================================================
# SCRIPT:  Test-PortConnectivity.ps1
# CONTEXT: TCP_PORT_CONNECTIVITY_TESTER
# VERSION: V3
# UPDATED: 2026-06-26 00:00:00
# ==============================================================================

$VariableContext = "TCP_PORT_CONNECTIVITY_TESTER"
$Version         = "V3"
$LastUpdated     = "2026-06-26 00:00:00"
$ScriptName      = $MyInvocation.MyCommand.Name

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
Write-Host " Tests TCP connectivity from this host to one or more"
Write-Host " targets across one or more ports. Performs a reverse"
Write-Host " DNS (PTR) lookup per target. Outputs a single grouped"
Write-Host " summary line per target showing Good and Failed ports."
Write-Host " Supports single-target and CSV file input modes."
Write-Host " Logs every individual port test as a separate entry."
Write-Host ""
Write-Host " Input/Steps Required:"                                 -ForegroundColor Yellow
Write-Host " 1. Choose single IP/DNS target or CSV input file."
Write-Host " 2. Enter one or more ports (comma or space separated)."
Write-Host " 3. Set a test interval (0 = run once)."
Write-Host " 4. Enter an optional comment."
Write-Host " 5. Configure output mode (Screen / Log File / Both)."
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

# Comment field added to field order
$script:LogFieldOrder = @(
    'Timestamp',
    'LogSessionId',
    'ScriptName',
    'Level',
    'Status',
    'Message',
    'ErrorMessage',
    'TargetInput',
    'ResolvedDNSName',
    'ResolvedIP',
    'TestedPort',
    'SourceIP',
    'TCPResultDetail',
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
            Add-Content -Path $script:LogTXTPath -Value ('Computer     : {0}' -f $env:COMPUTERNAME)
            Add-Content -Path $script:LogTXTPath -Value ('User         : {0}' -f $env:USERNAME)
            Add-Content -Path $script:LogTXTPath -Value ('UTC Day      : {0}' -f $utcDay)
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
    # Path display is handled once in Initialize-Logging — not here
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
# Write-LogEvent writes to log files only. All screen output is handled
# exclusively by Write-TargetSummaryLine and explicit Write-Host calls.
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
        Level           = $Level
        Status          = $Status
        Message         = $Message
        ErrorMessage    = if ($Data.ContainsKey('ErrorMessage'))    { Convert-ToFlatString $Data['ErrorMessage']    } else { '' }
        TargetInput     = if ($Data.ContainsKey('TargetInput'))     { Convert-ToFlatString $Data['TargetInput']     } else { '' }
        ResolvedDNSName = if ($Data.ContainsKey('ResolvedDNSName')) { Convert-ToFlatString $Data['ResolvedDNSName'] } else { '' }
        ResolvedIP      = if ($Data.ContainsKey('ResolvedIP'))      { Convert-ToFlatString $Data['ResolvedIP']      } else { '' }
        TestedPort      = if ($Data.ContainsKey('TestedPort'))      { Convert-ToFlatString $Data['TestedPort']      } else { '' }
        SourceIP        = if ($Data.ContainsKey('SourceIP'))        { Convert-ToFlatString $Data['SourceIP']        } else { '' }
        TCPResultDetail = if ($Data.ContainsKey('TCPResultDetail')) { Convert-ToFlatString $Data['TCPResultDetail'] } else { '' }
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
# Output mode drives everything:
#   [S]creen  -> console only,  no file logging
#   [L]og     -> file only,     no console output
#   [B]oth    -> console + file logging
# No secondary "enable file logging" prompt needed — L and B imply it.
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
    param([string]$ContextKey, [string]$DefaultLogFolder = (Join-Path -Path $PSScriptRoot -ChildPath 'Logs'))

    Write-Host "`n****************************************************" -ForegroundColor White
    Write-Host " Logging and Output Setup"                              -ForegroundColor Cyan
    Write-Host "****************************************************"   -ForegroundColor White

    $script:OutputMode = Read-OutputMode

    switch ($script:OutputMode) {
        'screen' {
            # Screen only — no file logging, no further prompts needed
            $script:LogToConsole   = $true
            $script:LoggingEnabled = $false
            Write-Host " Screen-only mode. File logging disabled." -ForegroundColor Yellow
            Write-Host "****************************************************" -ForegroundColor White
            return
        }
        'log' {
            # Log file only — suppress all console output during testing
            $script:LogToConsole   = $false
            $script:LoggingEnabled = $true
        }
        'both' {
            # Console + log file
            $script:LogToConsole   = $true
            $script:LoggingEnabled = $true
        }
    }

    # L and B both reach here — file logging is implied, no extra prompt
    $script:LogType     = Read-LogType
    $script:LogFolder   = Read-LogFolderMode -DefaultFolder $DefaultLogFolder
    $script:LogBaseName = ('{0}_{1}' -f (Get-SafeFileKey -Value $ScriptName), (Get-SafeFileKey -Value $ContextKey)).ToLower()

    $script:DebugEnabled = Read-YesNo -Prompt " Enable debug logging? [Y]es | [N]o"
    if ($script:DebugEnabled) { $script:DebugMode = Read-DebugMode }
    else                      { $script:DebugMode = $null }

    $script:LogPathDisplayed = $false
    Ensure-LogFiles

    if ($script:DebugEnabled -and $script:DebugMode -eq 'D') { Ensure-DebugLogFiles }

    # Show log path on screen once — this is the only log-related console output
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
    Write-Host " Total Tests:     $($script:DefaultList.Count)"     -ForegroundColor White
    Write-Host " Total Succeeded: $($script:SuccessList.Count)"     -ForegroundColor Green
    Write-Host " Total Failed:    $($script:FailureList.Count)"     -ForegroundColor Red
    Write-Host " Total Errors:    $($script:ErrorList.Count)"       -ForegroundColor Red

    if ($script:SuccessList.Count -gt 0) {
        foreach ($item in $script:SuccessList) { Write-Host " [+] Succeeded: $item" -ForegroundColor Green }
    }
    if ($script:FailureList.Count -gt 0) {
        foreach ($item in $script:FailureList) { Write-Host " [-] Failed:    $item" -ForegroundColor Red   }
    }
    if ($script:ErrorList.Count -gt 0) {
        foreach ($item in $script:ErrorList)   { Write-Host " [E] Error:     $item" -ForegroundColor Red   }
    }

    $allProcessed = $script:SuccessList + $script:FailureList + $script:ErrorList
    $missedItems  = $script:DefaultList | Where-Object { $_ -notin $allProcessed }
    if ($missedItems.Count -gt 0) {
        Write-Host " Total Missed:    $($missedItems.Count)" -ForegroundColor Red
        foreach ($m in $missedItems) { Write-Host " [X] Missed: $m" -ForegroundColor Red }
    } else {
        Write-Host " Total Missed:    0" -ForegroundColor Gray
    }

    $statusColor = if ($missedItems.Count -gt 0 -or $script:ErrorList.Count -gt 0) { "Red" } else { "Blue" }
    Write-Host "--------------------------" -ForegroundColor $statusColor
    Write-Host "Done.`n"                    -ForegroundColor $statusColor
}

# ==============================================================================
# DNS HELPER — reverse lookup with NoPTR fallback
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
# PORT PARSER — accepts comma, space, or mixed separators
# ==============================================================================
function Parse-Ports {
    param([string]$PortInput)
    $raw    = $PortInput -replace ',',' '
    $tokens = $raw -split '\s+' | Where-Object { $_ -ne '' }
    $ports  = @()
    foreach ($t in $tokens) {
        $n = 0
        if ([int]::TryParse($t.Trim(), [ref]$n) -and $n -gt 0 -and $n -le 65535) {
            $ports += $n
        } else {
            Write-Host " WARNING: '$t' is not a valid port number and will be skipped." -ForegroundColor Yellow
        }
    }
    return $ports
}

# ==============================================================================
# CORE TCP TEST — single port, returns result object, no console output
# ==============================================================================
function Test-SinglePort {
    param(
        [string]$Target,
        [int]$Port,
        [string]$ResolvedDNSName,
        [string]$ResolvedIP,
        [string]$Comment = ''
    )

    $sourceIP  = ''
    $succeeded = $false
    $errMsg    = ''

    try {
        $tcpClient   = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($Target, $Port, $null, $null)
        $waitHandle  = $asyncResult.AsyncWaitHandle
        $timeout     = $waitHandle.WaitOne(5000)

        if (-not $timeout) { throw "Connection timed out after 5 seconds" }

        $sourceIP = $tcpClient.Client.LocalEndPoint.Address.IPAddressToString
        $tcpClient.EndConnect($asyncResult)
        $tcpClient.Close()
        $succeeded = $true

    } catch {
        $errMsg = $_.Exception.Message
    }

    $logData = @{
        TargetInput     = $Target
        ResolvedDNSName = $ResolvedDNSName
        ResolvedIP      = $ResolvedIP
        TestedPort      = $Port
        SourceIP        = $sourceIP
        TCPResultDetail = if ($succeeded) { "TCP connect succeeded on port $Port" } else { $errMsg }
        Comment         = $Comment
    }
    if (-not $succeeded) { $logData['ErrorMessage'] = $errMsg }

    if ($succeeded) {
        Write-LogEvent -Level SUCCESS -Status 'PORT_SUCCESS' `
            -Message ("TCP port {0} to {1} ({2}) succeeded. Source IP: {3}" -f $Port, $ResolvedDNSName, $ResolvedIP, $sourceIP) `
            -Data $logData
    } else {
        Write-LogEvent -Level ERROR -Status 'PORT_FAILED' `
            -Message ("TCP port {0} to {1} ({2}) failed: {3}" -f $Port, $ResolvedDNSName, $ResolvedIP, $errMsg) `
            -Data $logData
    }

    return [PSCustomObject]@{
        Port      = $Port
        Succeeded = $succeeded
        SourceIP  = $sourceIP
        Error     = $errMsg
    }
}

# ==============================================================================
# OUTPUT LINE — grouped summary line per target (screen only)
# Format with comment:    MM.dd.yyyy | hh:mm:ss tt | "comment" | DNSName_IP | Good: 443 80 | Failed: 22
# Format without comment: MM.dd.yyyy | hh:mm:ss tt | DNSName_IP | Good: 443 80 | Failed: 22
# ==============================================================================
function Write-TargetSummaryLine {
    param(
        [string]$DisplayLabel,
        [int[]]$GoodPorts,
        [int[]]$FailedPorts,
        [string]$Comment = ''
    )

    $datePart = Get-Date -Format "MM.dd.yyyy"
    $timePart = Get-Date -Format "hh:mm:ss tt"

    # Date and time
    Write-Host ($datePart + " | " + $timePart + " | ") -NoNewline -ForegroundColor White

    # Comment segment — only printed when a comment was provided
    if (-not [string]::IsNullOrWhiteSpace($Comment)) {
        Write-Host ('"' + $Comment + '"') -NoNewline -ForegroundColor Cyan
        Write-Host " | " -NoNewline -ForegroundColor White
    }

    # Target label
    Write-Host ($DisplayLabel + " | ") -NoNewline -ForegroundColor White

    # Good ports
    Write-Host "Good: " -NoNewline -ForegroundColor White
    if ($GoodPorts.Count -gt 0) {
        $last = $GoodPorts[-1]
        foreach ($p in $GoodPorts) {
            if ($p -eq $last) { Write-Host "$p"  -NoNewline -ForegroundColor Green }
            else              { Write-Host "$p " -NoNewline -ForegroundColor Green }
        }
    } else {
        Write-Host "--" -NoNewline -ForegroundColor DarkGray
    }

    Write-Host " | " -NoNewline -ForegroundColor White

    # Failed ports
    Write-Host "Failed: " -NoNewline -ForegroundColor White
    if ($FailedPorts.Count -gt 0) {
        $last = $FailedPorts[-1]
        foreach ($p in $FailedPorts) {
            if ($p -eq $last) { Write-Host "$p"  -NoNewline -ForegroundColor Red }
            else              { Write-Host "$p " -NoNewline -ForegroundColor Red }
        }
    } else {
        Write-Host "--" -NoNewline -ForegroundColor DarkGray
    }

    Write-Host ""
}

# ==============================================================================
# TEST RUNNER — tests all ports for one target, writes summary line
# ==============================================================================
function Invoke-TargetTest {
    param(
        [string]$Target,
        [int[]]$Ports,
        [string]$Comment = ''
    )

    $dnsInfo = Resolve-TargetDNS -Target $Target

    Write-LogEvent -Level INFO -Status 'DNS_RESOLVED' `
        -Message ("DNS resolution for '{0}': DNS={1} IP={2}" -f $Target, $dnsInfo.ResolvedDNSName, $dnsInfo.ResolvedIP) `
        -Data @{
            TargetInput     = $Target
            ResolvedDNSName = $dnsInfo.ResolvedDNSName
            ResolvedIP      = $dnsInfo.ResolvedIP
            TestedPort      = 'N/A'
            TCPResultDetail = 'DNS resolution only'
            Comment         = $Comment
        }

    $goodPorts     = @()
    $failedPorts   = @()
    $resolveTarget = if ($dnsInfo.ResolvedIP -notin @('', 'UnresolvedIP')) { $dnsInfo.ResolvedIP } else { $Target }

    foreach ($port in $Ports) {
        $testKey = '{0}:{1}' -f $dnsInfo.DisplayLabel, $port
        $script:DefaultList += $testKey

        $result = Test-SinglePort `
            -Target          $resolveTarget `
            -Port            $port `
            -ResolvedDNSName $dnsInfo.ResolvedDNSName `
            -ResolvedIP      $dnsInfo.ResolvedIP `
            -Comment         $Comment

        if ($result.Succeeded) {
            $goodPorts              += $port
            $script:SuccessList     += $testKey
        } else {
            $failedPorts            += $port
            $script:FailureList     += $testKey
        }
    }

    # Screen output — one line only
    Write-TargetSummaryLine `
        -DisplayLabel $dnsInfo.DisplayLabel `
        -GoodPorts    $goodPorts `
        -FailedPorts  $failedPorts `
        -Comment      $Comment

    # Log the grouped summary as a single INFO record
    $goodStr   = if ($goodPorts.Count   -gt 0) { $goodPorts   -join ' ' } else { '--' }
    $failedStr = if ($failedPorts.Count -gt 0) { $failedPorts -join ' ' } else { '--' }

    Write-LogEvent -Level INFO -Status 'TARGET_SUMMARY' `
        -Message ("Target summary: {0} | Good: {1} | Failed: {2}" -f $dnsInfo.DisplayLabel, $goodStr, $failedStr) `
        -Data @{
            TargetInput     = $Target
            ResolvedDNSName = $dnsInfo.ResolvedDNSName
            ResolvedIP      = $dnsInfo.ResolvedIP
            TestedPort      = ($Ports -join ',')
            TCPResultDetail = ('Good={0} Failed={1}' -f $goodStr, $failedStr)
            Comment         = $Comment
        }
}

# ==============================================================================
# MAIN
# ==============================================================================
Write-Host "`n****************************************************" -ForegroundColor White

$TestType = ""
while ($TestType -notin @('1','2')) {
    $TestType = (Read-Host " Test Mode: [1] Single target | [2] Input file").Trim()
    if ($TestType -notin @('1','2')) {
        Write-Host " Invalid entry. Please select a valid option." -ForegroundColor Yellow
    }
}

if ($TestType -eq '1') {

    $Target  = Read-Host " Enter the URL / IP"
    $PortRaw = Read-Host " Enter port(s) — comma or space separated (e.g. 443 80 22)"
    $Ports   = Parse-Ports -PortInput $PortRaw

    while ($Ports.Count -eq 0) {
        Write-Host " No valid ports found. Please try again." -ForegroundColor Yellow
        $PortRaw = Read-Host " Enter port(s) — comma or space separated"
        $Ports   = Parse-Ports -PortInput $PortRaw
    }

    $IntervalRaw = Read-Host ' Enter interval in seconds ("0" = run once)'
    $Interval    = 0
    while (-not [int]::TryParse($IntervalRaw, [ref]$Interval)) {
        Write-Host " Invalid interval. Please enter a whole number." -ForegroundColor Yellow
        $IntervalRaw = Read-Host ' Enter interval in seconds ("0" = run once)'
    }

    $Comment = Read-Host " Enter comment (optional — press Enter to skip)"

    Initialize-Logging -ContextKey (Get-SafeFileKey -Value $Target)

    Write-LogEvent -Level INFO -Status 'SESSION_START' `
        -Message ("Session started. Mode=SingleTarget Target={0} Ports={1} Interval={2}s" -f $Target, ($Ports -join ','), $Interval) `
        -Data @{
            TargetInput     = $Target
            TestedPort      = ($Ports -join ',')
            TCPResultDetail = "Interval=$Interval"
            Comment         = $Comment
        }

    while ($true) {
        Invoke-TargetTest -Target $Target -Ports $Ports -Comment $Comment
        if ($Interval -le 0) { break }
        Start-Sleep -Seconds $Interval
    }

} elseif ($TestType -eq '2') {

    Write-Host "`n****************************************************" -ForegroundColor White
    Write-Host " Input File Setup"                                       -ForegroundColor Yellow
    Write-Host "****************************************************"   -ForegroundColor White

    $InputFilePath = ""
    while (-not (Test-Path -Path $InputFilePath)) {
        $InputFilePath = (Read-Host " Enter the path to the input CSV file").Trim()
        if (-not (Test-Path -Path $InputFilePath)) {
            Write-Host " File not found: $InputFilePath" -ForegroundColor Red
        }
    }

    $PortRaw = Read-Host " Enter port(s) to test against ALL targets — comma or space separated (e.g. 443 80 22)"
    $Ports   = Parse-Ports -PortInput $PortRaw

    while ($Ports.Count -eq 0) {
        Write-Host " No valid ports found. Please try again." -ForegroundColor Yellow
        $PortRaw = Read-Host " Enter port(s) — comma or space separated"
        $Ports   = Parse-Ports -PortInput $PortRaw
    }

    $IntervalRaw = Read-Host ' Enter interval in seconds ("0" = run once)'
    $Interval    = 0
    while (-not [int]::TryParse($IntervalRaw, [ref]$Interval)) {
        Write-Host " Invalid interval. Please enter a whole number." -ForegroundColor Yellow
        $IntervalRaw = Read-Host ' Enter interval in seconds ("0" = run once)'
    }

    Initialize-Logging -ContextKey 'multiplehosts'

    Write-LogEvent -Level INFO -Status 'SESSION_START' `
        -Message ("Session started. Mode=FileInput File={0} Ports={1} Interval={2}s" -f $InputFilePath, ($Ports -join ','), $Interval) `
        -Data @{
            TargetInput     = $InputFilePath
            TestedPort      = ($Ports -join ',')
            TCPResultDetail = "Interval=$Interval"
            Comment         = ''
        }

    $Lines = Get-Content -Path $InputFilePath

    while ($true) {
        foreach ($Line in $Lines) {
            if ([string]::IsNullOrWhiteSpace($Line))         { continue }
            if ($Line.Trim().StartsWith('#'))                 { continue }

            $cols = $Line -split ','
            if ($cols.Count -lt 1)                           { continue }
            if ($cols[0].Trim() -match '^(ip|dns|target)$') { continue }

            $Target = $cols[0].Trim()
            if ([string]::IsNullOrWhiteSpace($Target))       { continue }

            # Per-row port override: if column 2 is numeric port(s) use them; else use global ports
            $rowPorts = $Ports
            if ($cols.Count -ge 2) {
                $colTwo = $cols[1].Trim()
                $parsed = Parse-Ports -PortInput $colTwo
                if ($parsed.Count -gt 0) { $rowPorts = $parsed }
            }

            # Comment from last column (legacy S/SE skipped)
            $comment = ''
            if ($cols.Count -ge 4) {
                $comment = $cols[3].Trim()
            } elseif ($cols.Count -ge 3) {
                $third = $cols[2].Trim()
                if ($third -notin @('S','SE')) { $comment = $third }
            }

            Invoke-TargetTest -Target $Target -Ports $rowPorts -Comment $comment
        }

        Write-Host "`n[Batch Complete] $(Get-Date -Format 'MM.dd.yyyy | hh:mm:ss tt')" -ForegroundColor Blue

        Write-LogEvent -Level INFO -Status 'BATCH_COMPLETE' `
            -Message ("Batch complete at {0}" -f (Get-Timestamp)) `
            -Data @{
                TargetInput     = $InputFilePath
                TCPResultDetail = 'All targets in file processed'
                Comment         = ''
            }

        if ($Interval -le 0) { break }
        Start-Sleep -Seconds $Interval
    }
}

# ==============================================================================
# SESSION END + SUMMARY
# ==============================================================================
Write-LogEvent -Level INFO -Status 'SESSION_END' `
    -Message ("Session ended. Succeeded={0} Failed={1} Errors={2}" -f $script:SuccessList.Count, $script:FailureList.Count, $script:ErrorList.Count) `
    -Data @{
        TCPResultDetail = ('Succeeded={0} Failed={1} Errors={2}' -f $script:SuccessList.Count, $script:FailureList.Count, $script:ErrorList.Count)
        Comment         = ''
    }

Show-ScriptSummary -Title "PORT CONNECTIVITY TEST SUMMARY"