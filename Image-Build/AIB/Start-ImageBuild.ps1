# ***************************************************************************
#
# Purpose: Start Azure Image Builder Process
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
   Create all the necessary resources to support Azure Image Builder and begin building a single image.
   Based on https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop
   # added a bunch of individual article section references.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false,
    HelpMessage = 'Determine if Resource Providers should be registered. Only needs to run once per subscription.')]
    [boolean] $registerProviders = $true,

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify SubscriptionID if you have more than one subscription.')]
    [string] $subscriptionID = "",

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify Region where resources will be created.')]
    [string] $location = 'EastUS2',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify Image Management Resource Group Name. Will contain Storage Account, Shared Image Gallery, Image Definitions, Image Versions, and Image Builder Templates')]
    [string] $imageResourceGroup = '',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the name of the storage account. Storage account names must be between 3 and 24 characters in length and may contain numbers and lowercase letters only.')]
    [string] $storageAccountName= '',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the blob container name. Container names can be between 3 and 63 characters long, start with a letter or number, and contain only lowercase letters, numbers, or the dash (-) character.')]
    [string] $containerName = '',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the name of the master customization script. Must be same directory as this script.')]
    [string] $imageMasterScript = 'Invoke-AIBImageCustomization.ps1',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the file name of the Image Builder Template.')]
    [string] $imageTemplateFilePath = 'AzureImageBuilderTemplate.json',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the name of the Image Template. Only alphanumeric characters (0-9, a-z, and A-Z) and the hyphen (-) are supported.')]
    [string] $imageTemplateName = 'Windows10MS',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Name of custom Image Builder RBAC role.')]
    [string] $imageRoleDefName = 'Azure Image Builder Custom Role',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the name of the Azure Image Builder User Assigned Identity. Only alphanumeric characters (0-9, a-z, and A-Z) and the hyphen (-) are supported.')]
    [string] $identityName = 'AIBUserIdentity',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the name of the Shared Image Gallery. Allowed characters for Gallery name are uppercase or lowercase letters, digits, dots, and periods.')]
    [string] $sigGalleryName = '',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the Image Definition Name. Allowed characters for Image Definition Name are uppercase or lowercase letters, digits, dots, and periods.')]
    [string] $imageDefName = 'Windows10MS',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the image Publisher. Allowed characters for Image Publisher are uppercase or lowercase letters, digits, periods, and dashes.')]
    [string] $imagePublisher = 'NRC',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the name of the Shared Image Gallery. Allowed characters for Gallery name are uppercase or lowercase letters, digits, periods, and dashes.')]
    [string] $imageOffer = 'Windows-10',

    [Parameter(Mandatory=$false,
    HelpMessage = 'Specify the name of the Shared Image Gallery. Allowed characters for Gallery name are uppercase or lowercase letters, digits, periods, and dashes.')]
    [string] $imageSku = 'EVD'
)
#region Variables

# distribution properties object name (runOutput), i.e. this gives you the properties of the managed image on completion
# Recommend that you keep it same as image template name.
$runOutputName = $imageTemplateName
# Custom Role Template
$aibCustomRoleTemplate = "aibCustomRoleTemplate.json"
# Paths in repo
$customizationsFolder = "$PSScriptRoot\..\Customizations"
$functionsFolder = "$PSScriptRoot\Functions"
# Build Path on image
$buildDir = "c:\BuildDir"
#endregion

#region dot Source supporting functions
Write-Output "*** Start: Loading Supporting Functions ***"
$functions = (Get-ChildItem -Path $functionsFolder -file).FullName

ForEach ($file in $functions) {
    . "$file"
}
Write-Output "*** Complete: Loading Supporting Functions ***"
#endregion

#region Azure Logon
Write-Output "*** Start: Azure Logon Context ***"
# Get Context
$currentAzContext = Get-AzContext
If (!$currentAzContext) {
    Write-Error "You must be logged into Azure before running this script."
    Write-Output "* You can logon to Azure in multiple ways. One Simple way is to use the 'Connect-AzAccount' cmdlet"
    Write-Output "and enter credentials in the new browser window that pops up."
    Write-Output "* Another way is to set a variable `"$credential = get-credential`" and enter your credentials at the prompt."
    Write-Output "Then use `"Login-AzAccount -credential $credential`" to overcome issues with multiple accounts."
    Exit
}
# your subscription, this will get your current subscription
If ($subscriptionID -eq "") {
    $subscriptionID=$currentAzContext.Subscription.Id
}
Else {
    Set-AzContext -Subscription $subscriptionID
}
Write-Output "*** Complete: Azure Logon Context ***"
#endregion

#region Install/Import Required Modules
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop#set-up-environment-and-variables

Write-Output "*** Start: Installing and Importing Required Powershell Modules ***"

Write-Output "Checking to see if minimum version of 'Az' module is installed."
If (!(Get-InstalledModule -name Az -MinimumVersion 5.8.0 -ErrorAction SilentlyContinue)) {
    Write-Output "'Az' module needs to be installed or updated."
    Install-Module -Name Az -AllowClobber -Force
}
Else {
    Write-Output "Minimum version of 'Az' module is installed."
}

Write-Output "Checking to see if 'Az.Accounts' module is installed."
If (!(Get-Module -name Az.Accounts -ErrorAction SilentlyContinue)) {
    Write-Output "'Az.Account' module not found. Importing."
    Import-Module Az.Accounts -Force
}
Else {
    Write-Output "'Az.Accounts' module is installed."
}

Write-Output "Verifying that the 'Az.ManagedServiceIdentity' powershell module is installed."
If (!(Get-Module -name Az.ManagedServiceIdentity -ErrorAction SilentlyContinue)) {
    Write-Output "'Az.ManagedServiceIdentity' module not found. Installing and Importing."
    Install-Module -Name Az.ManagedServiceIdentity -AllowClobber -Force
    Import-Module -Name Az.ManagedServiceIdentity -Force
}
Else {
    Write-Output "'Az.ManagedServiceIdentity' module is already installed."
}

Write-Output "Verifying that 'AZ.ImageBuilder' powershell module is installed."
If (!(Get-Module -Name Az.ImageBuilder -ErrorAction SilentlyContinue)) {
    Write-Output "'Az.ImageBuilder' module not found. Installing and Importing."
    Install-Module Az.ImageBuilder -Force -AllowClobber
    Import-Module Az.ImageBuilder -Force
}
Else {
    Write-Output "'Az.ImageBuilder' module is already installed."
}

Write-Output "*** Complete: Installing and Importing Required Powershell Modules ***"
#endregion

#region Provider Registration
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop#prerequisites
If ($registerProviders) {
    Get-AzResourceProvider -ProviderNamespace Microsoft.Compute, Microsoft.KeyVault, Microsoft.Storage, Microsoft.VirtualMachineImages, Microsoft.Network |
    Where-Object RegistrationState -ne Registered |
        Register-AzResourceProvider
}
#endregion

#region create resource group
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop#set-up-environment-and-variables
Write-Output "*** Start: Resource Group ***"
Write-Output "Checking for existing Resource Group."
If (-not (Get-AzResourceGroup -Name $imageResourceGroup -ErrorAction SilentlyContinue)) {
    Write-Output "Creating '$imageResourceGroup' resource group."
    New-AzResourceGroup -Name $imageResourceGroup -Location $location
}
Else {
    Write-Output "Resource Group '$imageResourceGroup' already exists."
}
Write-Output "*** Complete: Resource Group ***"
#endregion

#region Create User Assigned Identity
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop#permissions-user-identity-and-role

Write-Output "*** Start: User Assigned Identity ***"
Write-Output "Checking for User Assigned Identity '$identityName' in '$imageResourceGroup' resource group."
$userIdentity = Get-AzUserAssignedIdentity | Where-Object { $_.Name -eq $identityName -and $_.ResourceGroupName -eq $imageResourceGroup }

If (!($userIdentity)) {
    # create New identity
    Write-Output "Creating a new user assigned identity: '$identityName'."
    New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName -ErrorAction Stop
    Write-Output "Waiting for user assigned identity to be available via API."
    do {
        Start-Sleep -seconds 1
    } until (Get-AzUserAssignedIdentity | Where-Object { $_.Name -eq $identityName -and $_.ResourceGroupName -eq $imageResourceGroup })
    Write-Output "User Assigned Identity now available via API."
    $userIdentity = Get-AzUserAssignedIdentity | Where-Object { $_.Name -eq $identityName -and $_.ResourceGroupName -eq $imageResourceGroup }
}
Else {
    Write-Output "Found User Assigned Identity: '$identityName'."
}

$identityNameResourceId = $userIdentity.Id
$identityNamePrincipalId = $userIdentity.PrincipalId
Write-Output "*** Complete: User Assigned Identity ***"

#endregion

#region Custom Role Assignment
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop#permissions-user-identity-and-role
# Role Definition Source found @ "https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
Write-Output "*** Start: AIB Custom Role Assignment ***"
Write-Output "Checking for custom Azure Role definition named '$imageRoleDefName'."
If (!(Get-AzRoleDefinition -Name $imageRoleDefName -ErrorAction SilentlyContinue)) {
    Write-Output "Custom Azure Role Definition not found. Now creating."
    # copying template to temp file for text replacement and submission.
    $tempFile = "$env:Temp\aibroletemplate.json"
    Copy-Item -Path $aibCustomRoleTemplate -Destination $tempFile -Force
    ((Get-Content -path $tempFile -Raw) -replace '<SubscriptionID>',$subscriptionID) | Set-Content -Path $tempFile
    ((Get-Content -path $tempFile -Raw) -replace '<RgName>', $imageResourceGroup) | Set-Content -Path $tempFile
    ((Get-Content -path $tempFile -Raw) -replace 'Azure Image Builder Service Image Creation Role', $imageRoleDefName) | Set-Content -Path $tempFile

    # create role definition
    New-AzRoleDefinition -InputFile "$tempFile" -ErrorAction Stop
    Write-Output "Waiting for custom role definition to be available for assignment via API."
    do {
        Start-Sleep -seconds 1
    } until (Get-AzRoleDefinition -Name $imageRoleDefName -ErrorAction SilentlyContinue)
    Write-Output "'$imageRoleDefName' role definition available via API."
    Remove-Item -Path $tempFile -Force
}
Else {
    Write-Output "Custom Azure Role Definition found."
}

Write-Output "Checking for custom role assignment for '$identityName'."
If (!(Get-AzRoleAssignment -RoleDefinitionName $imageRoleDefName -objectID $identityNamePrincipalId -ErrorAction SilentlyContinue)) {
    # grant role definition to image builder service principal
    Write-Output 'Role Assignment not found. Creating a new one.'
    Write-Output "Assigning role to '$identityName'."
    Try {
        New-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $imageRoleDefName -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup"
    }
    Catch {
        Write-Output "Pausing 5 seconds to work around timing issue with Role Assignments."
        Start-Sleep -seconds 5
        New-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $imageRoleDefName -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup" -ErrorAction Stop
    }
}
Else {
    Write-Output "'$imageRoleDefName' Assignment Found."
}
Write-Output "*** Complete: AIB Custom Role Assignment ***"

#endregion

#region Create Azure Storage Account and container for storing the customization scripts blobs.
# Not documented on AIB, this used to internalize all Content that is used in image.
Write-Output "*** Start: Image Customization Scripts Storage Account ***"
$storageAccountName = Get-AzStorageAccount -ResourceGroupName $imageResourceGroup -Name $storageAccountName -ErrorAction SilentlyContinue
If (!($storageAccountName)) {
    New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $imageResourceGroup -Location (Get-AzResourceGroup -Name $imageResourceGroup).location -sku Standard_LRS -EnableHttpsTrafficOnly $true -MinimumTlsVersion TLS1_2
    $storageAccountName = Get-AzStorageAccount -ResourceGroupName $imageResourceGroup -Name $storageAccountName -ErrorAction SilentlyContinue
}

$storageAccountNameId = $storageAccountName.Id
$storageAccountNameCtx = $storageAccountName.Context

If (!(Get-AzStorageContainer -Name $containerName -Context $storageAccountNameCtx -ErrorAction SilentlyContinue)) {
    New-AzStorageContainer -Name $containerName -Context $storageAccountNameCtx -Permission blob
}

Write-Output "Checking for 'Storage Blob Data Reader' Role Assignment for '$identityName'."
If (!(Get-AzRoleAssignment -RoleDefinitionName 'Storage Blob Data Reader' -ObjectId $identityNamePrincipalId -Scope $storageAccountNameId -ErrorAction SilentlyContinue)) {
    #grant role definition to image builder service principal
    Write-Output 'Role assignment not found. Creating a new one.'
    New-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName 'Storage Blob Data Reader' -Scope $storageAccountNameId -ErrorAction Stop
}
Else {
    Write-Output "'Storage Blob Data Reader' Role Assignment found."
}
Write-Output "*** Complete: Image Customization Scripts Storage Account ***"

#endregion

#region Update Image Customization Wrapper Script and upload to storage account

# this is a custom master script. The idea is to access this script from the image template as a script customizer but then this script calls
# all other scripts and installers. To call other scripts via Uri you have to supply a SAS token since it no longer supports the native Storage
# Blob Data Reader Role for access.

Write-Output "*** Start: Image Customization Wrapper Script ***"
$tempFile = "$env:Temp\imageMasterScript.ps1"
# Find Image Master Script in script directory.
$script = Get-ChildItem -Path $PSScriptRoot -file -filter "$imageMasterScript" -Recurse
Copy-Item -Path $($script.FullName) -Destination $tempFile -Force
Set-ContainerSASInFile -StorageAccount $storageAccountName -BlobContainer $containerName -FilePath $tempFile
((Get-Content -path $tempFile -Raw) -replace '<StorageAccount>', $storageAccountName) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<Container>', $containerName) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<BuildDir>', $buildDir) | Set-Content -Path $tempFile
Set-AzStorageBlobContent -File "$tempFile" -Container $containerName -Blob $imageMasterScript -Context $storageAccountNameCtx -Force
Remove-Item -Path $tempFile -Force
Write-Output "*** Complete: Image Customization Wrapper Script ***"

#endregion

#region Upload other Customization Scripts

# Also not documented in AIB documentation. This is custom code to zip each subdirectory under the customizations directory
# and upload the zip files to the storage accounts as blobs in the specified container.

Write-Output "*** Start: Image Customization Scripts ***"
$zipDestinationFolder = "$env:Temp\ZipFiles"
If (!(Test-Path $zipDestinationFolder)) {
    $null = New-Item -Path $zipDestinationFolder -ItemType Directory -Force
}
Write-Output "Compressing subfolders under '$customizationsFolder' into zip files stored in '$zipDestinationFolder'."
Compress-SubFolderContents -SourceFolderPath $customizationsFolder -DestinationFolderPath "$zipDestinationFolder"

$InputObject = @{
    ResourceGroupName  = (Get-AzResource -Name $storageAccountName -ResourceType 'Microsoft.Storage/storageAccounts').ResourceGroupName
    StorageAccountName = $storageAccountName
    contentDirectories = $zipDestinationFolder
    targetContainer    = $containerName
}
Add-ContentToBlobContainer @InputObject
Remove-Item -Path $zipDestinationFolder -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "*** Complete: Image Customization Scripts ***"

#endregion

#region Create the Shared Image Gallery and Image Definition
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop#create-the-shared-image-gallery

Write-Output "*** Start: Shared Image Gallery ***"
# create gallery
Write-Output "Checking for Shared Image Gallery named '$sigGalleryName' in '$imageResourceGroup' resource group."
If (!(Get-AzGallery -Name $sigGalleryName -ResourceGroupName $imageResourceGroup -ErrorAction SilentlyContinue)) {
    Write-Output 'Shared Image Gallery not found. Now creating the Shared Image Gallery.'
    New-AzGallery -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Location $location -ErrorAction Stop
}
Else {
    Write-Output 'Shared Image Gallery found.'
}
# create gallery definition
Write-Output "Checking for Image Definition named '$imageDefName' in the shared image gallery."
If (!(Get-AzGalleryImageDefinition -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Name $imageDefName -ErrorAction SilentlyContinue)) {
    Write-Output 'Image Definition not found. Now creating it.'
    New-AzGalleryImageDefinition -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Location $location -Name $imageDefName -OsState generalized -OsType Windows -Publisher $imagePublisher -Offer $imageOffer -Sku $imageSku -ErrorAction Stop
}
Else {
    write-output "Image Definition Found."
}
Write-Output "*** Complete: Shared Image Gallery ***"

#endregion

#Region Configure the Image Template
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop#configure-the-image-template
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop#download-template-and-configure
# Instead of downloading the template from GitHub, the template is available in this directory. We create a temporary file
# so we can update the variables for your environment dynamically.

Write-Output "*** Start: Azure Image Builder Template ***"
Write-Output "Updating Azure Image Builder ARM template with variables."
$tempFile = "$env:Temp\AIBImageTemplate.json"
Copy-Item -Path $imageTemplateFilePath -Destination $tempFile

((Get-Content -path $tempFile -Raw) -replace '<SubscriptionID>', $subscriptionID) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<RGName>', $imageResourceGroup) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<Region>', $location) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<RunOutputName>', $runOutputName) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<StorageAccount>', $storageAccountName) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<Container>', $containerName) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<MasterScriptName>', $imageMasterScript) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<ImageDefName>', $imageDefName) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<SharedImageGalName>', $sigGalleryName) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<Region1>', $location) | Set-Content -Path $tempFile
((Get-Content -path $tempFile -Raw) -replace '<ImgBuilderId>', $identityNameResourceId) | Set-Content -Path $tempFile
# Add the second escape character '\' to the buildDir for proper JSON syntax.
$escBuildDir = $buildDir.Replace('\', '\\')
((Get-Content -path $tempFile -Raw) -replace '<BuildDir>', $escBuildDir) | Set-Content -Path $tempFile
Write-Output "*** Complete: Azure Image Builder Template ***"

#endregion

#Region Submit the template to AIB
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop#submit-the-template
# We must first delete the template because you can not update an existing template. This allows us to dynamically update
# our template as we manage the images going forward.

Write-Output "*** Start: AIB Template Submission to Service ***"
Write-Output "Checking for existing image builder template named '$imageTemplateName'."
If (Get-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName -ErrorAction SilentlyContinue) {
    Write-Output "Existing template found, must delete the template because they cannot be updated."
    Remove-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName -ErrorAction Stop
}
Else {
    Write-Output "Existing template not found."
}
Write-Output "Submitting Azure Image Builder template to service."
New-AzResourceGroupDeployment -ResourceGroupName $imageResourceGroup -TemplateFile $tempFile -api-version "2020-02-14" -imageTemplateName $imageTemplateName -svclocation $location -ErrorAction Stop
Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
Write-Output "*** Complete: AIB Template Submission to Service ***"
#endregion

#Region Invoke the Deployment
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-virtual-desktop#build-the-image

Write-Output "*** Start: Invoke AIB Image Build ***"
Write-Output "Pausing 5 secs to ensure that template is ready."
start-sleep 5
Write-Output "Starting Image Build"
Invoke-AzResourceAction -ResourceName $imageTemplateName -ResourceGroupName $imageResourceGroup -ResourceType Microsoft.VirtualMachineImages/imageTemplates -ApiVersion "2020-02-14" -Action Run -Force
Write-Output "*** Complete: Invoke AIB Image Build ***"

#endregion

Write-Output "----- Script Complete -----"