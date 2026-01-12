<#
.SYNOPSIS
    Reads an exported file and opens paths in Windows Explorer.
    Features a Choice to open all or pick specific folders via a Grid View.
#>

#Clear-Host
$VariableContext = "EXPLORER PATH IMPORTER (TABBED) V8"

# --- DESIGN: CONTEXT HEADER ---
Write-Host "****************************************************" -ForegroundColor White
Write-Host " CONTEXT HEADER: $VariableContext" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor White

# --- DESIGN: PURPOSE AND PROMPTS HEADER ---
Write-Host "****************************************************" -ForegroundColor White
Write-Host " Script Purpose and Prompts" -ForegroundColor Yellow
Write-Host ""
Write-Host " This script is for opening your exported list of "
Write-Host " opened 'Windows Explorer Folder Paths' and will be "
Write-Host " prompted for the following answers:"
Write-Host ""
Write-Host " 1. Input directory path"
Write-Host " 2. List available 'input' files by file type"
Write-Host " 3. Open All or Pick specific folders"
Write-Host "****************************************************" -ForegroundColor White

# --- NEW PROMPT: CLEAR TERMINAL (Placed here as a reading pause) ---
Write-Host "`nDo you want to clear script terminal before running this script?" -ForegroundColor White
Write-Host "[Y]es | [N]o: " -ForegroundColor White -NoNewline
$clearChoice = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $clearChoice

if ($clearChoice -eq 'y') { Clear-Host }

# --- PROMPT 1: DIRECTORY SCAN ---
Write-Host "`n--- Starting Import Process ---" -ForegroundColor Cyan
$inputDir = Read-Host "Input directory path where exports are stored"

if (-not (Test-Path $inputDir)) {
    Write-Host "Error: Directory not found." -ForegroundColor Red
    return
}

# --- PROMPT 2: FILE TYPE FILTER (Instant Keypress) ---
Write-Host "List available 'input' files by file type or all: [C]sv | [T]xt | [A]ll: " -ForegroundColor White -NoNewline
$filterType = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $filterType

$fileList = if ($filterType -eq 'c') {
    Get-ChildItem -Path $inputDir -File | Where-Object { $_.Extension -eq ".csv" }
} elseif ($filterType -eq 't') {
    Get-ChildItem -Path $inputDir -File | Where-Object { $_.Extension -eq ".txt" }
} else {
    Get-ChildItem -Path $inputDir -File
}

$fileList = $fileList | Sort-Object LastWriteTime -Descending

if (-not $fileList) {
    Write-Host "`nNo files found matching filter." -ForegroundColor Yellow
    return
}

Write-Host "`nAvailable files:" -ForegroundColor White
for ($i = 0; $i -lt $fileList.Count; $i++) {
    Write-Host "[$($i + 1)] $($fileList[$i].Name)" -ForegroundColor Gray
}

# --- FILE SELECTION (Internal Logic) ---
Write-Host "`nEnter selection number: " -ForegroundColor White -NoNewline
$selection = Read-Host
if (-not [int]::TryParse($selection, [ref]$selectedIndex)) { return }
$selectedIndex-- 

if ($selectedIndex -lt 0 -or $selectedIndex -ge $fileList.Count) {
    Write-Host "Invalid selection." -ForegroundColor Red
    return
}

$selectedFile = $fileList[$selectedIndex]
Write-Host "Selected File: $($selectedFile.Name)" -ForegroundColor Cyan

# --- LOGIC: READ DATA ---
$data = if ($selectedFile.Extension -eq ".csv") {
    Import-Csv -Path $selectedFile.FullName
} else {
    Get-Content -Path $selectedFile.FullName | ForEach-Object { [PSCustomObject]@{ Path = $_ } }
}

# --- PROMPT 3: OPENING METHOD (Instant Keypress) ---
Write-Host "`nOpen [A]ll folders or [P]ick specific folders to open: " -ForegroundColor White -NoNewline
$openMethod = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $openMethod

$foldersToOpen = @()

if ($openMethod -eq 'p') {
    Write-Host "`nLaunching Selection Window..." -ForegroundColor Yellow
    # GridView allows visual selection
    $foldersToOpen = $data | Out-GridView -Title "Select specific folders to open" -OutputMode Multiple
} else {
    $foldersToOpen = $data
}

if (-not $foldersToOpen) {
    Write-Host "No folders were selected to open." -ForegroundColor Yellow
    return
}

# --- LOGIC: OPEN IN TABS ---
Write-Host "`nOpening $($foldersToOpen.Count) folders in tabs..." -ForegroundColor Green

foreach ($item in $foldersToOpen) {
    $path = $item.Path
    if (Test-Path $path) {
        Start-Process "explorer.exe" -ArgumentList "`"$path`""
        Start-Sleep -Milliseconds 900
    } else {
        Write-Host "Path no longer exists: $path" -ForegroundColor Red
    }
}

Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " TASK COMPLETE" -ForegroundColor White
Write-Host "****************************************************" -ForegroundColor White