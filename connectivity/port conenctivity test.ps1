
<#CSV File Template Example
Legacy input rows supported (Output option ignored now):
IP,Port,S,Note
IP,Port,SE,Note

Also supported:
IP,Port,Note
#>

# -------------------------
# Helper: Yes/No prompt (accepts y/yes/n/no)
# -------------------------
function Read-YesNo {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

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
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    while ($true) {
        $raw = (Read-Host $Prompt).Trim().ToLower()
        switch ($raw) {
            'txt' { return 'txt' }
            'text' { return 'txt' }
            'csv' { return 'csv' }
            default { Write-Host "Please enter TXT or CSV." -ForegroundColor Yellow }
        }
    }
}

# -------------------------
# Logging (export type TXT/CSV + daily rollover + auto filename)
# -------------------------
$script:LoggingEnabled = $false
$script:LogFolder = $null
$script:LogFilePath = $null
$script:LogDay = $null        # yyyyMMdd
$script:LogType = $null       # 'txt' or 'csv'
$script:LogKey = $null        # sanitized target key used in file name
$script:LogPathDisplayed = $false

function Get-LogFilePath {
    param(
        [Parameter(Mandatory)][string]$LogFolder,
        [Parameter(Mandatory)][string]$LogKey,
        [Parameter(Mandatory)][ValidateSet('txt','csv')][string]$LogType
    )

    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $fileName = "testnetconnection_{0}_{1}.{2}" -f $LogKey, $ts, $LogType
    return (Join-Path -Path $LogFolder -ChildPath $fileName)
}

function New-LogFile {
    # Called on first log creation and on daily rollover
    if (-not (Test-Path -Path $script:LogFolder)) {
        New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
    }

    $script:LogFilePath = Get-LogFilePath -LogFolder $script:LogFolder -LogKey $script:LogKey -LogType $script:LogType
    $script:LogDay = Get-Date -Format 'yyyyMMdd'

    # For TXT, write a header line once per file
    if ($script:LogType -eq 'txt') {
        Add-Content -Path $script:LogFilePath -Value ("==== Test-NetConnection Log Started: {0} ====" -f (Get-Date -Format "MM.dd.yyyy | HH:mm:ss"))
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

    # Display log path ONLY ONCE when logging is enabled
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
    param(
        [Parameter(Mandatory)][hashtable]$Row
    )
    if (-not $script:LoggingEnabled) { return }
    Ensure-LogFile

    $obj = [PSCustomObject]$Row
    if (-not (Test-Path -Path $script:LogFilePath)) {
        $obj | Export-Csv -Path $script:LogFilePath -NoTypeInformation
    } else {
        # If file exists but is empty, still write header
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
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][ValidateSet('Success','Failure','Info')][string]$Status,
        [string]$Error = '',
        [string]$Comment = '',
        [string]$SourceIP = '',
        [string]$Message = ''
    )

    if (-not $script:LoggingEnabled) { return }

    if ($script:LogType -eq 'txt') {
        # Prefer the same human-readable line format for TXT
        if (-not $Message) {
            $ts = Get-Date -Format "MM.dd.yyyy | hh:mm:ss tt"
            if ($Status -eq 'Success') {
                $Message = "$ts - Connection to $Target ($SourceIP) on port $Port succeeded"
                if ($Comment) { $Message += " - $Comment (Source IP: $SourceIP)" }
                else { $Message += " (Source IP: $SourceIP)" }
            }
            elseif ($Status -eq 'Failure') {
                $Message = "$ts - Connection to $Target on port $Port failed: $Error"
                if ($Comment) { $Message += " - $Comment" }
            }
            else {
                $Message = "$ts - $Message"
            }
        }

        Write-LogText -Message $Message
    }
    else {
        # Structured output for CSV
        $row = @{
            DateTime = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            Target   = $Target
            Port     = $Port
            Status   = $Status
            Error    = $Error
            Comment  = $Comment
            SourceIP = $SourceIP
            Message  = $Message
        }
        Write-LogCsvRow -Row $row
    }
}

# -------------------------
# Email config (replaces Output option)
# -------------------------
$script:EmailEnabled = $false
$script:SMTPServer = $null
$script:FromEmail  = $null
$script:ToEmail    = $null

# -------------------------
# Configure Logging + Email (called AFTER test prompts)
# -------------------------
function Configure-LoggingAndEmail {
    param(
        [Parameter(Mandatory)][string]$LogKeyForFileName
    )

    # Logging prompt (per baseline order: logging then email)
    $script:LoggingEnabled = Read-YesNo -Prompt "Enable Logging (Yes/No): "
    if ($script:LoggingEnabled) {

        $script:LogType = Read-LogType -Prompt "Export file type (TXT/CSV): "
        $script:LogFolder = Read-Host "Enter the folder path for the log file (example: C:\Temp\Logs): "

        # Sanitize key: replace periods with underscores
        $script:LogKey = $LogKeyForFileName -replace '\.', '_'

        # Initialize log file + show path once
        New-LogFile
        Ensure-LogFile
    }

    # Email prompt
    $script:EmailEnabled = Read-YesNo -Prompt "Email (Yes or No): "
    if ($script:EmailEnabled) {
        $script:SMTPServer = Read-Host "Enter SMTP Server: "
        $script:FromEmail  = Read-Host "Enter From Email Address: "
        $script:ToEmail    = Read-Host "Enter To Email Address (comma-separated allowed): "
    }
}

# -------------------------
# Function: Test TCP connectivity (always outputs to screen)
# -------------------------
function Test-PortConnection {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][int]$Port,
        [string]$Comment = ""
    )

    $CurrentDateTime = Get-Date -Format "MM.dd.yyyy | hh:mm:ss tt"
    $ResolvedIP = $null

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($Target, $Port, $null, $null)

        $waitHandle = $asyncResult.AsyncWaitHandle
        $timeout = $waitHandle.WaitOne(5000)

        if (-not $timeout) {
            throw "Connection timed out after 5 seconds"
        }

        # Source IP (local endpoint)
        $ResolvedIP = $tcpClient.Client.LocalEndPoint.Address.IPAddressToString
        $tcpClient.EndConnect($asyncResult)
        $tcpClient.Close()

        $ConnectionStatus = "$CurrentDateTime - Connection to $Target ($ResolvedIP) on port $Port succeeded"
        if ($Comment) {
            $ConnectionStatus += " - $Comment (Source IP: $ResolvedIP)"
        } else {
            $ConnectionStatus += " (Source IP: $ResolvedIP)"
        }

        Write-Host $ConnectionStatus -ForegroundColor Green

        Write-LogRecord -Target $Target -Port $Port -Status 'Success' -Comment $Comment -SourceIP $ResolvedIP -Message $ConnectionStatus
    }
    catch {
        $ErrorMessage = $_.Exception.Message

        if ($ResolvedIP) {
            $ConnectionStatus = "$CurrentDateTime - Connection to $Target ($ResolvedIP) on port $Port failed: $ErrorMessage"
        } else {
            $ConnectionStatus = "$CurrentDateTime - Connection to $Target on port $Port failed: $ErrorMessage"
        }

        if ($Comment) {
            $ConnectionStatus += " - $Comment"
        }

        Write-Host $ConnectionStatus -ForegroundColor Red

        Write-LogRecord -Target $Target -Port $Port -Status 'Failure' -Error $ErrorMessage -Comment $Comment -SourceIP $ResolvedIP -Message $ConnectionStatus

        # Email on failure (if enabled)
        if ($script:EmailEnabled -and $script:SMTPServer -and $script:FromEmail -and $script:ToEmail) {
            try {
                $toAddresses = $script:ToEmail -split '\s*,\s*'
                Send-MailMessage -SmtpServer $script:SMTPServer -From $script:FromEmail -To $toAddresses `
                    -Subject "Test Port Connectivity Failure" -Body $ConnectionStatus -ErrorAction SilentlyContinue
            }
            catch {
                Write-Host "WARNING: Email notification failed." -ForegroundColor Yellow
                Write-LogRecord -Target $Target -Port $Port -Status 'Info' -Message 'WARNING: Email notification failed.'
            }
        }
    }
}

# -------------------------
# Main (baseline prompt order preserved)
# -------------------------
$TestType = Read-Host "Press '1' for a single IP test or '2' for input file: "

if ($TestType -eq '1') {

    # Prompt order unchanged until logging/email
    $Target   = Read-Host "Enter the URL/IP: "
    $Port     = Read-Host "Enter the Port: "
    $Interval = Read-Host "Enter the Interval (in seconds): "
    $Comment  = Read-Host "Enter Comment: "

    # Configure logging/email after comment
    Configure-LoggingAndEmail -LogKeyForFileName $Target

    # Run once
    Test-PortConnection -Target $Target -Port ([int]$Port) -Comment $Comment

    # Repeat if interval > 0
    if ([int]$Interval -gt 0) {
        while ($true) {
            Start-Sleep -Seconds ([int]$Interval)
            Test-PortConnection -Target $Target -Port ([int]$Port) -Comment $Comment
        }
    }

}
elseif ($TestType -eq '2') {

    $InputFilePath = Read-Host "Enter the path to the input file (CSV format): "
    $Lines = Get-Content -Path $InputFilePath
    $RepeatInterval = Read-Host 'Enter the interval to rerun the test (in seconds, "0"=Run Once): '

    # For file mode, use a stable key
    Configure-LoggingAndEmail -LogKeyForFileName "multiplehosts"

    while ($true) {
        foreach ($Line in $Lines) {

            if ([string]::IsNullOrWhiteSpace($Line)) { continue }
            if ($Line.Trim().StartsWith("#")) { continue }

            $LineValues = $Line -split ','

            if ($LineValues.Count -lt 2) { continue }

            # Skip header line if present
            if ($LineValues[0].Trim() -match '^(ip|dns|target)$' -and $LineValues[1].Trim() -match '^(port)$') { continue }

            $Target = $LineValues[0].Trim()
            $Port   = [int]$LineValues[1].Trim()

            # Output option removed; support legacy formats:
            #   Target,Port,S,Note -> comment is 4th column
            #   Target,Port,Note   -> comment is 3rd column unless it's S/SE
            $Comment = ""
            if ($LineValues.Count -ge 4) {
                $Comment = $LineValues[3].Trim()
            }
            elseif ($LineValues.Count -ge 3) {
                $third = $LineValues[2].Trim()
                if ($third -notin @("S","SE")) {
                    $Comment = $third
                }
            }

            Test-PortConnection -Target $Target -Port $Port -Comment $Comment
        }

        Write-Host "Test Completed" -ForegroundColor Blue
        Write-LogRecord -Target 'N/A' -Port 0 -Status 'Info' -Message ("Test Completed - {0}" -f (Get-Date -Format "MM.dd.yyyy | HH:mm:ss"))
        Write-LogRecord -Target 'N/A' -Port 0 -Status 'Info' -Message ""

        if ([int]$RepeatInterval -le 0) { break }
        Start-Sleep -Seconds ([int]$RepeatInterval)
    }

}
else {
    Write-Host "Invalid selection. Please choose '1' for a single IP test or '2' for input file test."    Write-Host "Invalid selection. Please choose '1' for a single IP test or '2' for input file test." -ForegroundColor Yellow
    Write-LogRecord -Target 'N/A' -Port 0 -Status 'Info' -Message "Invalid selection at main menu."
}