<#
.DESCRIPTION
    EXPLORER PATH IMPORTER (TABBED) V8 - VS Code Edition
    Enhanced detection: Scans all desktop windows to find multiple VS Code instances.
    Includes Debug Mode to troubleshoot missing windows.

.PROMPTS
    1. Clear Terminal Toggle (Yes/No/Exit)
    2. Export Choice (Yes/No/Exit)
    3. Export File Type (CSV/TXT/Both)
    4. Custom Naming Toggle
#>

$VariableContext = "EXPLORER PATH IMPORTER (TABBED) V8"
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
Write-Host " This script detects ALL open VS Code windows using "
Write-Host " a deep desktop window scan + Debug Mode."
Write-Host ""
Write-Host " 1. Choice to export to CSV or TXT"
Write-Host " 2. Custom file naming and directory selection"
Write-Host "****************************************************" -ForegroundColor White

# --- PROMPT: CLEAR TERMINAL ---
Write-Host "`nDo you want to clear script terminal before running this script?" -ForegroundColor White
Write-Host "[Y]es | [N]o | [E]xit: " -ForegroundColor White -NoNewline
$clearChoice = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $clearChoice

if ($clearChoice -eq 'e') { return }
if ($clearChoice -eq 'y') { Clear-Host }

# --- PROMPT: DEBUG MODE ---
Write-Host "`nEnable [D]ebug Mode (Show all found titles) or [S]tandard Run: " -ForegroundColor White -NoNewline
$debugMode = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $debugMode

# --- DATA LOGIC: DEEP DESKTOP SCAN ---
Write-Host "`nScanning Desktop for VS Code Windows..." -ForegroundColor Gray

# Tier 1: .NET Window Search (Much more reliable for multiple windows)
Add-Type @"
  using System;
  using System.Runtime.InteropServices;
  using System.Text;
  using System.Collections.Generic;

  public class WindowFinder {
    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder strText, int maxCount);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static List<string> GetOpenWindows() {
      List<string> windows = new List<string>();
      EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
        if (IsWindowVisible(hWnd)) {
          StringBuilder sb = new StringBuilder(256);
          GetWindowText(hWnd, sb, 256);
          string title = sb.ToString();
          if (!string.IsNullOrEmpty(title)) { windows.Add(title); }
        }
        return true;
      }, IntPtr.Zero);
      return windows;
    }
  }
"@

$AllWindows = [WindowFinder]::GetOpenWindows()
$Paths = @()

if ($debugMode -eq 'd') {
    Write-Host "`n--- DEBUG: ALL WINDOW TITLES FOUND ---" -ForegroundColor Yellow
    $AllWindows | ForEach-Object { Write-Host " DEBUG: $_" -ForegroundColor DarkGray }
    Write-Host "--- END DEBUG ---`n" -ForegroundColor Yellow
}

foreach ($Title in $AllWindows) {
    if ($Title -match " - Visual Studio Code") {
        $CleanTitle = $Title -replace " - Visual Studio Code", ""
        
        # Split title and take the last part (Folder Name)
        $Parts = $CleanTitle -split " - "
        $FolderName = $Parts[-1].Trim()
        
        if ($FolderName -and $FolderName -notmatch "Welcome|Extension Host") {
            $Paths += $FolderName
        }
    }
}

$DefaultList = $Paths | Select-Object -Unique

# Show detected items
if ($DefaultList.Count -gt 0) {
    Write-Host "`nDetected $($DefaultList.Count) Open VS Code Instances:" -ForegroundColor Green
    $DefaultList | ForEach-Object { Write-Host " -> $_" -ForegroundColor Gray }
} else {
    Write-Host "`nNo active VS Code windows found." -ForegroundColor Red
}

# --- TEMPLATE: DYNAMIC EXPORT LOGIC ---
Write-Host "`nExport list for backup? [Y]es | [N]o | [E]xit: " -ForegroundColor White -NoNewline
$exportChoice = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
Write-Host $exportChoice

if ($exportChoice -eq 'e') { return }

if ($exportChoice -eq 'y' -and $DefaultList.Count -gt 0) {
    Write-Host "Export type: [C]sv | [T]xt | [B]oth: " -ForegroundColor White -NoNewline
    $type = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
    Write-Host $type

    $exportDir = Read-Host "`nExport Directory Path"
    if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }

    Write-Host "Custom Export File Name? [Y]es | [N]o: " -ForegroundColor White -NoNewline
    $customNameToggle = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToLower()
    Write-Host $customNameToggle

    $dateStamp = Get-Date -Format "yyyyMMdd"
    $timeStamp = Get-Date -Format "HHmmss"
    $defaultBase = "VSCode_MultiWindow_Export" 
    
    if ($customNameToggle -eq 'y') {
        $manualName = Read-Host " Enter Custom Name"
        $fileName = "$($dateStamp)_$($timeStamp)_$manualName"
    } else {
        $fileName = "$($dateStamp)_$($timeStamp)_$defaultBase"
    }

    $fullPathBase = Join-Path $exportDir $fileName

    try {
        if ($type -eq 'c' -or $type -eq 'b') {
            $DefaultList | ForEach-Object { [PSCustomObject]@{ WindowTitle = $_ } } | Export-Csv -Path "$fullPathBase.csv" -NoTypeInformation
            Write-Host "Successfully exported CSV: $fullPathBase.csv" -ForegroundColor Cyan
            $SuccessList += "CSV Export"
        }
        if ($type -eq 't' -or $type -eq 'b') {
            $DefaultList | Out-File -FilePath "$fullPathBase.txt"
            Write-Host "Successfully exported TXT: $fullPathBase.txt" -ForegroundColor Cyan
            $SuccessList += "TXT Export"
        }
    } catch {
        Write-Host "An error occurred: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- DESIGN: SUMMARY OUTPUT ---
Write-Host "`n--- PROCESSING SUMMARY ---" -ForegroundColor Blue
Write-Host "Total Windows Detected: $($DefaultList.Count)" -ForegroundColor Cyan
Write-Host "Total Tasks Completed: $($SuccessList.Count)" -ForegroundColor Green
Write-Host "--------------------------" -ForegroundColor Blue