# ==============================================================================
# SCRIPT:   ping_multi_ip_monitor.ps1
# CONTEXT:  PING_MULTI_IP_MONITOR
# PURPOSE:  Ping single or multiple IP addresses or hostnames concurrently and
#           display results on a single pipe-delimited line per round.
#           Supports Single IP/Host, comma-separated Multiple, or CSV import.
#           Auto-resolves hostnames from IPs and IPs from hostnames at startup.
# ==============================================================================

# ==============================================================================
# SECTION 1 — HEADER INFO
# ==============================================================================

$VariableContext = "PING_MULTI_IP_MONITOR"
$Version         = "V1"
$LastUpdated     = "2026-06-26 00:00:00"
$ScriptName      = $MyInvocation.MyCommand.Name

Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " SCRIPT:  $ScriptName"          -ForegroundColor Cyan
Write-Host " CONTEXT: $VariableContext"     -ForegroundColor Cyan
Write-Host " VERSION: $Version"             -ForegroundColor Cyan
Write-Host " UPDATED: $LastUpdated"         -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor White
Write-Host " Script Purpose:"               -ForegroundColor Yellow
Write-Host " Ping one or more IP addresses or hostnames concurrently."
Write-Host " Results display on a single pipe-delimited line per round."
Write-Host " Auto-resolves hostname from IP and IP from hostname at startup."
Write-Host " Supports single entry, comma-separated list, or CSV/TXT/JSON import."
Write-Host ""
Write-Host " Input/Steps Required:"         -ForegroundColor Yellow
Write-Host " 1. Select input mode: [S]ingle | [M]ultiple | [C]sv file"
Write-Host " 2. Provide IP address(es), hostname(s), or select import file"
Write-Host " 3. Configure logging and output mode"
Write-Host " 4. Script resolves all targets then pings concurrently each round"
Write-Host "****************************************************" -ForegroundColor White

# --- INTERACTION: RUN OR EXIT ---
Write-Host "`nDo you want to run this script?" -ForegroundColor White

$runChoice = ""
while ($runChoice -notin @('y', 'e')) {
    $runChoice = (Read-Host " [Y]es | [E]xit").ToLower()
    if ($runChoice -notin @('y', 'e')) {
        Write-Host " Invalid selection. Please enter Y or E." -ForegroundColor Red
    }
}

if ($runChoice -eq 'e') {
    Write-Host "`nExiting script. No action has been taken. Have a great day!" -ForegroundColor Yellow
    exit
}

# --- INTERACTION: CLEAR TERMINAL BEFORE CONTINUING ---
Write-Host "`nDo you want to clear the terminal before continuing?" -ForegroundColor White

$clearChoice = ""
while ($clearChoice -notin @('y', 'n')) {
    $clearChoice = (Read-Host " [Y]es | [N]o").ToLower()
    if ($clearChoice -notin @('y', 'n')) {
        Write-Host " Invalid selection. Please enter Y or N." -ForegroundColor Red
    }
}

if ($clearChoice -eq 'y') {
    Clear-Host
}

Write-Host "Proceeding..." -ForegroundColor Gray

# ==============================================================================
# SECTION 2 — GLOBAL LOGGING STATE
# ==============================================================================

$Global:LogFilePath      = $null
$Global:LogFormat        = "JSON"
$Global:LogSessionId     = [System.Guid]::NewGuid().ToString()
$Global:EnableDebugLog   = $false
$Global:DebugLogPath     = $null
$Global:EnableEventLog   = $false
$Global:EventLogPath     = $null

# ==============================================================================
# SECTION 3 — LOGGING FUNCTIONS
# ==============================================================================

function Get-LogFilePath {
    param([string]$BaseDir, [string]$BaseName, [string]$Format)
    $date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
    $ext  = switch ($Format) { "CSV" { "csv" } "TXT" { "txt" } default { "json" } }
    return Join-Path $BaseDir "$BaseName`_$date.$ext"
}

function Initialize-LogFile {
    param([string]$Path, [string]$Format)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (-not (Test-Path $Path)) {
        if ($Format -eq "CSV") {
            "Timestamp,LogSessionId,ScriptName,Level,Status,Message,ErrorMessage,Detail1Key,Detail1Value,Detail2Key,Detail2Value,Detail3Key,Detail3Value" | Set-Content $Path -Encoding UTF8
        } else {
            New-Item -ItemType File -Path $Path -Force | Out-Null
        }
    }
}

function Write-LogEntry-TXT {
    param($Path,$Timestamp,$SessionId,$Script,$Level,$Status,$Message,$ErrorMessage,
          $D1K,$D1V,$D2K,$D2V,$D3K,$D3V)
    $line = "[$Timestamp] [$Level] [$Status] [$Script] [$SessionId] $Message"
    if ($ErrorMessage) { $line += " | ERROR: $ErrorMessage" }
    if ($D1K)          { $line += " | $D1K=$D1V" }
    if ($D2K)          { $line += " | $D2K=$D2V" }
    if ($D3K)          { $line += " | $D3K=$D3V" }
    Add-Content -Path $Path -Value $line -Encoding UTF8
}

function Write-LogEntry-CSV {
    param($Path,$Timestamp,$SessionId,$Script,$Level,$Status,$Message,$ErrorMessage,
          $D1K,$D1V,$D2K,$D2V,$D3K,$D3V)
    $row = '"{0}","{1}","{2}","{3}","{4}","{5}","{6}","{7}","{8}","{9}","{10}","{11}","{12}"' -f `
        $Timestamp,$SessionId,$Script,$Level,$Status,$Message,$ErrorMessage,
        $D1K,$D1V,$D2K,$D2V,$D3K,$D3V
    Add-Content -Path $Path -Value $row -Encoding UTF8
}

function Write-LogEntry-JSON {
    param($Path,$Timestamp,$SessionId,$Script,$Level,$Status,$Message,$ErrorMessage,
          $D1K,$D1V,$D2K,$D2V,$D3K,$D3V)
    $obj = [ordered]@{
        Timestamp    = $Timestamp
        LogSessionId = $SessionId
        ScriptName   = $Script
        Level        = $Level
        Status       = $Status
        Message      = $Message
        ErrorMessage = $ErrorMessage
        Detail1Key   = $D1K;  Detail1Value = $D1V
        Detail2Key   = $D2K;  Detail2Value = $D2V
        Detail3Key   = $D3K;  Detail3Value = $D3V
    }
    Add-Content -Path $Path -Value ($obj | ConvertTo-Json -Compress) -Encoding UTF8
}

function Write-LogEvent {
    param(
        [string]$Level   = "INFO",
        [string]$Status  = "",
        [string]$Message = "",
        [string]$ErrorMessage = "",
        [string]$Detail1Key   = "", [string]$Detail1Value = "",
        [string]$Detail2Key   = "", [string]$Detail2Value = "",
        [string]$Detail3Key   = "", [string]$Detail3Value = "",
        [switch]$SuppressConsole
    )
    $ts = (Get-Date).ToUniversalTime().ToString("o")
    if (-not $SuppressConsole) {
        $color = switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } default { "Gray" } }
        Write-Host "[$Level][$Status] $Message" -ForegroundColor $color
    }
    if ($Global:LogFilePath) {
        $args = @($Global:LogFilePath,$ts,$Global:LogSessionId,$ScriptName,
                  $Level,$Status,$Message,$ErrorMessage,
                  $Detail1Key,$Detail1Value,$Detail2Key,$Detail2Value,$Detail3Key,$Detail3Value)
        switch ($Global:LogFormat) {
            "TXT"  { Write-LogEntry-TXT  @args }
            "CSV"  { Write-LogEntry-CSV  @args }
            default { Write-LogEntry-JSON @args }
        }
    }
}

# ==============================================================================
# SECTION 4 — IMPORT PATH CONFIGURATION
# ==============================================================================

$Import_Path_1 = "C:ScriptsImports"   # UPDATE BEFORE FIRST USE
$Import_Path_2 = "C:ScriptsImports"   # UPDATE BEFORE FIRST USE

# ==============================================================================
# SECTION 5 — DNS RESOLUTION FUNCTION
# ==============================================================================

function Resolve-PingTarget {
    param([string]$Entry)
    $result = [ordered]@{
        OriginalEntry    = $Entry
        ResolvedHostname = ""
        ResolvedIPAddress = ""
        Label            = ""
        IsValid          = $false
    }
    try {
        if ($Entry -match '^d{1,3}(.d{1,3}){3}$') {
            $result.ResolvedIPAddress = $Entry
            try {
                $dns = [System.Net.Dns]::GetHostEntry($Entry)
                $result.ResolvedHostname = $dns.HostName
            } catch { $result.ResolvedHostname = $Entry }
        } else {
            $result.ResolvedHostname = $Entry
            $dns = [System.Net.Dns]::GetHostEntry($Entry)
            $result.ResolvedIPAddress = ($dns.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1).ToString()
        }
        $result.Label    = "$($result.ResolvedHostname)_$($result.ResolvedIPAddress)"
        $result.IsValid  = $true
    } catch {
        $result.Label   = "$Entry_UNRESOLVED"
        $result.IsValid = $false
    }
    return $result
}

# ==============================================================================
# SECTION 6 — CONCURRENT PING FUNCTION
# ==============================================================================

function Invoke-ConcurrentPing {
    param([array]$Targets, [int]$TimeoutMs = 1000)
    $pool    = [runspacefactory]::CreateRunspacePool(1, $Targets.Count)
    $pool.Open()
    $jobs    = @()
    $script  = {
        param($Label, $IP, $Timeout)
        $ping   = New-Object System.Net.NetworkInformation.Ping
        $opts   = New-Object System.Net.NetworkInformation.PingOptions
        $opts.Ttl = 64
        $buffer = [byte[]]::new(32)
        try {
            $reply = $ping.Send($IP, $Timeout, $buffer, $opts)
            if ($reply.Status -eq 'Success') {
                [pscustomobject]@{ Label=$Label; IP=$IP; Status="Successful"; LatencyMs=$reply.RoundtripTime }
            } else {
                [pscustomobject]@{ Label=$Label; IP=$IP; Status="Timeout"; LatencyMs=$null }
            }
        } catch {
            [pscustomobject]@{ Label=$Label; IP=$IP; Status="Error"; LatencyMs=$null }
        }
    }
    foreach ($t in $Targets) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($script).AddArgument($t.Label).AddArgument($t.ResolvedIPAddress).AddArgument($TimeoutMs)
        $jobs += [pscustomobject]@{ PS=$ps; Handle=$ps.BeginInvoke() }
    }
    $results = foreach ($j in $jobs) {
        $j.PS.EndInvoke($j.Handle)
        $j.PS.Dispose()
    }
    $pool.Close(); $pool.Dispose()
    return $results
}

function Format-PingRoundLine {
    param([array]$Results, [datetime]$RoundTime)
    $ts      = $RoundTime.ToString("yyyy-MM-dd HH:mm:ss")
    $segments = foreach ($r in $Results) {
        $suffix = if ($r.Status -eq "Successful") { "$($r.LatencyMs)ms" } else { $r.Status.ToLower() }
        "$($r.Status)-$($r.Label)-$suffix"
    }
    return "$ts | " + ($segments -join " | ")
}

# ==============================================================================
# SECTION 7 — LOGGING INITIALIZATION
# ==============================================================================

Write-Host "`n--- Logging Setup ---" -ForegroundColor White
$logDir = Read-Host " Log directory path (leave blank to skip logging)"
if ($logDir -and (Test-Path $logDir)) {
    Write-Host " Format: [J]SON | [C]SV | [T]XT" -ForegroundColor White
    $fmtChoice = (Read-Host " Select format").ToLower()
    $Global:LogFormat = switch ($fmtChoice) { "c" { "CSV" } "t" { "TXT" } default { "JSON" } }
    $Global:LogFilePath = Get-LogFilePath -BaseDir $logDir -BaseName "ping_multi_ip_monitor" -Format $Global:LogFormat
    Initialize-LogFile -Path $Global:LogFilePath -Format $Global:LogFormat
    Write-Host " Logging to: $($Global:LogFilePath)" -ForegroundColor Gray
} else {
    Write-Host " Logging disabled." -ForegroundColor Gray
}

# ==============================================================================
# SECTION 8 — INPUT MODE SELECTION
# ==============================================================================

Write-Host "`n--- Input Mode ---" -ForegroundColor White
$inputMode = ""
while ($inputMode -notin @('s','m','c')) {
    $inputMode = (Read-Host " [S]ingle | [M]ultiple | [C]sv/TXT/JSON file").ToLower()
    if ($inputMode -notin @('s','m','c')) {
        Write-Host " Invalid selection. Please enter S, M, or C." -ForegroundColor Red
    }
}

$rawEntries = @()

switch ($inputMode) {
    's' {
        $rawEntries = @((Read-Host " Enter IP or hostname").Trim())
    }
    'm' {
        $rawEntries = (Read-Host " Enter IPs/hostnames comma-separated").Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    'c' {
        Write-Host "`n Available import paths:" -ForegroundColor White
        Write-Host "  [1] $Import_Path_1"
        Write-Host "  [2] $Import_Path_2"
        Write-Host "  [3] Enter custom path"
        $pathChoice = (Read-Host " Select [1] | [2] | [3]").Trim()
        $importDir  = switch ($pathChoice) {
            "1" { $Import_Path_1 }
            "2" { $Import_Path_2 }
            default {
                $custom = Read-Host " Enter full file path"
                Split-Path $custom -Parent
            }
        }
        if ($pathChoice -eq "3") {
            $importFile = Read-Host " Enter full file path"
        } else {
            $files = Get-ChildItem -Path $importDir -Include *.csv,*.txt,*.json -File -ErrorAction SilentlyContinue
            if (-not $files) { Write-Host " No supported files found in $importDir" -ForegroundColor Red; exit }
            Write-Host "`n Files found:" -ForegroundColor White
            for ($i=0; $i -lt $files.Count; $i++) { Write-Host "  [$($i+1)] $($files[$i].Name)" }
            $fi = [int](Read-Host " Select file number") - 1
            $importFile = $files[$fi].FullName
        }
        $ext = [System.IO.Path]::GetExtension($importFile).ToLower()
        switch ($ext) {
            ".json" {
                $data = Get-Content $importFile -Raw | ConvertFrom-Json
                $col  = ($data[0].PSObject.Properties.Name | Where-Object { $_ -match 'ip|host|address|target|name' } | Select-Object -First 1)
                if (-not $col) { $col = $data[0].PSObject.Properties.Name[0] }
                $rawEntries = $data | ForEach-Object { $_.$col }
            }
            ".csv" {
                $data = Import-Csv $importFile
                $col  = ($data[0].PSObject.Properties.Name | Where-Object { $_ -match 'ip|host|address|target|name' } | Select-Object -First 1)
                if (-not $col) { $col = $data[0].PSObject.Properties.Name[0] }
                $rawEntries = $data | ForEach-Object { $_.$col }
            }
            default {
                $rawEntries = Get-Content $importFile | Where-Object { $_.Trim() -and -not $_.StartsWith('#') }
            }
        }
    }
}

# ==============================================================================
# SECTION 9 — DNS RESOLUTION
# ==============================================================================

Write-Host "`n--- Resolving Targets ---" -ForegroundColor White
$targets = @()
foreach ($entry in $rawEntries) {
    $resolved = Resolve-PingTarget -Entry $entry
    if ($resolved.IsValid) {
        Write-Host "  OK  $($resolved.Label)" -ForegroundColor Green
        Write-LogEvent -Level "INFO" -Status "RESOLVE" -Message "Target resolved: $($resolved.Label)" `
            -Detail1Key "OriginalEntry"    -Detail1Value $resolved.OriginalEntry `
            -Detail2Key "ResolvedHostname" -Detail2Value $resolved.ResolvedHostname `
            -Detail3Key "ResolvedIPAddress" -Detail3Value $resolved.ResolvedIPAddress `
            -SuppressConsole
    } else {
        Write-Host "  FAIL $entry (unresolved)" -ForegroundColor Red
        Write-LogEvent -Level "WARN" -Status "RESOLVE" -Message "Target unresolved: $entry" `
            -Detail1Key "OriginalEntry" -Detail1Value $entry `
            -Detail2Key "ResolvedHostname" -Detail2Value "" `
            -Detail3Key "ResolvedIPAddress" -Detail3Value "" `
            -SuppressConsole
    }
    $targets += $resolved
}
$targets = $targets | Where-Object { $_.IsValid }
if (-not $targets) { Write-Host "`nNo valid targets resolved. Exiting." -ForegroundColor Red; exit }

# ==============================================================================
# SECTION 10 — PING CONFIGURATION
# ==============================================================================

Write-Host "`n--- Ping Configuration ---" -ForegroundColor White
$timeoutMs = [int](Read-Host " Timeout per ping in ms [default 1000]")
if ($timeoutMs -le 0) { $timeoutMs = 1000 }

$intervalSec = [int](Read-Host " Interval between rounds in seconds [default 5]")
if ($intervalSec -le 0) { $intervalSec = 5 }

$maxRounds = [int](Read-Host " Max rounds (0 = continuous)")

# ==============================================================================
# SECTION 11 — PRE-RUN SUMMARY
# ==============================================================================

Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " PRE-RUN SUMMARY" -ForegroundColor Yellow
Write-Host "****************************************************" -ForegroundColor White
Write-Host " Targets   : $($targets.Count)"
foreach ($t in $targets) { Write-Host "   - $($t.Label)" }
Write-Host " Timeout   : $timeoutMs ms"
Write-Host " Interval  : $intervalSec sec"
Write-Host " Max Rounds: $(if ($maxRounds -eq 0) { 'Continuous' } else { $maxRounds })"
Write-Host " Log File  : $(if ($Global:LogFilePath) { $Global:LogFilePath } else { 'Disabled' })"
Write-Host "****************************************************" -ForegroundColor White

$confirmStart = ""
while ($confirmStart -notin @('y','e')) {
    $confirmStart = (Read-Host "`n Start pinging? [Y]es | [E]xit").ToLower()
    if ($confirmStart -notin @('y','e')) {
        Write-Host " Invalid selection. Please enter Y or E." -ForegroundColor Red
    }
}
if ($confirmStart -eq 'e') {
    Write-Host "`nExiting script. No action has been taken. Have a great day!" -ForegroundColor Yellow
    exit
}

# ==============================================================================
# SECTION 12 — MAIN PING LOOP
# ==============================================================================

Write-Host "`n--- Ping Monitor Started (Ctrl+C to stop) ---`n" -ForegroundColor White
$roundNum = 0

try {
    while ($true) {
        $roundNum++
        $roundTime = Get-Date
        $results   = Invoke-ConcurrentPing -Targets $targets -TimeoutMs $timeoutMs

        $successCount = ($results | Where-Object { $_.Status -eq "Successful" }).Count
        $failCount    = ($results | Where-Object { $_.Status -ne "Successful" }).Count
        $line         = Format-PingRoundLine -Results $results -RoundTime $roundTime

        $color = if ($failCount -eq 0) { "Green" } elseif ($successCount -eq 0) { "Red" } else { "Yellow" }
        Write-Host $line -ForegroundColor $color

        $targetList = ($results | ForEach-Object { $_.Label }) -join ","
        Write-LogEvent -Level "INFO" -Status "PING_ROUND" `
            -Message "Round $roundNum complete: $successCount OK, $failCount failed" `
            -Detail1Key "PingSuccessCount" -Detail1Value $successCount `
            -Detail2Key "PingTimeoutCount" -Detail2Value $failCount `
            -Detail3Key "PingTargetList"   -Detail3Value $targetList `
            -SuppressConsole

        foreach ($r in $results) {
            $evtStatus = if ($r.Status -eq "Successful") { "PING_OK" } else { "PING_FAIL" }
            $evtLevel  = if ($r.Status -eq "Successful") { "INFO" }    else { "WARN" }
            Write-LogEvent -Level $evtLevel -Status $evtStatus `
                -Message "$($r.Status): $($r.Label)" `
                -Detail1Key "TargetLabel" -Detail1Value $r.Label `
                -Detail2Key "LatencyMs"   -Detail2Value $(if ($r.LatencyMs -ne $null) { $r.LatencyMs } else { "" }) `
                -Detail3Key "RoundNumber" -Detail3Value $roundNum `
                -SuppressConsole
        }

        if ($maxRounds -gt 0 -and $roundNum -ge $maxRounds) { break }
        Start-Sleep -Seconds $intervalSec
    }
} catch {
    Write-Host "`nMonitor interrupted." -ForegroundColor Yellow
}

# ==============================================================================
# SECTION 13 — COMPLETION SUMMARY
# ==============================================================================

Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " COMPLETED" -ForegroundColor Green
Write-Host "****************************************************" -ForegroundColor White
Write-Host " Rounds completed : $roundNum"
Write-Host " Log file         : $(if ($Global:LogFilePath) { $Global:LogFilePath } else { 'Disabled' })"
Write-Host "****************************************************`n" -ForegroundColor White

Write-LogEvent -Level "INFO" -Status "COMPLETE" `
    -Message "Script completed after $roundNum rounds." `
    -Detail1Key "RoundsCompleted" -Detail1Value $roundNum `
    -Detail2Key "" -Detail2Value "" `
    -Detail3Key "" -Detail3Value "" `
    -SuppressConsole
