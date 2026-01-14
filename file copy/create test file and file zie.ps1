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
# Prompt user to start
# -------------------------
$createFiles = Read-YesNo "Do you need to create files [Yes | No]"

if (-not $createFiles) {
    Write-Host "File creation cancelled by user."
    exit
}

# -------------------------
# Set folder path
# -------------------------
$folder = "$env:USERPROFILE\Documents\filecopytest_files"
if (-not (Test-Path $folder)) {
    New-Item -Path $folder -ItemType Directory | Out-Null
}

Write-Host "These file sizes will be created in the following path:"
Write-Host $folder -ForegroundColor Green

# -------------------------
# Default file sizes in MB
# -------------------------
# 1MB, 100MB, 1GB, 2GB, 5GB, 10GB
$fileSizesMB = @(
    1,
    100,
    1024,   # 1GB
    2048,   # 2GB
    5120,   # 5GB
    10240   # 10GB
)

# -------------------------
# Prompt for additional file sizes
# -------------------------
$addMore = Read-YesNo "Create Additional File Sizes [Yes | No]"

if ($addMore) {
    $inputSizes = Read-Host "Input additional file sizes required in GB separated by commas [ex: 100, 300, 500, 1000]"
    if ($inputSizes) {
        $additionalSizesMB = $inputSizes -split ',' |
            ForEach-Object { [int]($_.Trim()) * 1024 }   # Convert GB to MB
        $fileSizesMB += $additionalSizesMB
    }
}

# Remove duplicates and sort
$fileSizesMB = $fileSizesMB | Sort-Object -Unique

# -------------------------
# Create CSV files
# -------------------------
foreach ($sizeMB in $fileSizesMB) {
    $sizeBytes = $sizeMB * 1MB
    $fileName = "$folder\File_${sizeMB}MB.csv"

    # CSV line content
    $line = "Column1,Column2,Column3,Column4,Column5"
    $lineBytes = [Text.Encoding]::UTF8.GetByteCount($line + "`r`n")
    $linesNeeded = [math]::Ceiling($sizeBytes / $lineBytes)

    Write-Host "Creating $fileName (~$sizeMB MB)..."

    $fs = [System.IO.File]::OpenWrite($fileName)
    $sw = New-Object System.IO.StreamWriter($fs)

    for ($i = 0; $i -lt $linesNeeded; $i++) {
        $sw.WriteLine($line)
    }

    $sw.Close()
    $fs.Close()

    Write-Host "Created $fileName"
}

Write-Host "All files created successfully in $folder" -ForegroundColor Cyan
