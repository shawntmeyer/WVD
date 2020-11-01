$WindowsVersion = "2004"
$BuildDir = "c:\BuildDir"
$ScriptName = $MyInvocation.MyCommand.Name
Write-Output "Running '$ScriptName'"
Write-Output "Creating '$BuildDir'"
$null = New-Item -Path "$BuildDir" -ItemType Directory -Force -ErrorAction SilentlyContinue
Write-Output "Downloading the WVD Image Prep Script from the 'http://www.github.com/shawntmeyer/wvd' repo."
$PrepWVDImageURL = "https://github.com/shawntmeyer/WVD/archive/master.zip"
$PrepareWVDImageZip= "$BuildDir\WVD-Master.zip"
Write-Output "Downloading '$PrepWVDImageURL' to '$PrepareWVDImageZip'."
Invoke-WebRequest -Uri $PrepWVDImageURL -outfile $PrepareWVDImageZip -UseBasicParsing
Expand-Archive -Path $PrepareWVDImageZip -DestinationPath $BuildDir
$ScriptPath = "$BuildDir\WVD-Master\Image-Build\Customizations"
Set-Location -Path $ScriptPath
Write-Output "Running Prepare-WVDImage.ps1"
.\Prepare-WVDImage.ps1 -RemoveApps $False
Write-Output "Finished 'Prepare-WVDImage.ps1'."
# Download Virtual Desktop Optimization Tool from the Virtual Desktop Team GitHub Repo
$WVDOptimizeURL = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/master.zip'
$WVDOptimizeZIP = "$OEMDir\Windows_10_VDI_Optimize-master.zip"
Write-Output "Downloading the Virtual Desktop Team's Virtual Desktop Optimization Tool from GitHub."
Write-Output "Downloading '$WVDOptimizeURL' to '$WVDOptimizeZIP'."
Invoke-WebRequest -Uri $WVDOptimizeURL -OutFile $WVDOptimizeZIP -UseBasicParsing
Expand-Archive -Path $WVDOptimizeZIP -DestinationPath $OEMDir -force
Remove-Item -Path $WVDOptimizeZIP -Force -ErrorAction SilentlyContinue
$ScriptPath = "$BuildDir\Virtual-Desktop-Optimization-Tool-master"
# Update the optimization script's configuration to keep the windows calculator app.
Write-Output "Staging the Virtual Desktop Optimization Tool at '$ScriptPath'."
Write-Output "Changing AppPackages.json file to leave WindowsCalculator app."
$AppxPackagesConfigFileFullName = "$scriptPath\$WindowsVersion\ConfigurationFiles\AppxPackages.json"
$AppxPackagesObj = Get-Content "$AppxPackagesConfigFileFullName" -Raw | ConvertFrom-Json
ForEach ($Element in $AppxPackagesObj) {
    If ($Element.AppxPackage -eq 'Microsoft.WindowsCalculator') {
        $Element.VDIState = 'Enabled'
    }
}
$AppxPackagesObj | ConvertTo-Json -depth 32 | Set-Content $AppxPackagesConfigFileFullName
$WVDOptimizeScriptName = (Get-ChildItem $ScriptPath | Where-Object {$_.Name -like '*optimize*.ps1'}).Name
Write-Output "Adding a -NoRestart parameter to the Set-NetAdapterAdvancedProperty line in '$WVDOptimizeScriptName' to prevent the network adapter restart from killing AIB."
$WVDOptScriptFile = Join-Path -Path $ScriptPath -ChildPath $WVDOptimizeScriptName
(Get-Content $WVDOptScriptFile) | ForEach-Object { if (($_ -like 'Set-NetAdapterAdvancedProperty*') -and ($_ -notlike '*-NoRestart*')) { $_ -replace "$_", "$_ -NoRestart" } else { $_ } } | Set-Content $WVDOptScriptFile
Set-Location $ScriptPath
Write-Output "Now calling '$WVDOptimizeScriptName'."
.\$WVDOptimizeScriptName -WindowsVersion $WindowsVersion -Verbose
Write-Output 'Cleaning up from customization scripts.'
Set-Location "$env:SystemDrive"
Write-Output "Removing '$BuildDir'."
Remove-Item -Path $BuildDir\* -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $BuildDir -Recurse -Force -ErrorAction SilentlyContinue


<##

Write-Output "Creating '$OEMDir\setupcomplete2.cmd' and adding command to run $ScriptPath\Win10_VirtualDesktop_Optimize.ps1 post Windows Setup."
$CMDLine = "Powershell.exe -noprofile -noninteractive -executionpolicy bypass -file `"$ScriptPath\Win10_VirtualDesktop_Optimize.ps1`" -WindowsVersion $WindowsVersion -Verbose > %windir%\oem\win10_virtualdesktop_optimize.log"
$CMDLine | out-file -Encoding ascii -FilePath "$OEMDir\setupcomplete2.cmd"
# Create the following tag file to force a machine restart from c:\windows\oem\setupcomplete.cmd
Write-Output "Adding the 'RestartMachine.tag' file to the '$OEMDir'."
$Null = New-Item -Path "$OEMDir" -Name "RestartMachine.tag" -ItemType File
##>