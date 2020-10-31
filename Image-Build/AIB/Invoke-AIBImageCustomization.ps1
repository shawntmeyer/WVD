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

# Create the default setup scripts directory if it doesn't exist. If setupcomplete.cmd is found in this directory by Windows Setup it is ran
# after Windows Setup finishes but before the user interface is displayed. See https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup
$SetupDir = "$env:SystemRoot\Setup\Scripts"
If (!(Test-Path $SetupDir)) {
    $null = New-Item -Name $SetupDir -ItemType Directory
}
#Download Virtual Desktop Optimization Tool from the Virtual Desktop Team GitHub Repo
$WVDOptimizeURL = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/master.zip'
$WVDOptimizeZIP = "$SetupDir\Windows_10_VDI_Optimize-master.zip"
Invoke-WebRequest -Uri $WVDOptimizeURL -OutFile $WVDOptimizeZIP -UseBasicParsing
Expand-Archive -Path $WVDOptimizeZIP -DestinationPath $SetupDir -force
Remove-Item -Path $WVDOptimizeZIP -Force -ErrorAction SilentlyContinue
$ScriptPath = "$SetupDir\Virtual-Desktop-Optimization-Tool-master"
# Update the script configuration to leave the windows calculator enabled.
$AppxPackagesConfigFileFullName = "$scriptPath\$WindowsVersion\ConfigurationFiles\AppxPackages.json"

$AppxPackagesObj = Get-Content "$AppxPackagesConfigFileFullName" -Raw | ConvertFrom-Json
ForEach ($Element in $AppxPackagesObj) {
    If ($Element.AppxPackage -eq 'Microsoft.WindowsCalculator') {
        $Element.VDIState = 'Enabled'
    }
}
$AppxPackagesObj | ConvertTo-Json -depth 32 | Set-Content $AppxPackagesConfigFileFullName
# Add a new setupcomplete.cmd if it is needed else just add a new line to an existing one to call the Win10_VirtualDesktop_Optimization.ps1 script during deployment.
If (!(Test-Path $SetupDir\setupcomplete.cmd)){
    New-Item -Path $SetupDir\setupcomplete.cmd -ItemType File
}
Add-Content -Path $SetupDir\setupcomplete.cmd -Value "Powershell.exe -executionpolicy bypass -file `"$ScriptPath\Win10_VirtualDesktop_Optimize.ps1`" -WindowsVersion $WindowsVersion -Restart -Verbose"