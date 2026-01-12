<#
.DESCRIPTION
    VS CODE WORKSPACE IMPORTER V8
    Reads an exported file (CSV/TXT) and opens the paths as VS Code Workspaces.
    Features a choice to open all detected paths or pick specific ones via GridView.

.PROMPTS
    1. Clear Terminal Toggle (Yes/No/Exit)
    2. Input Directory Selection
    3. File Type Filter (CSV/TXT/All)
    4. Opening Method (All/Pick)
#>

$VariableContext = "VS CODE WORKSPACE IMPORTER V8"
$SuccessList = @()
$SkippedList = @()
$DefaultList = @() 

# --- DESIGN: CONTEXT HEADER ---
Write-Host "****************************************************" -ForegroundColor White
Write-Host " CONTEXT HEADER: $VariableContext" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor White

# --- DESIGN: PURPOSE AND PROMPTS HEADER ---
Write-Host "****************************************************" -ForegroundColor White
Write-Host " Script Purpose and Prompts" -ForegroundColor Yellow
Write-Host ""
Write-Host " This script reads your exported VS Code workspace"
Write-Host " list and opens them. You will be prompted for:"
Write-Host ""
Write-Host " 1. Input directory path"
Write-Host " 2. File selection from available exports"
Write-Host " 3. Open All or Pick specific workspaces"
Write-Host "****************************************************" -ForegroundColor White

# --- PROMPT: CLEAR TERMINAL ---
Write-Host "`nDo you want to clear script terminal before running this script?" -ForegroundColor White
Write-Host "[Y]es | [N]o | [E]xit: " -ForegroundColor White -NoNewline
$clearChoice = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $clearChoice

if ($clearChoice -eq 'e') { return }
if ($clearChoice -eq 'y') { Clear-Host }

# --- PROMPT 1: DIRECTORY SCAN ---
Write-Host "`n--- Starting Import Process ---" -ForegroundColor Cyan
$inputDir = Read-Host "Input directory path where exports are stored"

if (-not (Test-Path $inputDir)) {
    Write-Host "Error: Directory not found." -ForegroundColor Red
    return
}

# --- PROMPT 2: FILE TYPE FILTER ---
Write-Host "List available files by type: [C]sv | [T]xt | [A]ll: " -ForegroundColor White -NoNewline
$filterType = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $filterType

$fileList = if ($filterType -eq 'c') {
    Get-ChildItem -Path $inputDir -File | Where-Object { $_.Extension -eq ".csv" }
} elseif ($filterType -eq 't') {
    Get-ChildItem -Path $inputDir -File | Where-Object { $_.Extension -eq ".txt" }
} else {
    Get-ChildItem -Path $inputDir -File | Where-Object { $_.Extension -match "csv|txt" }
}

$fileList = $fileList | Sort-Object LastWriteTime -Descending

if (-not $fileList) {
    Write-Host "`nNo export files found in $inputDir" -ForegroundColor Yellow
    return
}

Write-Host "`nAvailable export files (Newest first):" -ForegroundColor White
for ($i = 0; $i -lt $fileList.Count; $i++) {
    Write-Host "[$($i + 1)] $($fileList[$i].Name)" -ForegroundColor Gray
}

# --- FIXED SELECTION LOGIC ---
Write-Host "`nEnter selection number: " -ForegroundColor White -NoNewline
$selectionInput = Read-Host

# Initialize variable to avoid [ref] error in PS 5.1
$selectedIndex = 0
if (-not [int]::TryParse($selectionInput, [ref]$selectedIndex)) { 
    Write-Host "Invalid input: Please enter a number." -ForegroundColor Red
    return 
}
$selectedIndex-- 

if ($selectedIndex -lt 0 -or $selectedIndex -ge $fileList.Count) {
    Write-Host "Invalid selection: Number out of range." -ForegroundColor Red
    return
}

$selectedFile = $fileList[$selectedIndex]
Write-Host "Selected File: $($selectedFile.Name)" -ForegroundColor Cyan

# --- LOGIC: READ DATA ---
$data = if ($selectedFile.Extension -eq ".csv") {
    $rawCsv = Import-Csv -Path $selectedFile.FullName
    $rawCsv | ForEach-Object { 
        $foundPath = ""
        if ($_.Path) { $foundPath = $_.Path }
        elseif ($_.WorkspacePath) { $foundPath = $_.WorkspacePath }
        elseif ($_.WindowTitle) { $foundPath = $_.WindowTitle }
        
        [PSCustomObject]@{ Path = $foundPath } 
    }
} else {
    Get-Content -Path $selectedFile.FullName | Where-Object { $_ -ne "" } | ForEach-Object { [PSCustomObject]@{ Path = $_ } }
}

$DefaultList = $data

# --- PROMPT 3: OPENING METHOD ---
Write-Host "`nOpen [A]ll workspaces or [P]ick specific ones: " -ForegroundColor White -NoNewline
$openMethod = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $openMethod

$workspacesToOpen = @()

if ($openMethod -eq 'p') {
    Write-Host "`nLaunching Selection Window..." -ForegroundColor Yellow
    $workspacesToOpen = $DefaultList | Out-GridView -Title "Select VS Code Workspaces to Launch" -OutputMode Multiple
} else {
    $workspacesToOpen = $DefaultList
}

if (-not $workspacesToOpen) {
    Write-Host "No workspaces selected." -ForegroundColor Yellow
    return
}

# --- LOGIC: OPEN IN VS CODE ---
Write-Host "`nLaunching $($workspacesToOpen.Count) VS Code instances..." -ForegroundColor Green

foreach ($item in $workspacesToOpen) {
    $path = $item.Path
    # Check if path is valid or if it is a directory
    if ($path -and (Test-Path $path)) {
        Write-Host " [+] Opening: $path" -ForegroundColor Gray
        Start-Process "code" -ArgumentList "`"$path`""
        $SuccessList += $path
        Start-Sleep -Milliseconds 500 
    } else {
        Write-Host " [!] Path not found or invalid: $path" -ForegroundColor Red
        $SkippedList += $path
    }
}

# --- DESIGN: SUMMARY OUTPUT & RESULTS ---
Write-Host "`n--- PROCESSING SUMMARY ---" -ForegroundColor Blue
Write-Host "Total Paths in File: $($DefaultList.Count)" -ForegroundColor Cyan
Write-Host "Total Opened: $($SuccessList.Count)" -ForegroundColor Green
foreach ($item in $SuccessList) { Write-Host " [+] Launched: $item" }

if ($SkippedList.Count -gt 0) {
    Write-Host "Total Failed/Missing: $($SkippedList.Count)" -ForegroundColor Red
    foreach ($item in $SkippedList) { Write-Host " [X] Missing: $item" -ForegroundColor Red }
}

Write-Host "--------------------------" -ForegroundColor Blue
Write-Host "TASK COMPLETE" -ForegroundColor White