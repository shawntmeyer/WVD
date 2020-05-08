# ***************************************************************************
#
# Purpose: WVD Image Prep
#
# ------------- DISCLAIMER -------------------------------------------------
# This script code is provided as is with no guarantee or waranty concerning
# the usability or impact on systems and may be used, distributed, and
# modified in any way provided the parties agree and acknowledge the 
# Microsoft or Microsoft Partners have neither accountabilty or 
# responsibility for results produced by use of this script.
#
# Microsoft will not provide any support through any means.
# ------------- DISCLAIMER -------------------------------------------------
#
# ***************************************************************************
<#
.DESCRIPTION
   Prepare a Windows System either running on Hyper-V or in Azure to be sysprep'd added as a Windows Virtual Desktop image.
   Script can install Office 365 from Microsoft CDN, OneDrive per machine, Teams per machine, FSLogix Agent, and Edge Chromium
   Script will configure each of these items in accordance with reference articles specified in the code below.
   Script will also perform WVD specific and Azure generic image configurations per reference articles.
#>

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$DropdownArraySyncMonths = @(
    'Not Configured', '1', '2', '6', '12'
)

$DropdownArrayEmailCacheSync = @(
    'Not Configured', '3 days', '1 week', '2 weeks', '1 month', '3 months', '6 months', '12 months', '24 months', '36 months', '60 months', 'All'
)

$DropdownArrayCalSyncMode = @(
    'Not Configured', 'Inactive', 'Primary Calendar Only', 'All Calendar Folders'
)

$WVDGoldenImagePrep = New-Object system.Windows.Forms.Form
$WVDGoldenImagePrep.ClientSize = '700,800'
$WVDGoldenImagePrep.text = "Form"
$WVDGoldenImagePrep.TopMost = $false

$Execute = New-Object system.Windows.Forms.Button
$Execute.BackColor = "#417505"
$Execute.text = "Execute"
$Execute.width = 655
$Execute.height = 60
$Execute.location = New-Object System.Drawing.Point(20, 610)
$Execute.Font = 'Microsoft Sans Serif,18,style=Bold'
$Execute.ForeColor = "#ffffff"
$Execute.Add_Click({
    [string]$AADTenantID = $AADTenantID.Text
    [boolean]$Office365Install = $InstallOffice365.Checked
    $EmailCacheTime = $EmailCacheMonths.SelectedItem
    $CalendarSync = $CalendarSyncMode.SelectedItem
    $CalendarSyncMonths = $CalSyncTime.SelectedItem
    [boolean]$OneDriveInstall = $InstallOneDrive.Checked
    [boolean]$FSLogixInstall = $InstallFSLogix.Checked
    [string]$FSLogixVHDPath = $VHDPath.Text
    [boolean]$TeamsInstall = $InstallTeams.Checked
    [boolean]$EdgeInstall = $InstallEdge.Checked
    [boolean]$WindowsUpdateDisable = $DisableWU.Checked
    [boolean]$CleanupImage = $RunCleanMgr.Checked

    $args = "-Office365Install $Office365Install -OneDriveInstall $OneDriveInstall -FSLogixInstall $FSLogixInstall -TeamsInstall $TeamsInstall -EdgeInstall $EdgeInstall -WindowsUpdateDisable $WindowsUpdateDisable -CleanupImage $CleanupImage"
    If ($AADTenantID -ne '') { $args = "$args -AADTenantID $AADTenantID" }
    If ($FSLogixVHDPath -ne '') { $args = "$args -FSLogixVHDPath $FSLogixVHDPath" }

    $command = "$PSScriptRoot\Prepare-WVDImage.ps1"
    $WVDGoldenImagePrep.Close()
    & $command $args
})

$ScriptTitle = New-Object system.Windows.Forms.Label
$ScriptTitle.text = "WVD Golden VHD Prep Script"
$ScriptTitle.AutoSize = $true
$ScriptTitle.width = 25
$ScriptTitle.height = 10
$ScriptTitle.location = New-Object System.Drawing.Point(63, 47)
$ScriptTitle.Font = 'Microsoft Sans Serif,30,style=Bold'

$InstallOffice365 = New-Object system.Windows.Forms.CheckBox
$InstallOffice365.text = "Install Office 365 ProPlus"
$InstallOffice365.AutoSize = $false
$InstallOffice365.width = 173
$InstallOffice365.height = 30
$InstallOffice365.location = New-Object System.Drawing.Point(48, 142)
$InstallOffice365.Font = 'Microsoft Sans Serif,14'

$InstallOffice365.Add_CheckStateChanged({
    $EmailCacheMonths.Enabled = $InstallOffice365.Checked
    $CalendarSyncMode.Enabled = $InstallOffice365.Checked
    $CalSyncTime.Enabled = $InstallOffice365.Checked
})

$labelEmailCache = New-Object system.Windows.Forms.Label
$labelEmailCache.text = "Cache email for:"
$labelEmailCache.AutoSize = $true
$labelEmailCache.width = 25
$labelEmailCache.height = 10
$labelEmailCache.location = New-Object System.Drawing.Point(64, 170)
$labelEmailCache.Font = 'Microsoft Sans Serif,12'

$EmailCacheMonths = New-Object system.Windows.Forms.ComboBox
$EmailCacheMonths.text = "1 month"
$EmailCacheMonths.width = 120
$EmailCacheMonths.height = 29
$EmailCacheMonths.location = New-Object System.Drawing.Point(64, 205)
$EmailCacheMonths.Font = 'Microsoft Sans Serif,12'
$EmailCacheMonths.Enabled=$false

$labelCalSyncType = New-Object system.Windows.Forms.Label
$labelCalSyncType.text = "Cal Sync Type"
$labelCalSyncType.AutoSize = $true
$labelCalSyncType.width = 25
$labelCalSyncType.height = 10
$labelCalSyncType.location = New-Object System.Drawing.Point(203, 170)
$labelCalSyncType.Font = 'Microsoft Sans Serif,12'

$CalendarSyncMode = New-Object system.Windows.Forms.ComboBox
$CalendarSyncMode.text = "Primary Calendar Only"
$CalendarSyncMode.width = 180
$CalendarSyncMode.height = 29
$CalendarSyncMode.location = New-Object System.Drawing.Point(203, 205)
$CalendarSyncMode.Font = 'Microsoft Sans Serif,12'
$CalendarSyncMode.Enabled=$false

$labelCalSyncTime = New-Object system.Windows.Forms.Label
$labelCalSyncTime.text = "Cal Sync Months"
$labelCalSyncTime.AutoSize = $true
$labelCalSyncTime.width = 25
$labelCalSyncTime.height = 10
$labelCalSyncTime.location = New-Object System.Drawing.Point(410, 170)
$labelCalSyncTime.Font = 'Microsoft Sans Serif,12'

$CalSyncTime = New-Object system.Windows.Forms.ComboBox
$CalSyncTime.text = "1"
$CalSyncTime.width = 120
$CalSyncTime.height = 29
$CalSyncTime.location = New-Object System.Drawing.Point(410, 205)
$CalSyncTime.Font = 'Microsoft Sans Serif,12'
$CalSyncTime.Enabled=$false

$InstallFSLogix = New-Object system.Windows.Forms.CheckBox
$InstallFSLogix.text = "Install FSLogix Agent"
$InstallFSLogix.AutoSize = $false
$InstallFSLogix.width = 250
$InstallFSLogix.height = 30
$InstallFSLogix.location = New-Object System.Drawing.Point(48, 250)
$InstallFSLogix.Font = 'Microsoft Sans Serif,14'

$InstallFSLogix.Add_CheckStateChanged({
    $VHDPath.Enabled = $InstallFSLogix.Checked
})

$LabelVHDLocation = New-Object system.Windows.Forms.Label
$LabelVHDLocation.text = "FSLogix VHD Location"
$LabelVHDLocation.AutoSize = $true
$LabelVHDLocation.width = 25
$LabelVHDLocation.height = 20
$LabelVHDLocation.location = New-Object System.Drawing.Point(64, 295)
$LabelVHDLocation.Font = 'Microsoft Sans Serif,12'

$VHDPath = New-Object system.Windows.Forms.TextBox
$VHDPath.multiline = $false
$VHDPath.text = "\\Server\ShareName"
$VHDPath.width = 390
$VHDPath.height = 20
$VHDPath.location = New-Object System.Drawing.Point(270, 295)
$VHDPath.Font = 'Microsoft Sans Serif,12'
$VHDPath.Enabled=$false

$InstallOneDrive = New-Object system.Windows.Forms.CheckBox
$InstallOneDrive.text = "Install OneDrive per Machine "
$InstallOneDrive.AutoSize = $false
$InstallOneDrive.width = 400
$InstallOneDrive.height = 30
$InstallOneDrive.location = New-Object System.Drawing.Point(48, 340)
$InstallOneDrive.Font = 'Microsoft Sans Serif,14'

$InstallOneDrive.Add_CheckStateChanged({
    $AADTenantID.Enabled = $InstallOneDrive.Checked
})

$LabelAADTenant = New-Object system.Windows.Forms.Label
$LabelAADTenant.text = "AAD Tenant ID "
$LabelAADTenant.AutoSize = $true
$LabelAADTenant.width = 25
$LabelAADTenant.height = 20
$LabelAADTenant.location = New-Object System.Drawing.Point(64, 385)
$LabelAADTenant.Font = 'Microsoft Sans Serif,12'

$AADTenantID = New-Object system.Windows.Forms.TextBox
$AADTenantID.multiline = $false
$AADTenantID.text = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXX"
$AADTenantID.width = 409
$AADTenantID.height = 20
$AADTenantID.location = New-Object System.Drawing.Point(251, 385)
$AADTenantID.Font = 'Microsoft Sans Serif,12'
$AADTenantID.Enabled=$false

$InstallTeams = New-Object system.Windows.Forms.CheckBox
$InstallTeams.text = "Install Microsoft Teams per Machine"
$InstallTeams.AutoSize = $false
$InstallTeams.width = 400
$InstallTeams.height = 30
$InstallTeams.location = New-Object System.Drawing.Point(48, 433)
$InstallTeams.Font = 'Microsoft Sans Serif,14'

$InstallEdge = New-Object system.Windows.Forms.CheckBox
$InstallEdge.text = "Install Microsoft Edge Chromium v80+"
$InstallEdge.AutoSize = $false
$InstallEdge.width = 400
$InstallEdge.height = 30
$InstallEdge.location = New-Object System.Drawing.Point(48, 480)
$InstallEdge.Font = 'Microsoft Sans Serif,14'

$DisableWU = New-Object system.Windows.Forms.CheckBox
$DisableWU.text = "Disable Windows Update"
$DisableWU.AutoSize = $false
$DisableWU.width = 400
$DisableWU.height = 30
$DisableWU.location = New-Object System.Drawing.Point(48, 523)
$DisableWU.Font = 'Microsoft Sans Serif,14'

$RunCleanMgr = New-Object system.Windows.Forms.CheckBox
$RunCleanMgr.text = "Run System Clean Up (CleanMgr.exe)"
$RunCleanMgr.AutoSize = $false
$RunCleanMgr.width = 400
$RunCleanMgr.height = 30
$RunCleanMgr.location = New-Object System.Drawing.Point(48, 571)
$RunCleanMgr.Font = 'Microsoft Sans Serif,14'

ForEach ($Item in $DropdownArraySyncMonths) {
    [void] $CalSyncTime.Items.Add($Item)
}

ForEach ($Item in $DropdownArrayEmailCacheSync) {
    [void] $EmailCacheMonths.Items.Add($Item)
}

ForEach ($Item in $DropdownArrayCalSyncMode) {
    [void] $CalendarSyncMode.Items.Add($Item)
}

$WVDGoldenImagePrep.controls.AddRange(@($Execute, $ScriptTitle, $CalendarSyncMode, $EmailCacheMonths, $CalSyncTime, $VHDPath, $AADTenantID, $InstallOffice365, $InstallFSLogix, $InstallOneDrive, $DisableWU, $InstallTeams, $InstallEdge, $RunCleanMgr, $LabelVHDLocation, $LabelAADTenant, $labelEmailCache, $labelCalSyncType, $labelCalSyncTime))

$WVDGoldenImagePrep.AcceptButton = $Execute

$WVDGoldenImagePrep.ShowDialog()
