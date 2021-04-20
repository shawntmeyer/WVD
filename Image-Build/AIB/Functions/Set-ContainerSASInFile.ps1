<#
.SYNOPSIS
Add a Container Specific SAS token to a Uri in a file.

.DESCRIPTION
This cmdlet generates a storage account Shared Access Signature token good for 3 hours and then dynamically adds the token to the specified file by replacing <SAS> with the token in the file.

.PARAMETER filepath
the path to the file to be updated with the signature

.PARAMETER Confirm
Will promt user to confirm the action to create invasible commands

.PARAMETER WhatIf
Dry run of the script

.EXAMPLE
    Set-ContainerSaSinFile -FilePath "c:\windows\temp\filename.ps1"

    Replaces <SAS> in filename.ps1 with a SAS token from the storage account referenced in the ps1.
#>
function Set-ContainerSASInFile {

	[CmdletBinding(SupportsShouldProcess)]
	param (
        [Parameter(Mandatory)]
        [string] $storageAccount,
        [Parameter(Mandatory)]
		[string] $blobContainer,
		[Parameter(Mandatory)]
		[string] $filePath
	)

	$fileContent = Get-Content -Path $filePath
    $saslines = $fileContent | Where-Object { $_ -like "*<SAS>*" } | ForEach-Object { $_.Trim() }
    
    If ($saslines.count -gt 0) {
        Write-Verbose ("Found [{0}] lines with sas tokens (<SAS>) to replace" -f $saslines.Count)
        $storageAccountResource = Get-AzResource -Name $storageAccount -ResourceType 'Microsoft.Storage/storageAccounts'

		if(-not $storageAccountResource) {
			throw "Storage account [$storageAccount] not found"
        }

        $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccountResource.ResourceGroupName -Name $storageAccount)[0].Value
        $context = New-AzStorageContext $storageAccount -StorageAccountKey $storageAccountKey
        $sasToken = New-AzStorageContainerSASToken -Name $blobContainer -Permission 'rl' -StartTime (Get-Date) -ExpiryTime (Get-Date).AddHours(3) -Context $context
        Foreach ($line in $saslines) {
            $newString = $line.Replace('<SAS>', $sasToken)
            $FileContent = $FileContent.Replace($line, $newString)
        }

        if ($PSCmdlet.ShouldProcess("File in path [$filePath]", "Overwrite")) {
            Set-Content -Path $filePath -Value $fileContent -Force
        }
    }
}