<#
.SYNOPSIS
Upload Scripts and Executable files needed to customize WVD VMs to the created Storage Accounts blob containers.

.DESCRIPTION
This cmdlet uploads files specifiied in the contentToUpload-sourcePath parameter to the blob specified in the contentToUpload-targetBlob parameter to the specified Azure Storage Account.

.PARAMETER ResourceGroupName
Name of the resource group that contains the Storage account to update.

.PARAMETER StorageAccountName
Name of the Storage account to update.

.PARAMETER contentToUpload
Optional. Array with a contentmap to upload.
E.g. $( @{ sourcePath = 'WVDScripts'; targetBlob = 'wvdscripts' })

.PARAMETER Confirm
Will promt user to confirm the action to create invasible commands

.PARAMETER WhatIf
Dry run of the script

.EXAMPLE
    Add-ContentToBlobContainer -ResourceGroupName "RG01" -StorageAccountName "storageaccount01"

    Uploads files contained in the WVDScripts Repo folder and the files contained in the wvdScaling Repo folder
    respectively to the "wvdscripts" blob container and to the "wvdScaling" blob container in the Storage Account "storageaccount01"
    of the Resource Group "RG01"

.EXAMPLE
    Add-ContentToBlobContainer -ResourceGroupName "RG01" -StorageAccountName "storageaccount01" -contentToUpload $( @{ sourcePath = 'WVDScripts'; targetBlob = 'wvdscripts' })
    
    Uploads files contained in the WVDScripts Repo folder to the "wvdscripts" blob container in the Storage Account "storageaccount01"
    of the Resource Group "RG01"
#>

function Add-ContentToBlobContainer {
    [CmdletBinding(SupportsShouldProcess = $True)]
    param(
        [Parameter(
            Mandatory,
            HelpMessage = "Specifies the name of the resource group that contains the Storage account to update."
        )]
        [string] $ResourceGroupName,

        [Parameter(
            Mandatory,
            HelpMessage = "Specifies the name of the Storage account to update."
        )]
        [string] $StorageAccountName,

        [Parameter(
            Mandatory,
            HelpMessage = "The paths to the content to upload."
        )]
        [string[]] $contentDirectories,

        [Parameter(
            Mandatory,
            HelpMessage = "The name of the container to upload to."
        )]
        [string] $targetContainer
    )

    Write-Verbose "Getting storage account context."
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -ErrorAction Stop
    $ctx = $storageAccount.Context

    foreach ($contentDirectory in $contentDirectories) {

        try {
            Write-Verbose "Processing content in path: [$contentDirectory]"
    
            Write-Verbose "Testing local path"
            If (-Not (Test-Path -Path $contentDirectory)) {
                throw "Testing local paths FAILED: Cannot find content path to upload [$contentDirectory]"
            }
            Write-Verbose "Getting files to be uploaded..."
            $scriptsToUpload = Get-ChildItem -Path $contentDirectory -ErrorAction 'Stop'
            Write-Verbose "Files to be uploaded:"
            Write-Verbose ($scriptsToUpload.Name | Format-List | Out-String)

            Write-Verbose "Testing blob container"
            Get-AzStorageContainer -Name $targetContainer -Context $ctx -ErrorAction 'Stop' | Out-Null
            Write-Verbose "Testing blob container SUCCEEDED"
    
            if ($PSCmdlet.ShouldProcess("Files to the '$targetContainer' container", "Upload")) {
                $scriptsToUpload | Set-AzStorageBlobContent -Container $targetContainer -Context $ctx -Force -ErrorAction 'Stop' | Out-Null
            }
            Write-Verbose ("[{0}] files in directory [{1}] uploaded to container [{2}]" -f $scriptsToUpload.Count, $contentDirectory, $targetContainer)
        }
        catch {
            Write-Error "Upload FAILED: $_"
        }
    }
}