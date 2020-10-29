$BuildDir = "c:\BuildDir"
New-Item -Path "$BuildDir" -ItemType Directory -Force -ErrorAction SilentlyContinue
$PrepWVDImageURL = "https://github.com/shawntmeyer/WVD/archive/master.zip"
$PrepareWVDImageZip= "$BuildDir\WVD-Master.zip"
Invoke-WebRequest -Uri $PrepWVDImageURL -outfile $PrepareWVDImageZip -UseBasicParsing
Expand-Archive -Path $PrepareWVDImageZip -DestinationPath $BuildDir
$ScriptPath = "$BuildDir\WVD-Master\Image-Build\Customizations"
Set-Location -Path $ScriptPath
.\Prepare-WVDImage.ps1 -RemoveApps $False
$WVDOptimizeURL = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/master.zip'
$WVDOptimizeZIP = "$BuildDir\Windows_10_VDI_Optimize-master.zip"
Invoke-WebRequest -Uri $WVDOptimizeURL -OutFile $WVDOptimizeZIP -UseBasicParsing
Expand-Archive -Path $WVDOptimizeZIP -DestinationPath $BuildDir -force
$ScriptPath = "$BuildDir\Virtual-Desktop-Optimization-Tool-master"
Set-Location -Path $ScriptPath
.\Win10_VirtualDesktop_Optimize.ps1 -WindowsVersion 2004 -Verbose
Set-Location -Path c:\
Remove-Item -Path $BuildDir -Recurse -Force -ErrorAction SilentlyContinue