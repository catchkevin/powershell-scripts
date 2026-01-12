# ==============================================================================
# SCRIPT: Directory Structure Exporter (Integrated)
# CONTEXT: HEADER_CORE_TEMPLATE_V3 | DYNAMIC_EXPORT_TEMPLATE_V6
# UPDATED: 2026-01-11 09:00:00
# ==============================================================================

# 1. SET CONTEXT AND VERSION
$VariableContext = "DIR_EXPORTER_INTEGRATED_V3"
$LastUpdated     = "2026-01-11 09:00:00"

# --- DESIGN: CONTEXT HEADER ---
Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " CONTEXT: $VariableContext" -ForegroundColor Cyan
Write-Host " UPDATED: $LastUpdated" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor White

# --- DESIGN: PURPOSE AND PROMPTS HEADER ---
Write-Host " Script Purpose:" -ForegroundColor Yellow
Write-Host " Recursively scans a source directory and provides terminal display"
Write-Host " and optional file export of all discovered paths."
Write-Host ""
Write-Host " Input/Steps Required:" -ForegroundColor Yellow
Write-Host " 1. Provide the source directory path to scan."
Write-Host " 2. Select export options (File vs. Terminal Only)."
Write-Host " 3. Define export path and naming preferences."
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
# START MAIN SCRIPT LOGIC
# ==============================================================================
Write-Host "`n--- Execution Started ---" -ForegroundColor Green

# Setup Audit Arrays
$SuccessList = @()
$SkippedList = @()
$DefaultList = @()

# Source Path Selection
Write-Host "`nSource Selection:" -ForegroundColor Yellow
$targetPath = Read-Host " >> Enter the Directory Path to scan"

if (-not (Test-Path $targetPath)) {
    Write-Host " [!] Source path not found. Exiting." -ForegroundColor Red
    exit
}

Write-Host " Scanning directory... please wait." -ForegroundColor Gray

# Collect data - Creating an object for better Table/CSV formatting
$DataToExport = Get-ChildItem -Path $targetPath -Recurse | Select-Object @{Name="Path"; Expression={$_.FullName}}
$DefaultList = $DataToExport

# ==============================================================================
# EXPORT LOGIC (Template V6)
# ==============================================================================

$exportQuery = Read-Host "`nCreate Export File? [Y]es | [N]o | [E]xit"
$exportSelection = $exportQuery.ToLower()

if ($exportSelection -eq 'e') { Write-Host "Exiting..." -ForegroundColor Red; exit }

if ($exportSelection -eq 'y') {
    # --- DEFINE & CHOOSE PATH ---
    $Path_Personal_1 = "$env:USERPROFILE\OneDrive\Documents\projects\script exports"
    $Path_Personal_2 = "$env:USERPROFILE\OneDrive\Documents\projects\script exports for inputs"
    $Path_Work       = "ENTER_PATH_HERE"

    Write-Host "`nSelect Export Location:" -ForegroundColor Yellow
    Write-Host " 1. Personal: $Path_Personal_1"
    Write-Host " 2. Inputs:   $Path_Personal_2"
    Write-Host " 3. Provide a different path"
    
    $pathChoice = Read-Host " Selection [1] | [2] | [3]"
    switch ($pathChoice) {
        "1" { $exportDir = $Path_Personal_1 }
        "2" { $exportDir = $Path_Personal_2 }
        "3" { $exportDir = Read-Host " >> Provide Export File Path" }
        Default { Write-Host "Invalid choice. Defaulting to Personal 1." -ForegroundColor Yellow; $exportDir = $Path_Personal_1 }
    }

    if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }

    # --- NAMING & PREFERENCE LOGIC ---
    $dateTimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $defaultBase   = "Directory_Inventory"

    # REQUIREMENT: Display Default File Name before asking for custom (V6)
    Write-Host "`nDefault file name: $defaultBase" -ForegroundColor Gray
    $nameToggle = Read-Host " Custom Export File Name? [Y]es | [N]o"
    $baseName = if ($nameToggle.ToLower() -eq 'y') { Read-Host " >> Enter File Name" } else { $defaultBase }

    Write-Host "`nFilename Preference:" -ForegroundColor White
    $orderInput = Read-Host " [D]ate_Time_Name | [N]ame_Date_Time"
    
    $fileName = if ($orderInput.ToLower() -eq 'n') { "${baseName}_${dateTimeStamp}" } else { "${dateTimeStamp}_${baseName}" }

    # --- FORMAT SELECTION ---
    $typeInput = Read-Host "`nExport type: [C]sv | [T]xt | [B]oth"
    $type = $typeInput.ToLower()

    # --- FINAL CONFIRMATION ---
    Write-Host "`nPROPOSED EXPORT:" -ForegroundColor Yellow
    Write-Host " Path: $exportDir"
    Write-Host " File: $fileName"
    $confirm = Read-Host "`nConfirm Export Path and File Name: [C]ontinue | [E]xit"

    if ($confirm.ToLower() -eq 'e') { 
        Write-Host "Export Cancelled." -ForegroundColor Red 
    } else {
        # --- EXECUTE EXPORTS ---
        $fullPathBase = Join-Path $exportDir $fileName
        try {
            if ($type -eq 'c' -or $type -eq 'b') {
                $DataToExport | Export-Csv -Path "$fullPathBase.csv" -NoTypeInformation
                Write-Host " [+] Exported CSV: $fullPathBase.csv" -ForegroundColor Cyan
                $SuccessList += "$fileName.csv"
            }
            if ($type -eq 't' -or $type -eq 'b') {
                $DataToExport.Path | Out-File -FilePath "$fullPathBase.txt"
                Write-Host " [+] Exported TXT: $fullPathBase.txt" -ForegroundColor Cyan
                $SuccessList += "$fileName.txt"
            }
        } catch {
            Write-Host " [!] Error during export: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} else {
    Write-Host "`nSkipping file export..." -ForegroundColor Gray
}

# ==============================================================================
# TERMINAL OUTPUT (Mandatory V6)
# ==============================================================================
Write-Host "`n--- TERMINAL RESULTS DISPLAY ---" -ForegroundColor Yellow
if ($null -ne $DataToExport -and $DataToExport.Count -gt 0) {
    # Displaying the list of paths in a table for scannability
    $DataToExport | Format-Table -AutoSize
} else {
    Write-Host " [!] No data available to display." -ForegroundColor Red
}
Write-Host "--- End of Results ---`n"

# ==============================================================================
# SUMMARY REPORT
# ==============================================================================
Write-Host "--- PROCESSING SUMMARY ---" -ForegroundColor Blue
Write-Host "Total Items Scanned: $($DefaultList.Count)" -ForegroundColor White
Write-Host "Total Files Created: $($SuccessList.Count)" -ForegroundColor Green

if ($SuccessList.Count -gt 0) {
    foreach ($item in $SuccessList) { Write-Host " [+] Created: $item" -ForegroundColor Green }
}
Write-Host "--------------------------" -ForegroundColor Blue
Write-Host "Done.`n"