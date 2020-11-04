#region Step 1: Setup Variables

# Import Module
If (!(Get-Module -name Az.Accounts -ErrorAction SilentlyContinue)) {
    Import-Module Az.Accounts -Force
}

# Get Context
$currentAzContext = Get-AzContext
# destination image resource group
$imageResourceGroup="RG-AzureImageBuilder"
# location (see possible locations in main docs)
$location="EastUS"
# your subscription, this will get your current subscription
$subscriptionID=$currentAzContext.Subscription.Id
# image template name
$imageTemplateName="Win10-EVD-20H2"
# distribution properties object name (runOutput), i.e. this gives you the properties of the managed image on completion
$runOutputName="Win10MS"

# create resource group
If (!(Get-AzResourceGroup -Name $imageResourceGroup -ErrorAction SilentlyContinue)) {
    Write-Output "Creating '$ImageResourceGroup' resource group."
    New-AzResourceGroup -Name $imageResourceGroup -Location $location
}
#endregion

#region Step 2: Create User Assigned Identity

# setup role def names, these need to be unique

$imageRoleDefName="Azure Image Builder Custom Role"
$IdentityName="AIBUserIdentity"

## Add AZ PS module to support AzUserAssignedIdentity
If (!(Get-Module -name Az.ManagedServiceIdentity -ErrorAction SilentlyContinue)) {
    Write-Output "Installing 'Az.ManagedServiceIdentity' powershell module."
    Install-Module -Name Az.ManagedServiceIdentity -Force
}

# Cleanup from previous runs
Write-Output "Checking for User Assigned Identity '$IdentityName' in '$imageResourceGroup' resource group."
$UserIdentity = Get-AzUserAssignedIdentity | Where-Object { $_.Name -eq $IdentityName -and $_.ResourceGroupName -eq $imageResourceGroup }
If (!($UserIdentity)) {
    # create New identity
    Write-Output "Creating a new user assigned identity."
    $UserIdentity = New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $IdentityName -ErrorAction Stop
}
Else {
    Write-Output "Found User Assigned Identity"
}
$IdentityNameResourceId = $UserIdentity.Id
$IdentityNamePrincipalId = $UserIdentity.PrincipalId

Write-Output "Checking for custom Azure Role definition named '$ImageRoleDefName'."
If (!(Get-AzRoleDefinition -Name $imageRoleDefName -ErrorAction SilentlyContinue)) {
    Write-Output "Custom Azure Role Definition not found. Now creating."
    $aibRoleImageCreationUrl="https://raw.githubusercontent.com/danielsollondon/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
    $aibRoleImageCreationPath = "$env:Temp\aibRoleImageCreation.json"

    # download config
    Invoke-WebRequest -Uri $aibRoleImageCreationUrl -OutFile $aibRoleImageCreationPath -UseBasicParsing

    ((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $aibRoleImageCreationPath
    ((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<rgName>', $imageResourceGroup) | Set-Content -Path $aibRoleImageCreationPath
    ((Get-Content -path $aibRoleImageCreationPath -Raw) -replace 'Azure Image Builder Service Image Creation Role', $imageRoleDefName) | Set-Content -Path $aibRoleImageCreationPath

    # create role definition
    New-AzRoleDefinition -InputFile "$env:Temp\aibRoleImageCreation.json" -ErrorAction Stop
    #endregion
}
Else {
    Write-Output "Custom Azure Role Definition found."
}

Write-Output "Checking for Role Assignment for '$IdentityName' with custom role."
If (!(Get-AzRoleAssignment -RoleDefinitionName $imageRoleDefName -objectID $IdentityNamePrincipalId -ErrorAction SilentlyContinue)) {
    # grant role definition to image builder service principal
    Write-Output 'Role Assignment not found. Creating a new one.'
    do {
        Write-Output "Waiting for custom role definition to be available for assignment."
        Start-Sleep -seconds 5
    } until (Get-AzRoleDefinition -Name $imageRoleDefName -ErrorAction SilentlyContinue)
    Write-Output "'$ImageRoleDefName' role definition available."
    Write-Output "Assigning role to '$IdentityName'."
    New-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -RoleDefinitionName $imageRoleDefName -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup" -ErrorAction Stop
}
Else {
    Write-Output 'Role Assignment Found.'
}

#region Step 3: Create the Shared Image Gallery and Image Definition

$sigGalleryName= "WVDSharedImages"
$imageDefName ="Windows10MS"
$imagePub = "WindowsDeploymentGuy"
$ImageOffer = "Windows-10"
$ImageSku = "EVD"

# create gallery
Write-Output "Checking for Shared Image Gallery named '$SIGGalleryName' in '$ImageResourceGroup' resource group."
If (!(Get-AzGallery -Name $sigGalleryName -ResourceGroupName $imageResourceGroup -ErrorAction SilentlyContinue)) {
    Write-Output 'Shared Image Gallery not found. Now creating the Shared Image Gallery.'
    New-AzGallery -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Location $location -ErrorAction Stop
}
Else {
    Write-Output 'Shared Image Gallery found.'
}
# create gallery definition
Write-Output "Checking for Image Definition named '$ImageDefName' in the shared image gallery."
If (!(Get-AzGalleryImageDefinition -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Name $imageDefName -ErrorAction SilentlyContinue)) {
    Write-Output 'Image Definition not found. Now creating it.'
    New-AzGalleryImageDefinition -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Location $location -Name $imageDefName -OsState generalized -OsType Windows -Publisher $imagePub -Offer $imageOffer -Sku $imageSku -ErrorAction Stop
}
Else {
    write-output "Image Definition Found."
}

#endregion

#Region Step 4: Configure the Image Template
Write-Output "Verifying that 'AZ.ImageBuilder' powershell module is installed."
If (!(Get-Module -Name AZ.ImageBuilder)) {
    Write-Output "Module not found. Installing."
    Install-Module AZ.ImageBuilder -Force -AllowClobber
}
Else {
    Write-Output "Module found."
}
Write-Output "Downloading Azure Image Builder JSON template from repo."
$templateUrl="https://raw.githubusercontent.com/shawntmeyer/WVD/master/Image-Build/AIB/ImageBuilder-GITHUB.json"
$templateFilePath = "$env:Temp\armTemplateWinSIG.json"

Invoke-WebRequest -Uri $templateUrl -OutFile $templateFilePath -UseBasicParsing
Write-Output "Updating fields in template with provided parameters."
((Get-Content -path $templateFilePath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<rgName>',$imageResourceGroup) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<runOutputName>',$runOutputName) | Set-Content -Path $templateFilePath

((Get-Content -path $templateFilePath -Raw) -replace '<imageDefName>',$imageDefName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<sharedImageGalName>',$sigGalleryName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region1>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<imgBuilderId>',$IdentityNameResourceId) | Set-Content -Path $templateFilePath

#endregion

#Region Step 5: Submit the template to AIB
Write-Output "Checking for existing image builder template named '$imageTemplateName'."
If (Get-AZImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName -ErrorAction SilentlyContinue) {
    Write-Output "Existing template found, must delete the template because they cannot be updated."
    Remove-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName -ErrorAction Stop
}
Else {
    Write-Output "Existing template not found."
}
Write-Output "Submitting Azure Image Builder template to service."
New-AzResourceGroupDeployment -ResourceGroupName $imageResourceGroup -TemplateFile $templateFilePath -api-version "2019-05-01-preview" -imageTemplateName $imageTemplateName -svclocation $location -ErrorAction Stop
#endregion
start-sleep 5
#Region Step 6: Invoke the Deployment

Write-Output "Starting Image Build"
Invoke-AzResourceAction -ResourceName $imageTemplateName -ResourceGroupName $imageResourceGroup -ResourceType Microsoft.VirtualMachineImages/imageTemplates -ApiVersion "2019-05-01-preview" -Action Run -Force
#endregion