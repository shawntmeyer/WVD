# Register for Azure Image Builder Feature

$AIBRegState = (Get-AzProviderFeature -FeatureName VirtualMachineTemplatePreview -ProviderNamespace Microsoft.VirtualMachineImages).RegistrationState
# wait until RegistrationState is set to 'Registered'
If ($AIBRegState -ne 'Registered' -or $AIBRegState -ne 'Registering') {
    Register-AzProviderFeature -FeatureName VirtualMachineTemplatePreview -ProviderNamespace Microsoft.VirtualMachineImages
}
while ((Get-AzProviderFeature -FeatureName VirtualMachineTemplatePreview -ProviderNamespace Microsoft.VirtualMachineImages).RegistrationState -ne 'Registered') {
    Write-Host "Waiting for Feature VirtualMachineTemplatePreview to be registered."
    Start-Sleep 5
}

# check you are registered for the providers, ensure RegistrationState is set to 'Registered'.
#Get-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages
#Get-AzResourceProvider -ProviderNamespace Microsoft.Storage 
#Get-AzResourceProvider -ProviderNamespace Microsoft.Compute
#Get-AzResourceProvider -ProviderNamespace Microsoft.KeyVault

Register-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages
Register-AzResourceProvider -ProviderNamespace Microsoft.Storage
Register-AzResourceProvider -ProviderNamespace Microsoft.Compute
Register-AzResourceProvider -ProviderNamespace Microsoft.KeyVault