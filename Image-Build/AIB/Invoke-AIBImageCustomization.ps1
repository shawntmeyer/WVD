[CmdletBinding()]
param(
    [Parameter()]
    [string] $storageAccount = '<StorageAccount>',
    [Parameter()]
    [string] $container = '<Container>',
    [Parameter()]
    [string] $sasToken = '<SAS>',
    [Parameter()]
    [string] $buildDir = "<BuildDir>"
)

#region Initialization
[string]$Script:Path = $MyInvocation.MyCommand.Definition
[string]$Script:Name = [IO.Path]::GetFileNameWithoutExtension($Script:Path)

Write-Output "Running '$Script:Name'"

#region First Script

$scriptName = "Prepare-WVDImage"
$scriptFile = "$scriptName" + ".ps1"
$zipFile = "$scriptName" + ".zip"
[string]$scriptUrl = "https://" + "$storageAccount" + ".blob.core.windows.net/" + "$container" + "/" + "$zipFile" + "$sasToken"
$downloadedZip= "$buildDir\$scriptName.zip"
Write-Output "Downloading '$scriptUrl' to '$downloadedZip'."
Invoke-WebRequest -Uri $scriptUrl -outfile $downloadedZip -UseBasicParsing
Expand-Archive -Path $downloadedZip -DestinationPath "$buildDir\$scriptName" -Force
Remove-Item -Path $downloadedZip -Force -ErrorAction SilentlyContinue
$ScriptPath = (Get-ChildItem -Path $buildDir -Recurse -Filter "$scriptFile").FullName
Write-Output "Now calling '$scriptFile'"
& "$ScriptPath"
Write-Output "Finished '$scriptFile'."

#endregion

#region Additional Scripts

$scriptName = "Install-PowershellCore"
$scriptFile = "$scriptName" + ".ps1"
$zipFile = "$scriptName" + ".zip"
[string]$scriptUrl = "https://" + "$storageAccount" + ".blob.core.windows.net/" + "$container" + "/" + "$zipFile" + "$sasToken"
$downloadedZip= "$buildDir\$scriptName.zip"
Write-Output "Downloading '$scriptUrl' to '$downloadedZip'."
Invoke-WebRequest -Uri $scriptUrl -outfile $downloadedZip -UseBasicParsing
Expand-Archive -Path $downloadedZip -DestinationPath $buildDir
Remove-Item -Path $downloadedZip -Force -ErrorAction SilentlyContinue
$ScriptPath = (Get-ChildItem -Path $buildDir -Recurse -Filter "$scriptFile").FullName
Write-Output "Now calling '$scriptFile'"
& "$ScriptPath"
Write-Output "Finished '$scriptFile'."

<##-- Additional Scripts Here
$scriptName = "Install-<softwareName>"
$scriptFile = "$scriptName" + ".ps1"
$zipFile = "$scriptName" + ".zip"
[string]$scriptUrl = "https://" + "$storageAccount" + ".blob.core.windows.net/" + "$container" + "/" + "$zipFile" + "$sasToken"
$downloadedZip= "$buildDir\$scriptName.zip"
Write-Output "Downloading '$scriptUrl' to '$downloadedZip'."
Invoke-WebRequest -Uri $scriptUrl -outfile $downloadedZip -UseBasicParsing
Expand-Archive -Path $downloadedZip -DestinationPath $buildDir
Remove-Item -Path $downloadedZip -Force -ErrorAction SilentlyContinue
$ScriptPath = (Get-ChildItem -Path $buildDir -Recurse -Filter "$scriptFile").FullName
Write-Output "Now calling '$scriptFile'"
& "$ScriptPath"
Write-Output "Finished '$scriptFile'."
--##>

#endregion

$DeprovisioningScript = "$env:SystemDrive\DeprovisioningScript.ps1"
If (Test-Path $DeprovisioningScript) {
    Write-Output "Adding the /mode:VM switch to the sysprep command line in the deprovisioning script."
    (Get-Content $DeprovisioningScript) | ForEach-Object { if ($_ -like '*System32\Sysprep\Sysprep.exe*') { "$_ /mode:vm" } else { $_ } } | Set-Content $DeprovisioningScript
}
Write-Output "Finished '$Script:Name'."


