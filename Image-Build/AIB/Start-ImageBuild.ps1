#region Step 1: Setup Variables

# Import Module
Import-Module Az.Accounts
# Get Context
$currentAzContext = Get-AzContext
# destination image resource group
$imageResourceGroup="RG-AzureImageBuilder"
# location (see possible locations in main docs)
$location="EastUS"
# your subscription, this will get your current subscription
$subscriptionID=$currentAzContext.Subscription.Id
# name of the image to be created
$imageName="aibCustomImgWin10MS"
# image template name
$imageTemplateName="Windows10MS"
# distribution properties object name (runOutput), i.e. this gives you the properties of the managed image on completion
$runOutputName="Win10MS"
# create resource group
If (!(Get-AzResourceGroup -Name $imageResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $imageResourceGroup -Location $location
}
#endregion

#region Step 2: Create User Assigned Identity

# setup role def names, these need to be unique
$timeInt=$(get-date -UFormat "%s")
#$imageRoleDefName="Azure Image Builder Image Def"+$timeInt
$imageRoleDefName="Azure Image Builder Custom Role"
#$IdentityName="AIBUserIdentity"+$timeInt
$IdentityName="AIBUserIdentity"

## Add AZ PS module to support AzUserAssignedIdentity
If (!(Get-Module -name Az.ManagedServiceIdentity -ErrorAction SilentlyContinue)) {
    Install-Module -Name Az.ManagedServiceIdentity
}

# Cleanup from previous runs

$IdentityNameResourceId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $IdentityName -ErrorAction SilentlyContinue).Id
$IdentityNamePrincipalId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $IdentityName -ErrorAction SilentlyContinue).PrincipalId

If (($identityNamePrincipalID) -and (Get-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup" -RoleDefinitionName $imageRoleDefName -ErrorAction SilentlyContinue)) {
    Remove-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup" -RoleDefinitionName $imageRoleDefName -Force
}
If (Get-AzRoleDefinition -Name $imageRoleDefName -ErrorAction SilentlyContinue) {
    Remove-AzRoleDefinition -Name $imageRoleDefName -Force    
}
If (Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $IdentityName -ErrorAction SilentlyContinue) {
    Remove-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $IdentityName -Force
}

# create New identity
New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $IdentityName

$IdentityNameResourceId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $IdentityName).Id
$IdentityNamePrincipalId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $IdentityName).PrincipalId

$aibRoleImageCreationUrl="https://raw.githubusercontent.com/danielsollondon/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
$aibRoleImageCreationPath = "$env:Temp\aibRoleImageCreation.json"

# download config
Invoke-WebRequest -Uri $aibRoleImageCreationUrl -OutFile $aibRoleImageCreationPath -UseBasicParsing

((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $aibRoleImageCreationPath
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<rgName>', $imageResourceGroup) | Set-Content -Path $aibRoleImageCreationPath
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace 'Azure Image Builder Service Image Creation Role', $imageRoleDefName) | Set-Content -Path $aibRoleImageCreationPath

# create role definition
New-AzRoleDefinition -InputFile "$env:Temp\aibRoleImageCreation.json"
#endregion

# grant role definition to image builder service principal
New-AzRoleAssignment -ObjectId $IdentityNamePrincipalId -RoleDefinitionName $imageRoleDefName -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup"

#region Step 3: Create the Shared Image Gallery and Image Definition

$sigGalleryName= "WVDSharedImages"
$imageDefName ="Windows10MS"
$imagePub = "WindowsDeploymentGuy"
$ImageOffer = "Windows-10"
$ImageSku = "EVD"

# additional replication region
$replRegion2="westus"

# create gallery
If (!(Get-AzGallery -Name $sigGalleryName -ResourceGroupName $imageResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzGallery -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Location $location
}
# create gallery definition
If (!(Get-AzGalleryImageDefinition -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Name $imageDefName -ErrorAction SilentlyContinue)) {
    New-AzGalleryImageDefinition -GalleryName $sigGalleryName -ResourceGroupName $imageResourceGroup -Location $location -Name $imageDefName -OsState generalized -OsType Windows -Publisher $imagePub -Offer $imageOffer -Sku $imageSku
}

#endregion

#Region Step 4: Configure the Image Template
$templateUrl="https://raw.githubusercontent.com/shawntmeyer/WVD/master/Image-Build/AIB/ImageBuilder.json"
#$templateUrl="https://raw.githubusercontent.com/danielsollondon/azvmimagebuilder/master/quickquickstarts/1_Creating_a_Custom_Win_Shared_Image_Gallery_Image/armTemplateWinSIG.json"
#$templateFilePath = "armTemplateWinSIG.json"
$templateFilePath = "$env:Temp\armTemplateWinSIG.json"

Invoke-WebRequest -Uri $templateUrl -OutFile $templateFilePath -UseBasicParsing

((Get-Content -path $templateFilePath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<rgName>',$imageResourceGroup) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<runOutputName>',$runOutputName) | Set-Content -Path $templateFilePath

((Get-Content -path $templateFilePath -Raw) -replace '<imageDefName>',$imageDefName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<sharedImageGalName>',$sigGalleryName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region1>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region2>',$replRegion2) | Set-Content -Path $templateFilePath

((Get-Content -path $templateFilePath -Raw) -replace '<imgBuilderId>',$IdentityNameResourceId) | Set-Content -Path $templateFilePath

#endregion

#Region Step 5: Submit the template to AIB
If (Get-AZImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName -ErrorAction SilentlyContinue) {
    Remove-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName
}
New-AzResourceGroupDeployment -ResourceGroupName $imageResourceGroup -TemplateFile $templateFilePath -api-version "2019-05-01-preview" -imageTemplateName $imageTemplateName -svclocation $location
#endregion

#Region Step 6: Invoke the Deployment
Invoke-AzResourceAction -ResourceName $imageTemplateName -ResourceGroupName $imageResourceGroup -ResourceType Microsoft.VirtualMachineImages/imageTemplates -ApiVersion "2019-05-01-preview" -Action Run -Force
#endregion