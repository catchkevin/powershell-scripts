
# -------------------------
# Ping Logger (continuous like ping -t)
# Prompts:
#   Enter the URL/IP:
#   Enable Logging (Yes/No):
#   Export file type (TXT/CSV):
#   Enter the folder path for the log file (example: C:\Temp\Logs):
#
# Logging:
#   ping_<target>_<yyyyMMdd_HHmmss>.txt|csv
#   Daily rollover
#   Displays log path once
# -------------------------

# Ping behavior (no prompts)
$script:PingTimeoutMs   = 4000   # per attempt
$script:PingIntervalSec = 1      # like default ping cadence
$script:DefaultTTL      = 128

# -------------------------
# Helper: Yes/No prompt (accepts y/yes/n/no)
# -------------------------
function Read-YesNo {
    param([Parameter(Mandatory)][string]$Prompt)

    while ($true) {
        $raw = (Read-Host $Prompt).Trim().ToLower()
        switch ($raw) {
            'y'   { return $true }
            'yes' { return $true }
            'n'   { return $false }
            'no'  { return $false }
            default { Write-Host "Please enter Yes/No (y/yes/n/no)." -ForegroundColor Yellow }
        }
    }
}

# -------------------------
# Helper: Log type prompt (TXT/CSV)
# -------------------------
function Read-LogType {
    param([Parameter(Mandatory)][string]$Prompt)

    while ($true) {
        $raw = (Read-Host $Prompt).Trim().ToLower()
        switch ($raw) {
            'txt'  { return 'txt' }
            'text' { return 'txt' }
            'csv'  { return 'csv' }
            default { Write-Host "Please enter TXT or CSV." -ForegroundColor Yellow }
        }
    }
}

# -------------------------
# Logging (export type TXT/CSV + daily rollover + auto filename)
# -------------------------
$script:LoggingEnabled   = $false
$script:LogFolder        = $null
$script:LogFilePath      = $null
$script:LogDay           = $null        # yyyyMMdd
$script:LogType          = $null        # 'txt' or 'csv'
$script:LogKey           = $null        # sanitized target key used in file name
$script:LogPathDisplayed = $false

function Get-LogFilePath {
    param(
        [Parameter(Mandatory)][string]$LogFolder,
        [Parameter(Mandatory)][string]$LogKey,
        [Parameter(Mandatory)][ValidateSet('txt','csv')][string]$LogType
    )

    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $fileName = "ping_{0}_{1}.{2}" -f $LogKey, $ts, $LogType
    return (Join-Path -Path $LogFolder -ChildPath $fileName)
}

function New-LogFile {
    # Called on first log creation and on daily rollover
    if (-not (Test-Path -Path $script:LogFolder)) {
        New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
    }

    $script:LogFilePath = Get-LogFilePath -LogFolder $script:LogFolder -LogKey $script:LogKey -LogType $script:LogType
    $script:LogDay = Get-Date -Format 'yyyyMMdd'

    # For TXT, write a header line once per file (same pattern as your example)
    if ($script:LogType -eq 'txt') {
        Add-Content -Path $script:LogFilePath -Value ("==== Ping Log Started: {0} ====" -f (Get-Date -Format "MM.dd.yyyy | HH:mm:ss"))
        Add-Content -Path $script:LogFilePath -Value ""
    }
    # For CSV, header is written automatically on first Export-Csv write
}

function Ensure-LogFile {
    if (-not $script:LoggingEnabled) { return }

    $today = Get-Date -Format 'yyyyMMdd'
    if (-not $script:LogDay -or -not $script:LogFilePath -or $today -ne $script:LogDay) {
        New-LogFile
    }

    # Display log path ONLY ONCE when logging is enabled (same pattern)
    if (-not $script:LogPathDisplayed) {
        Write-Host ("Logging Enabled -> {0}" -f $script:LogFilePath) -ForegroundColor Cyan
        $script:LogPathDisplayed = $true
    }
}

function Write-LogText {
    param([Parameter(Mandatory)][string]$Message)
    if (-not $script:LoggingEnabled) { return }
    Ensure-LogFile
    Add-Content -Path $script:LogFilePath -Value $Message
}

function Write-LogCsvRow {
    param([Parameter(Mandatory)][hashtable]$Row)

    if (-not $script:LoggingEnabled) { return }
    Ensure-LogFile

    $obj = [PSCustomObject]$Row
    if (-not (Test-Path -Path $script:LogFilePath)) {
        $obj | Export-Csv -Path $script:LogFilePath -NoTypeInformation
    } else {
        $fileInfo = Get-Item -Path $script:LogFilePath -ErrorAction SilentlyContinue
        if ($fileInfo -and $fileInfo.Length -eq 0) {
            $obj | Export-Csv -Path $script:LogFilePath -NoTypeInformation
        } else {
            $obj | Export-Csv -Path $script:LogFilePath -NoTypeInformation -Append
        }
    }
}

function Write-LogRecord {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][ValidateSet('Success','Failure','Info')][string]$Status,
        [string]$ResolvedIP = '',
        [Nullable[int]]$LatencyMs = $null,
        [Nullable[int]]$TTL = $null,
        [string]$Error = '',
        [string]$Message = ''
    )

    if (-not $script:LoggingEnabled) { return }

    if ($script:LogType -eq 'txt') {
        Write-LogText -Message $Message
    }
    else {
        $row = @{
            DateTime   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            Target     = $Target
            ResolvedIP = $ResolvedIP
            Status     = $Status
            LatencyMs  = $LatencyMs
            TTL        = $TTL
            Error      = $Error
            Message    = $Message
        }
        Write-LogCsvRow -Row $row
    }
}

# -------------------------
# Configure Logging (called AFTER target prompt)
# -------------------------
function Configure-Logging {
    param([Parameter(Mandatory)][string]$LogKeyForFileName)

    $script:LoggingEnabled = Read-YesNo -Prompt "Enable Logging (Yes/No): "
    if ($script:LoggingEnabled) {

        $script:LogType = Read-LogType -Prompt "Export file type (TXT/CSV): "
        $script:LogFolder = Read-Host "Enter the folder path for the log file (example: C:\Temp\Logs): "

        # Sanitize key: replace periods with underscores + strip bad filename chars
        $script:LogKey = ($LogKeyForFileName -replace '\.', '_') -replace '[^a-zA-Z0-9_]+', '_'

        # Initialize log file + show path once
        New-LogFile
        Ensure-LogFile
    }
}

# -------------------------
# Continuous Ping (like ping -t) using .NET Ping
# -------------------------
function Invoke-PingForever {
    param([Parameter(Mandatory)][string]$Target)

    $pinger  = New-Object System.Net.NetworkInformation.Ping
    $options = New-Object System.Net.NetworkInformation.PingOptions($script:DefaultTTL, $false)
    $buffer  = [Text.Encoding]::ASCII.GetBytes(("a" * 32))  # 32-byte payload

    Write-Host "Press Ctrl+C to stop..." -ForegroundColor Yellow

    while ($true) {
        $CurrentDateTime = Get-Date -Format "MM.dd.yyyy | hh:mm:ss tt"
        $ResolvedIP = $null

        try {
            $reply = $pinger.Send($Target, $script:PingTimeoutMs, $buffer, $options)

            if ($reply.Status -eq 'Success') {
                $ResolvedIP = "$($reply.Address)"
                $latency = [int]$reply.RoundtripTime
                $ttl = $null
                try { $ttl = $reply.Options.Ttl } catch { $ttl = $null }

                # Write-Host line modeled after your sample pattern/wording
                $ConnectionStatus = "$CurrentDateTime - Ping to $Target ($ResolvedIP) succeeded"
                $ConnectionStatus += " (Latency: ${latency}ms"
                if ($ttl -ne $null) { $ConnectionStatus += ", TTL: $ttl" }
                $ConnectionStatus += ")"

                Write-Host $ConnectionStatus -ForegroundColor Green
                Write-LogRecord -Target $Target -Status 'Success' -ResolvedIP $ResolvedIP -LatencyMs $latency -TTL $ttl -Message $ConnectionStatus
            }
            else {
                $ErrorMessage = "$($reply.Status)"

                $ConnectionStatus = "$CurrentDateTime - Ping to $Target failed: $ErrorMessage"
                Write-Host $ConnectionStatus -ForegroundColor Red
                Write-LogRecord -Target $Target -Status 'Failure' -Error $ErrorMessage -Message $ConnectionStatus
            }
        }
        catch {
            $ErrorMessage = $_.Exception.Message

            $ConnectionStatus = "$CurrentDateTime - Ping to $Target failed: $ErrorMessage"
            Write-Host $ConnectionStatus -ForegroundColor Red
            Write-LogRecord -Target $Target -Status 'Failure' -Error $ErrorMessage -Message $ConnectionStatus
        }

        Start-Sleep -Seconds $script:PingIntervalSec
    }
}

# -------------------------
# Main (prompt order preserved)
# -------------------------
$Target = Read-Host "Enter the URL/IP: "
Configure-Logging -LogKeyForFileName $Target
Invoke-PingForever -Target $Target
