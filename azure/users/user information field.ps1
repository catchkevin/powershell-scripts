# ==============================================================================
# SCRIPT: Azure AD User Data Export Pro
# HEADER INFO FOR ALL SCRIPTS Standardizations (TEMPLATE)
# ------------------------------------------------------------------------------
$VariableContext = "AZURE_AD_USER_EXPORT_V10"
$LastUpdated     = "2026-02-05 20:10:00"

# --- DESIGN: CONTEXT HEADER ---
Write-Host "`n****************************************************" -ForegroundColor White
Write-Host " CONTEXT: $VariableContext" -ForegroundColor Cyan
Write-Host " UPDATED: $LastUpdated" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor White

# --- DESIGN: PURPOSE AND PROMPTS HEADER ---
Write-Host " Script Purpose:" -ForegroundColor Yellow
Write-Host " Advanced Azure AD extraction with multi-vendor and specific"
Write-Host " domain (Xifin/Service) exclusions plus manual domain filtering."
Write-Host ""
Write-Host " Input/Steps Required:" -ForegroundColor Yellow
Write-Host " 1. Scope & Account Status Filter"
Write-Host " 2. Configure Vendor, External, and Xifin Domain Toggles"
Write-Host " 3. Optional: Manual Email Domain Exclusion"
Write-Host " 4. Standardized Export & Results Summary"
Write-Host "****************************************************" -ForegroundColor White

# --- INTERACTION: RUN/CLEAR/EXIT ---
Write-Host "`nDo you want to clear script terminal before running?" -ForegroundColor White
$choice = Read-Host " [Y]es | [N]o | [E]xit"
if ($choice.ToLower() -eq 'e') { exit }

# ==============================================================================
# PRE-FLIGHT: MODULE & CONNECTION
# ==============================================================================
if (-not (Get-Module -ListAvailable Microsoft.Graph)) {
    Write-Host " [!] Microsoft Graph module not found. Installing..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Scope CurrentUser -AllowClobber -Force
}
if (!(Get-MgContext)) { Connect-MgGraph -Scopes "User.Read.All","Group.Read.All" }

# ==============================================================================
# AUDIT SETUP
# ==============================================================================
$SuccessList = @()
$SkippedList = @()
$EnabledCount = 0
$DisabledCount = 0

# ==============================================================================
# INTERACTION & PROMPT LOGIC
# ==============================================================================
Write-Host "`n****************************************************" -ForegroundColor White
$scopeInput = Read-Host " Scope: [S]ingle User | [M]ultiple Users | [A]ll Users | [I]nput File"
$scope = $scopeInput.ToLower()

$TargetUsers = @()
$FilterEnabledOnly = $false

# Filter Toggles
$IncludeOptimize = $true; $IncludeValor = $true; $IncludeOnQ = $true
$IncludeNaico = $true; $IncludeGebbs = $true; $IncludeEXT = $true
$IncludeXifinOnMic = $true; $IncludeServiceXifin = $true
$ExcludeDomain = $null

switch ($scope) {
    "s" {
        $email = Read-Host " >> Enter User Email Address"
        $TargetUsers = @($email)
    }
    "m" {
        $emails = Read-Host " >> Enter User Emails (Separated by comma or semi-colon)"
        $TargetUsers = $emails -split '[,;]' | ForEach-Object { $_.Trim() }
    }
    "a" {
        Write-Host ""
        $filterChoice = Read-Host " Filter: [E]nabled Users Only | [A]ll Users"
        if ($filterChoice.ToLower() -eq 'e') { $FilterEnabledOnly = $true }

        Write-Host "`n--- VENDOR / EXTERNAL / DOMAIN FILTERS ---" -ForegroundColor Yellow
        if ((Read-Host " Vendor 'Optimize':   [I]nclude | [E]xclude").ToLower() -eq 'e') { $IncludeOptimize = $false }
        if ((Read-Host " Vendor 'Valor':      [I]nclude | [E]xclude").ToLower() -eq 'e') { $IncludeValor = $false }
        if ((Read-Host " Vendor 'OnQ':        [I]nclude | [E]xclude").ToLower() -eq 'e') { $IncludeOnQ = $false }
        if ((Read-Host " Vendor 'Naico':      [I]nclude | [E]xclude").ToLower() -eq 'e') { $IncludeNaico = $false }
        if ((Read-Host " Vendor 'Gebbs':      [I]nclude | [E]xclude").ToLower() -eq 'e') { $IncludeGebbs = $false }
        if ((Read-Host " External (#EXT#):    [I]nclude | [E]xclude").ToLower() -eq 'e') { $IncludeEXT = $false }
        if ((Read-Host " xifin.onmicrosoft:   [I]nclude | [E]xclude").ToLower() -eq 'e') { $IncludeXifinOnMic = $false }
        if ((Read-Host " service.xifin.com:   [I]nclude | [E]xclude").ToLower() -eq 'e') { $IncludeServiceXifin = $false }
    }
    "i" {
        $Path_Personal = "$env:USERPROFILE\OneDrive\Documents\projects\toolbox\git commit push\scripts"
        $Path_Work     = "$env:USERPROFILE\OneDrive\Documents\dev_and_scripts\toolbox\git commit push\scripts"
        Write-Host "`nSelect Import Directory:" -ForegroundColor Yellow
        $dirChoice = Read-Host " Selection [1] Personal | [2] Work | [3] Custom"
        $importDir = switch($dirChoice) { "1"{$Path_Personal} "2"{$Path_Work} "3"{Read-Host " >> Path"} Default{$Path_Personal} }
        $fileList = Get-ChildItem -Path $importDir -File | Where-Object { $_.Extension -in ".csv", ".txt" }
        if (-not $fileList) { Write-Host "No files found."; exit }
        for ($i=0; $i -lt $fileList.Count; $i++) { Write-Host " [$($i+1)] $($fileList[$i].Name)" }
        $selectedIndex = [int](Read-Host "`nEnter selection") - 1
        $selectedFile = $fileList[$selectedIndex]
        $RawData = if ($selectedFile.Extension -eq ".csv") { (Import-Csv $selectedFile.FullName) } else { Get-Content $selectedFile.FullName | ForEach-Object { [PSCustomObject]@{ Email = $_ } } }
        $TargetUsers = $RawData | ForEach-Object { if ($_.Email) { $_.Email } else { $_.UserPrincipalName } }
    }
}

# --- MANUAL DOMAIN EXCLUSION ---
Write-Host ""
if ((Read-Host " Exclude a manual Email Domain? [Y]es | [N]o").ToLower() -eq 'y') {
    $ExcludeDomain = Read-Host " >> Enter domain (e.g. gmail.com)"
}

# ==============================================================================
# DATA RETRIEVAL & FILTERING LOGIC
# ==============================================================================
Write-Host "`nFetching data from Azure..." -ForegroundColor Cyan
$UsersToFetch = @()
$UserProps = "DisplayName","GivenName","Surname","UserPrincipalName","Mail","JobTitle","Department","EmployeeId","EmployeeType","OfficeLocation","AccountEnabled","OnPremisesSamAccountName"

if ($scope -eq "a") {
    $graphFilter = if ($FilterEnabledOnly) { "accountEnabled eq true" } else { $null }
    $AllUsers = Get-MgUser -All -Filter $graphFilter -Property $UserProps -ExpandProperty "Manager"
    
    $UsersToFetch = $AllUsers | Where-Object {
        $pass = $true
        # Vendor Checks
        if (-not $IncludeOptimize -and $_.Department -like "*Optimize*") { $pass = $false }
        if (-not $IncludeValor    -and $_.Department -like "*Valor*")    { $pass = $false }
        if (-not $IncludeOnQ      -and $_.Department -like "*OnQ*")      { $pass = $false }
        if (-not $IncludeNaico    -and $_.Department -like "*Naico*")    { $pass = $false }
        if (-not $IncludeGebbs    -and $_.Department -like "*Gebbs*")    { $pass = $false }
        # Specific UPN/Domain Checks
        if (-not $IncludeEXT      -and $_.UserPrincipalName -like "*#EXT#*") { $pass = $false }
        if (-not $IncludeXifinOnMic -and $_.UserPrincipalName -like "*xifin.onmicrosoft.com*") { $pass = $false }
        if (-not $IncludeServiceXifin -and $_.UserPrincipalName -like "*service.xifin.com*") { $pass = $false }
        # Manual Domain Check
        if ($null -ne $ExcludeDomain -and ($_.Mail -like "*$ExcludeDomain*" -or $_.UserPrincipalName -like "*$ExcludeDomain*")) { $pass = $false }
        $pass
    }
} else {
    foreach ($u in $TargetUsers) {
        if ([string]::IsNullOrWhiteSpace($u)) { continue }
        try {
            $userObj = Get-MgUser -UserId $u -Property $UserProps -ExpandProperty "Manager"
            # Apply UPN/Domain filters to targeted list
            $upn = $userObj.UserPrincipalName
            if ((-not $IncludeXifinOnMic -and $upn -like "*xifin.onmicrosoft.com*") -or
                (-not $IncludeServiceXifin -and $upn -like "*service.xifin.com*") -or
                ($null -ne $ExcludeDomain -and ($userObj.Mail -like "*$ExcludeDomain*" -or $upn -like "*$ExcludeDomain*"))) {
                $SkippedList += "$u (Filtered by Domain Rules)"
                continue
            }
            $UsersToFetch += $userObj
            $SuccessList += $u
        } catch { $SkippedList += $u }
    }
}

$DataToExport = foreach ($u in $UsersToFetch) {
    if ($u.AccountEnabled) { $EnabledCount++ } else { $DisabledCount++ }
    $MgrName = $u.Manager.AdditionalProperties.displayName
    $MgrMail = $u.Manager.AdditionalProperties.mail ?? $u.Manager.AdditionalProperties.userPrincipalName

    [PSCustomObject]@{
        "First Name"           = $u.GivenName
        "Last Name"            = $u.Surname
        "Display Name"         = $u.DisplayName
        "User Principal Name"  = $u.UserPrincipalName
        "SAM Account Name"     = $u.OnPremisesSamAccountName
        "Email Address"        = $u.Mail
        "Manager"              = $MgrName
        "Manager Email"        = $MgrMail
        "Job Title"            = $u.JobTitle
        "Department"           = $u.Department
        "Employee ID"          = $u.EmployeeId
        "Employee Type"        = $u.EmployeeType
        "Office Location"      = $u.OfficeLocation
        "Account Enabled"      = $u.AccountEnabled
    }
}

# ==============================================================================
# START EXPORT LOGIC (MANDATORY TEMPLATE V6)
# ==============================================================================
$exportQuery = Read-Host "`nCreate Export File? [Y]es | [N]o | [E]xit"
if ($exportQuery.ToLower() -eq 'e') { exit }
if ($exportQuery.ToLower() -eq 'y') {
    $Path_Personal = "$env:USERPROFILE\OneDrive\Documents\projects\toolbox\git commit push\scripts"
    $Path_Work     = "$env:USERPROFILE\OneDrive\Documents\dev_and_scripts\toolbox\git commit push\scripts"
    Write-Host "`nSelect Export Location:" -ForegroundColor Yellow
    $pathChoice = Read-Host " Selection [1] Personal | [2] Work | [3] Custom"
    $exportDir = switch ($pathChoice) { "1"{$Path_Personal} "2"{$Path_Work} "3"{Read-Host " >> Path"} Default{$Path_Personal} }

    if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }

    $dateTimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $defaultBase   = "AzureAD_User_Export"
    Write-Host "`nDefault file name: $defaultBase" -ForegroundColor Gray
    $baseName = if ((Read-Host " Custom Export File Name? [Y]es | [N]o").ToLower() -eq 'y') { Read-Host " >> Enter File Name" } else { $defaultBase }
    $orderInput = Read-Host "`nFilename Preference: [D]ate_Time_Name | [N]ame_Date_Time"
    $fileName = if ($orderInput.ToLower() -eq 'n') { "${baseName}_${dateTimeStamp}" } else { "${dateTimeStamp}_${baseName}" }
    $typeInput = Read-Host "`nExport type: [C]sv | [T]xt | [B]oth"
    $type = $typeInput.ToLower()

    Write-Host "`nPROPOSED EXPORT:" -ForegroundColor Yellow
    Write-Host " Path: $exportDir"
    Write-Host " File: $fileName"
    if ((Read-Host "`nConfirm Export: [C]ontinue | [E]xit").ToLower() -eq 'c') {
        $fullPathBase = Join-Path $exportDir $fileName
        try {
            if ($type -eq 'c' -or $type -eq 'b') { $DataToExport | Export-Csv -Path "$fullPathBase.csv" -NoTypeInformation }
            if ($type -eq 't' -or $type -eq 'b') { $DataToExport | Out-File -FilePath "$fullPathBase.txt" }
            Write-Host " [+] Export Complete." -ForegroundColor Cyan
        } catch { Write-Host " [!] Error: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

# ==============================================================================
# TERMINAL OUTPUT & SUMMARY
# ==============================================================================
Write-Host "`n--- TERMINAL RESULTS DISPLAY ---" -ForegroundColor Yellow
$DataToExport | Format-Table -AutoSize

Write-Host "`n--- PROCESSING SUMMARY ---" -ForegroundColor Blue
Write-Host "Total Records Finalized: $($DataToExport.Count)" -ForegroundColor White

if ($scope -eq "a") {
    Write-Host "Enabled Accounts:        $EnabledCount" -ForegroundColor Green
    Write-Host "Disabled Accounts:       $DisabledCount" -ForegroundColor Yellow
    Write-Host "Xifin.onmic Included:    $IncludeXifinOnMic" -ForegroundColor Gray
    Write-Host "Service.xifin Included:  $IncludeServiceXifin" -ForegroundColor Gray
    Write-Host "Manual Domain Excluded:  $($ExcludeDomain ?? 'None')" -ForegroundColor Gray
} else {
    Write-Host "Successful Lookups:      $($SuccessList.Count)" -ForegroundColor Green
    Write-Host "Skipped/Not Found:       $($SkippedList.Count)" -ForegroundColor Red
}

Write-Host "--------------------------" -ForegroundColor Blue
Write-Host "Done.`n"