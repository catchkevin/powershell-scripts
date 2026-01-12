<#
.SYNOPSIS
    Retrieves open Explorer paths with an instant-keypress UI, Exit functionality,
    and a Date_Time_Name file naming convention.
#>

#Clear-Host
$VariableContext = "EXPLORER PATH EXPORTER V2"

# --- DESIGN: CONTEXT HEADER ---
Write-Host "****************************************************" -ForegroundColor White
Write-Host " CONTEXT HEADER: $VariableContext" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor White

# --- DESIGN: PURPOSE AND PROMPTS HEADER ---
Write-Host "****************************************************" -ForegroundColor White
Write-Host " Script Purpose and Prompts" -ForegroundColor Yellow
Write-Host ""
Write-Host " This script retrieves all currently open Windows "
Write-Host " Explorer paths and exports them to a file for backup "
Write-Host " or later import. You will be prompted for:"
Write-Host ""
Write-Host " 1. Script Logic Type (Detailed or Single Line)"
Write-Host " 2. Export decision (Yes/No/Exit)"
Write-Host " 3. Export file type (Csv/Txt/Both)"
Write-Host " 4. Export directory path"
Write-Host " 5. Custom file naming option"
Write-Host "****************************************************" -ForegroundColor White

# --- PROMPT: CLEAR TERMINAL (Pause for reading) ---
Write-Host "`nDo you want to clear script terminal before running this script?" -ForegroundColor White
Write-Host "[Y]es | [N]o: " -ForegroundColor White -NoNewline
$clearChoice = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $clearChoice

if ($clearChoice -eq 'y') { Clear-Host }

# --- DESIGN: PROMPT & SELECTION (INSTANT KEYPRESS) ---
Write-Host "`n--- Starting Export Process ---" -ForegroundColor Cyan

# Prompt 1: Script Logic Type
Write-Host "Select [D]etailed Script or [S]ingle Line Script: " -ForegroundColor White -NoNewline
$scriptType = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $scriptType

# --- CORE LOGIC: GET PATHS ---
$Paths = try {
    $ShellApp = New-Object -ComObject Shell.Application
    # Get paths from all open "File Explorer" windows
    $ShellApp.Windows() | Where-Object { $_.Name -match "Explorer" } | ForEach-Object {
        $_.Document.Folder.Self.Path
    }
} catch { $null }

# Display result to screen
if ($Paths) {
    Write-Host "`nCurrently Open Paths:" -ForegroundColor Green
    $Paths | ForEach-Object { Write-Host " - $_" }
} else {
    Write-Host "`nNo open Explorer windows found." -ForegroundColor Yellow
}

# --- EXPORT PROMPTS ---

Write-Host "`nExport list for backup or import? [Y]es | [N]o | [E]xit: " -ForegroundColor White -NoNewline
$exportChoice = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $exportChoice

# Logic for Exit
if ($exportChoice -eq 'e') { 
    Write-Host "`nExiting script..." -ForegroundColor Red
    return 
}

if ($exportChoice -eq 'y') {
    
    Write-Host "Export type: [C]sv | [T]xt | [B]oth: " -ForegroundColor White -NoNewline
    $type = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
    Write-Host $type

    # Directory Path requires Read-Host for full string input
    $exportDir = Read-Host "`nExport Directory Path"
    if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }

    Write-Host "Custom Export File Name? [Y]es | [N]o: " -ForegroundColor White -NoNewline
    $customNameToggle = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
    Write-Host $customNameToggle

    # --- NAMING LOGIC ---
    # Format: yyyyMMdd_HHmmss
    $dateStamp = Get-Date -Format "yyyyMMdd"
    $timeStamp = Get-Date -Format "HHmmss"
    $defaultName = "open file paths export"
    
    if ($customNameToggle -eq 'y') {
        $appendName = Read-Host " Enter Custom Name to Append"
        $fileName = "$($dateStamp)_$($timeStamp)_$($appendName)"
    } else {
        $fileName = "$($dateStamp)_$($timeStamp)_$($defaultName)"
    }

    $fullPathBase = Join-Path $exportDir $fileName

    # Execute Exports
    if ($type -eq 'c' -or $type -eq 'b') {
        # Export as CSV with 'Path' header for future import
        $Paths | ForEach-Object { [PSCustomObject]@{ Path = $_ } } | Export-Csv -Path "$fullPathBase.csv" -NoTypeInformation
        Write-Host "Successfully exported CSV: $fullPathBase.csv" -ForegroundColor Cyan
    }
    if ($type -eq 't' -or $type -eq 'b') {
        $Paths | Out-File -FilePath "$fullPathBase.txt"
        Write-Host "Successfully exported TXT: $fullPathBase.txt" -ForegroundColor Cyan
    }

} else {
    Write-Host "`nSkipping Export." -ForegroundColor Gray
}

Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " TASK COMPLETE" -ForegroundColor White
Write-Host "****************************************************" -ForegroundColor White