$WindowsVersion = "2004"
$BuildDir = "c:\BuildDir"
New-Item -Path "$BuildDir" -ItemType Directory -Force -ErrorAction SilentlyContinue
$PrepWVDImageURL = "https://github.com/shawntmeyer/WVD/archive/master.zip"
$PrepareWVDImageZip= "$BuildDir\WVD-Master.zip"
Invoke-WebRequest -Uri $PrepWVDImageURL -outfile $PrepareWVDImageZip -UseBasicParsing
Expand-Archive -Path $PrepareWVDImageZip -DestinationPath $BuildDir
$ScriptPath = "$BuildDir\WVD-Master\Image-Build\Customizations"
Set-Location -Path $ScriptPath
.\Prepare-WVDImage.ps1 -RemoveApps $False
Remove-Item -Path $BuildDir -Recurse -Force -ErrorAction SilentlyContinue

<##
    OOBE supports running a custom script after setup completes named C:\Windows\Setup\Scripts\SetupComplete.cmd (see https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup).
    However, Azure's provisioning process uses this script (overwriting if necessary) to bootstrap its own
    OOBE process. Luckily, Azure's OOBE process leaves a hook for us at the end of its process by running the script
    C:\Windows\OEM\SetupComplete2.cmd, if present.
##>
$OEMDir = "$env:SystemRoot\OEM"
If (!(Test-Path $OEMDir)) {
    $null = New-Item -Name $OEMDir -ItemType Directory
}
#Download Virtual Desktop Optimization Tool from the Virtual Desktop Team GitHub Repo
$WVDOptimizeURL = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/master.zip'
$WVDOptimizeZIP = "$OEMDir\Windows_10_VDI_Optimize-master.zip"
Invoke-WebRequest -Uri $WVDOptimizeURL -OutFile $WVDOptimizeZIP -UseBasicParsing
Expand-Archive -Path $WVDOptimizeZIP -DestinationPath $OEMDir -force
Remove-Item -Path $WVDOptimizeZIP -Force -ErrorAction SilentlyContinue
$ScriptPath = "$OEMDir\Virtual-Desktop-Optimization-Tool-master"
# Update the script configuration to leave the windows calculator enabled.
$AppxPackagesConfigFileFullName = "$scriptPath\$WindowsVersion\ConfigurationFiles\AppxPackages.json"

$AppxPackagesObj = Get-Content "$AppxPackagesConfigFileFullName" -Raw | ConvertFrom-Json
ForEach ($Element in $AppxPackagesObj) {
    If ($Element.AppxPackage -eq 'Microsoft.WindowsCalculator') {
        $Element.VDIState = 'Enabled'
    }
}
$AppxPackagesObj | ConvertTo-Json -depth 32 | Set-Content $AppxPackagesConfigFileFullName
$CMDLine = "Powershell.exe -noprofile -noninteractive -executionpolicy bypass -file `"$ScriptPath\Win10_VirtualDesktop_Optimize.ps1`" -WindowsVersion $WindowsVersion -Restart -Verbose"
$CMDLine | out-file -Encoding ascii -FilePath "$OEMDir\setupcomplete2.cmd"
