# VS Code Workspace Manager (Tabbed V8)

A high-performance PowerShell toolkit designed to backup and restore active Visual Studio Code sessions. This project utilizes a **Deep Desktop Window Scan** to overcome the limitations of standard process tracking and the VS Code SQLite database lock issues.

---

## 📂 Project Overview

Managing multiple VS Code windows can be resource-intensive and disorganized. This project provides two primary scripts that act as a "Save State" and "Restore State" for your development environment:

1.  **Workspace Exporter:** Scans the Windows Desktop API to identify all unique open VS Code folders.
2.  **Workspace Importer:** Reads exported data and batch-launches workspaces back into VS Code.

## 🛠 Technical Architecture

### Deep Scan Technology
Unlike traditional scripts that query `Get-Process`, which often misses unfocused or background windows, the Exporter utilizes a native **C# / .NET Type Definition** to hook into `user32.dll`. This allows the script to:
* Enumerate all visible windows on the desktop.
* Extract titles from Windows that aren't currently "Main" processes.
* Filter out "Extension Host" and "N/A" titles to ensure data cleanlines.

### Tabbed V8 Framework
Both scripts utilize the **V8 Framework** style, which features:
* **Variable Context Headers:** Clear identification of script version and scope.
* **Interactive Keypress Prompts:** Uses `RawUI.ReadKey` for instant interaction (Y/N/E) without requiring the Enter key.
* **PowerShell 5.1 Compatibility:** Avoids modern operators (like `??`) to ensure it runs on standard Windows machines.

---

## 🚀 Usage Instructions

### 1. Exporting Workspaces
Run `VSCode_Exporter.ps1` when you have your desired workspaces open.
* **Debug Mode [D]:** Shows every active window title found by the Windows API. Use this if a window isn't being detected.
* **Standard Run [S]:** Cleanly identifies folders and prepares them for export.
* **Export Types:** Supports `.csv` (for data processing) and `.txt` (for clean lists).

### 2. Importing Workspaces
Run `VSCode_Importer.ps1` to restore a previous session.
* **Directory Scan:** Point the script to your export folder.
* **Grid View Selection:** If you choose **[P]ick**, a GUI window will appear allowing you to multi-select exactly which workspaces to open.
* **Staggered Launch:** The script includes a `500ms` delay between launches to prevent VS Code Instance collisions.

---

## 📋 Script Logic Flow

### Exporter Logic
1.  **Terminal Check:** Option to clear screen or exit.
2.  **Window Enumeration:** Invokes `user32.dll` to find all strings matching `* - Visual Studio Code`.
3.  **Title Parsing:** Splits the title string to isolate the folder name.
4.  **Deduplication:** Filters out redundant paths and background tools.
5.  **File Generation:** Saves to a timestamped file: `YYYYMMDD_HHMMSS_FileName.csv`.

### Importer Logic
1.  **File Filter:** Allows filtering by CSV or TXT.
2.  **Header Resolution:** Dynamically maps headers like `Path`, `WorkspacePath`, or `WindowTitle` to ensure compatibility across different export versions.
3.  **Existence Validation:** Performs a `Test-Path` check to ensure the folder hasn't been moved or deleted before attempting to open it.
4.  **CLI Execution:** Uses the `code` command-line interface to launch windows.

---

## ⚠️ Requirements & Troubleshooting

* **Execution Policy:** Ensure your policy allows local scripts: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`.
* **VS Code CLI:** The `code` command must be in your system PATH (Standard with VS Code installation).
* **Missing Windows:** If a window is not detected, ensure it is **not minimized to the System Tray** (it must be a visible desktop window).

---

## 📜 Version History
* **V8.0 (Current):** Switched to `EnumWindows` API for 100% detection accuracy.
* **V7.0:** Initial SQLite/JSON scan implementation (Deprecated due to file locks).
* **V1.0 - V6.0:** Basic Explorer path tracking and manual list building.

---
*Created as part of the Explorer Path Importer (Tabbed) V8 Suite.*