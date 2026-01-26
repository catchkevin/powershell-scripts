
<# 
Tracert Live Hop Display + Optional Daily-Rolled CSV Logging

Run modes:
- Continuous (2): repeats tracert after each run, optional delay between runs
- Once (1): runs one tracert and then prompts to Run Again (Y) or Quit (Q)

Logging:
- Prompt: Enable Logging (Yes/No) accepts: y, yes, n, no
- Log filename is auto-generated from Target + timestamp:
    traceroute_<target_sanitized>_yyyymmdd_HHmmss.csv
- Rolls log automatically when system date changes (new day)

NOTE (VS Code):
- Use "Run PowerShell File" / F5. Avoid "Run Selection/Line" for scripts like this.
#>

function Start-TracertLogger {

    function Parse-HopLine {
        param(
            [string]$Line,
            [string]$Target,
            [datetime]$RunTime
        )

        # Matches hop lines such as:
        #  1   <1 ms  <1 ms  <1 ms  router [10.0.0.1]
        #  2    *      *      *     Request timed out.
        $hopLinePattern = '^\s*(\d+)\s+(\*|<\d+|\d+)\s*(?:ms)?\s+(\*|<\d+|\d+)\s*(?:ms)?\s+(\*|<\d+|\d+)\s*(?:ms)?\s+(.*)$'

        if ($Line -match $hopLinePattern) {
            $hop  = [int]$matches[1]
            $t1   = $matches[2]
            $t2   = $matches[3]
            $t3   = $matches[4]
            $tail = $matches[5].Trim()

            $status  = 'OK'
            $HopHost = $null   # avoids collision with PowerShell automatic variable $Host
            $HopIP   = $null

            if ($tail -match 'Request timed out\.') {
                $status = 'TIMEOUT'
            } else {
                if ($tail -match '^(.*)\s+\[(.+)\]$') {
                    $HopHost = $matches[1].Trim()
                    $HopIP   = $matches[2].Trim()
                }
                elseif ($tail -match '^(\d{1,3}(?:\.\d{1,3}){3})$') {
                    $HopIP = $tail
                }
                else {
                    $HopHost = $tail
                }
            }

            return [pscustomobject]@{
                DateTime     = $RunTime.ToString('yyyyMMdd_HHmmss')     # <-- NEW (matches logfile stamp format)
                RunTimestamp = $RunTime.ToString('yyyy-MM-dd HH:mm:ss') # original readable format
                Target       = $Target
                Hop          = $hop
                Host         = $HopHost
                IP           = $HopIP
                RTT1         = $t1
                RTT2         = $t2
                RTT3         = $t3
                Status       = $status
            }
        }

        return $null
    }

    function Invoke-TracertLive {
        param(
            [string]$Target,
            [datetime]$RunTime
        )

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName               = 'tracert'
        $psi.Arguments              = $Target
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true

        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $psi
        [void]$proc.Start()

        $hopObjects = New-Object System.Collections.Generic.List[object]

        # Header per run (UPDATED: includes DateTime column)
        Write-Host ('{0,-15} {1,3} {2,-45} {3,-15} {4,7} {5,7} {6,7} {7}' -f 'DateTime','Hop','Host','IP','RTT1','RTT2','RTT3','Status') -ForegroundColor Gray
        Write-Host ('{0,-15} {1,3} {2,-45} {3,-15} {4,7} {5,7} {6,7} {7}' -f '--------','---','----','--','----','----','----','------') -ForegroundColor Gray

        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $hopObj = Parse-HopLine -Line $line -Target $Target -RunTime $RunTime
            if ($null -ne $hopObj) {
                $hopObjects.Add($hopObj) | Out-Null

                $hostOut = if ($hopObj.Host) { $hopObj.Host } else { '' }
                $ipOut   = if ($hopObj.IP)   { $hopObj.IP }   else { '' }

                $row = '{0,-15} {1,3} {2,-45} {3,-15} {4,7} {5,7} {6,7} {7}' -f `
                        $hopObj.DateTime, $hopObj.Hop, $hostOut, $ipOut, $hopObj.RTT1, $hopObj.RTT2, $hopObj.RTT3, $hopObj.Status

                if ($hopObj.Status -eq 'TIMEOUT') { Write-Host $row -ForegroundColor Yellow } else { Write-Host $row }
            }
        }

        # Drain stderr if any
        while (-not $proc.StandardError.EndOfStream) {
            $errLine = $proc.StandardError.ReadLine()
            if (-not [string]::IsNullOrWhiteSpace($errLine)) {
                Write-Host $errLine -ForegroundColor DarkYellow
            }
        }

        $proc.WaitForExit()
        return $hopObjects
    }

    function Get-LogFilePath {
        param(
            [string]$LogDirectory,
            [string]$Target
        )

        $now = Get-Date
        $todayKey = $now.ToString('yyyyMMdd')

        if ($script:CurrentLogDay -ne $todayKey) {
            $script:CurrentLogDay = $todayKey

            # Replace periods with underscores, and sanitize invalid filename chars
            $safeTarget = ($Target -replace '\.', '_')
            $safeTarget = ($safeTarget -replace '[\\/:*?"<>|]', '_')

            $stamp = $now.ToString('yyyyMMdd_HHmmss')
            $fileName = "traceroute_{0}_{1}.csv" -f $safeTarget, $stamp

            $script:LogFilePath = Join-Path $LogDirectory $fileName
        }

        return $script:LogFilePath
    }

    # -------------------------
    # PROMPTS
    # -------------------------

    $Target = Read-Host 'Enter for URL/IP'
    if ([string]::IsNullOrWhiteSpace($Target)) {
        Write-Host 'Target cannot be blank. Exiting.' -ForegroundColor Red
        return
    }

    Write-Host 'Interval:'
    Write-Host '    Press 1 | Run Once'
    Write-Host '    Press 2 | Continuous'

    do {
        $Mode = (Read-Host 'Enter Selection: ').Trim().ToUpper()
    } while ($Mode -notin @('1','2'))

    $DelaySeconds = 0
    if ($Mode -eq '2') {
        $delayInput = Read-Host 'Interval (enter seconds between continuous runs OR "0" to run immediately)'
        if (-not [string]::IsNullOrWhiteSpace($delayInput)) {
            [void][int]::TryParse($delayInput, [ref]$DelaySeconds)
        }
    }

    # Logging: single line, accepts y/yes/n/no
    do {
        $logChoice = (Read-Host 'Enable Logging (Yes/No)').Trim().ToLower()
    } while ($logChoice -notin @('y','yes','n','no'))

    $EnableLogging = ($logChoice -in @('y','yes'))
    $LogDirectory  = $null

    if ($EnableLogging) {
        $LogDirectory = Read-Host 'Enter file path location'

        if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
            Write-Host 'Logging selected but path missing. Disabling logging.' -ForegroundColor Yellow
            $EnableLogging = $false
        }
        else {
            if (-not (Test-Path -Path $LogDirectory)) {
                New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
            }

            # Initialize rollover tracking
            $script:CurrentLogDay = $null
            $script:LogFilePath   = $null

            # Compute and display initial log path ONCE
            $initialLogPath = Get-LogFilePath -LogDirectory $LogDirectory -Target $Target
            Write-Host ''
            Write-Host 'Logging enabled (auto-generated filename based on Target + date/time):' -ForegroundColor Green
            Write-Host ("  {0}" -f $initialLogPath) -ForegroundColor Green
        }
    }

    Write-Host ''
    Write-Host 'Starting tracert. Press CTRL+C to stop (Continuous mode).' -ForegroundColor Green
    Write-Host ''

    # -------------------------
    # RUN
    # -------------------------

    $KeepRunning = $true

    while ($KeepRunning) {

        $runTime = Get-Date

        Write-Host ('=' * 70) -ForegroundColor DarkGray
        Write-Host ("Run: {0} | Target: {1}" -f $runTime.ToString('yyyy-MM-dd HH:mm:ss'), $Target) -ForegroundColor Cyan
        Write-Host ('=' * 70) -ForegroundColor DarkGray

        $hopObjects = Invoke-TracertLive -Target $Target -RunTime $runTime

        if ($EnableLogging -and $LogDirectory) {
            $logPath = Get-LogFilePath -LogDirectory $LogDirectory -Target $Target

            if (-not (Test-Path $logPath)) {
                $hopObjects | Export-Csv -Path $logPath -NoTypeInformation
            } else {
                $hopObjects | Export-Csv -Path $logPath -NoTypeInformation -Append
            }

            Write-Host ("Logged hops to: {0}" -f $logPath) -ForegroundColor Green
        }

        # Continuous mode: sleep and run again (no Run Again/Quit prompt)
        if ($Mode -eq '2') {
            if ($DelaySeconds -gt 0) {
                Start-Sleep -Seconds $DelaySeconds
            }
            continue
        }

        # Run Once mode (1) => prompt to run again or quit
        Write-Host ''
        Write-Host ('-' * 40) -ForegroundColor DarkGray
        Write-Host 'Run Again (Y) or Quit (Q): ' -NoNewline

        do {
            $againChoice = ([Console]::ReadLine()).Trim().ToUpper()
        } while ($againChoice -notin @('Y','Q'))

        if ($againChoice -eq 'Y') {
            continue
        }

        Write-Host 'Exiting.' -        Write-Host 'Exiting.' -ForegroundColor DarkGray
        $KeepRunning = $false
    }
}

# Call the main function when running the file
Start-TracertLogger