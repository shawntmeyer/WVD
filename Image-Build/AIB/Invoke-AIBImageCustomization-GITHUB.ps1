$WindowsVersion = "2004"
$Office365Install = $true
$BuildDir = "c:\BuildDir"
$ScriptName = $MyInvocation.MyCommand.Name

Function Update-ServiceConfigurationJSON {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [String]
        $ConfigFile,
        [Parameter(Mandatory=$true)]
        [String]
        $ServiceName,
        [Parameter(Mandatory=$true)]
        [String]
        $VDIState
    )
    Write-Output "Checking for configuration file '$Configfile'."
    If (Test-Path $ConfigFile) {
        Write-Output "Configuration File found. Updating configuration of '$ServiceName' to '$VDIState'."
        $ConfigObj = Get-Content "$ConfigFile" -Raw | ConvertFrom-Json
        $ConfigObj | ForEach-Object {If($_.Name -eq "$ServiceName"){$_.VDIState = $VDIState}}
        $ConfigObj | ConvertTo-Json -depth 32 | Set-Content $ConfigFile
    }
    else {
        Write-Warning "The configuration file not found."
    }
}

Write-Output "Running '$ScriptName'"
Write-Output "Creating '$BuildDir'"
$null = New-Item -Path "$BuildDir" -ItemType Directory -Force -ErrorAction SilentlyContinue
Write-Output "Downloading the WVD Image Prep Script from the 'http://www.github.com/shawntmeyer/wvd' repo."
$PrepWVDImageURL = "https://github.com/shawntmeyer/WVD/archive/master.zip"
$PrepareWVDImageZip= "$BuildDir\WVD-Master.zip"
Write-Output "Downloading '$PrepWVDImageURL' to '$PrepareWVDImageZip'."
Invoke-WebRequest -Uri $PrepWVDImageURL -outfile $PrepareWVDImageZip -UseBasicParsing
Expand-Archive -Path $PrepareWVDImageZip -DestinationPath $BuildDir
Remove-Item -Path $PrepareWVDImageZip -Force -ErrorAction SilentlyContinue
$ScriptPath = "$BuildDir\WVD-Master\Image-Build\Customizations"
Write-Output "Now calling 'Prepare-WVDImage.ps1'"
# & "$ScriptPath\Prepare-WVDImage.ps1" -RemoveApps $False -Office365Install $Office365Install
& "$ScriptPath\Prepare-WVDImage.ps1" -Office365Install $Office365Install
Write-Output "Finished 'Prepare-WVDImage.ps1'."

# Download Virtual Desktop Optimization Tool from the Virtual Desktop Team GitHub Repo
$WVDOptimizeURL = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/master.zip'
$WVDOptimizeZIP = "$BuildDir\Windows_10_VDI_Optimize-master.zip"
Write-Output "Downloading the Virtual Desktop Team's Virtual Desktop Optimization Tool from GitHub."
Write-Output "Downloading '$WVDOptimizeURL' to '$WVDOptimizeZIP'."
Invoke-WebRequest -Uri $WVDOptimizeURL -OutFile $WVDOptimizeZIP -UseBasicParsing
Expand-Archive -Path $WVDOptimizeZIP -DestinationPath $BuildDir -force
Remove-Item -Path $WVDOptimizeZIP -Force -ErrorAction SilentlyContinue
$ScriptPath = "$BuildDir\Virtual-Desktop-Optimization-Tool-master"
Write-Output "Staging the Virtual Desktop Optimization Tool at '$ScriptPath'."
Write-Output "Removing AppXPackages.json file to prevent appx removal. Already completed."
$AppxPackagesConfigFileFullName = "$scriptPath\$WindowsVersion\ConfigurationFiles\AppxPackages.json"
Remove-Item -Path $AppxPackagesConfigFileFullName -force
# Update Services Configuration
Write-Output "Updating Services Configuration."
$ServicesConfig = "$ScriptPath\$WindowsVersion\ConfigurationFiles\Services.json"
Write-Output "Setting the 'Store Install Service' in file to 'Default'."
Update-ServiceConfigurationJSON -ServiceName 'InstallService' -ConfigFile $ServicesConfig -VDIState "Default"
Write-Output "Setting the 'System Maintenance Service' in file to 'Default'."
Update-ServiceConfigurationJSON -ServiceName 'SysMain' -ConfigFile $ServicesConfig -VDIState "Default"
Write-Output "Setting the 'Update Orchestration Service' in file to 'Default'."
Update-ServiceConfigurationJSON -ServiceName 'UsoSvc' -ConfigFile $ServicesConfig -VDIState "Default"
Write-Output "Setting the 'Volume Shadow Copy Service' in file to 'Default'."
Update-ServiceConfigurationJSON -ServiceName 'VSS' -ConfigFile $ServicesConfig -VDIState "Default"
# DefaultUserSettings.txt update
$TextFile = "$scriptPath\$WindowsVersion\ConfigurationFiles\DefaultUserSettings.txt"
If (Test-Path $TextFile) {
    # Remove Blank Lines
    (Get-Content $TextFile) | ForEach-Object { if ($_ -ne '') { $_ } } | Set-Content $TextFile
}
# Script Updates
$WVDOptimizeScriptName = (Get-ChildItem $ScriptPath | Where-Object {$_.Name -like '*optimize*.ps1'}).Name
Write-Output "Adding the '-NoRestart' switch to the Set-NetAdapterAdvancedProperty line in '$WVDOptimizeScriptName' to prevent the network adapter restart from killing AIB."
$WVDOptimizeScriptFile = Join-Path -Path $ScriptPath -ChildPath $WVDOptimizeScriptName
(Get-Content $WVDOptimizeScriptFile) | ForEach-Object { if (($_ -like 'Set-NetAdapterAdvancedProperty*') -and ($_ -notlike '*-NoRestart*')) { $_ -replace "$_", "$_ -NoRestart" } else { $_ } } | Set-Content $WVDOptimizeScriptFile
Write-Output "Removing the possibly invasive disk cleanup routine starting at c:\"
(Get-Content $WVDOptimizeScriptFile) | ForEach-Object { if ($_ -like 'Get-ChildItem -Path c:\ -include*') { "# $_" } else { $_ } } | Set-Content $WVDOptimizeScriptFile
Write-Output "Now calling '$WVDOptimizeScriptName'."
& "$WVDOptimizeScriptFile" -WindowsVersion $WindowsVersion -Verbose
Write-Output "Completed $WVDOptimizeScriptName."

#Section Install App Y
Start-Sleep 5
Write-Output "Adding the /mode:VM switch to the sysprep command line in the deprovisioning script."
$DeprovisioningScript = "$env:SystemDrive\DeprovisioningScript.ps1"
If (Test-Path $DeprovisioningScript) {
    (Get-Content $DeprovisioningScript) | ForEach-Object { if ($_ -like '*System32\sysprep\sysprep.exe *') { $_ -replace "$_", "$_ /mode:vm" } else { $_ } } | Set-Content $DeprovisioningScript
}
Write-Output 'Cleaning up from customization scripts.'
Write-Output "Removing '$BuildDir'."
Remove-Item -Path $BuildDir\* -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $BuildDir -Recurse -Force -ErrorAction SilentlyContinue