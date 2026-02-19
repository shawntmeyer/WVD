Function Install-Evergreen {
    $adminCheck = [Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())
    $Admin = $adminCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" -and $_.InstallationPolicy -ne "Trusted" }) {
        if ($Admin) {
            Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted"
            Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.208 -Force
        } else {
            Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.208 -Force -Scope CurrentUser
        }
    }
    # Check for module in the appropriate scope
    if ($Admin) {
        $Installed = Get-Module -Name "Evergreen" -ListAvailable | `
            Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | `
            Select-Object -First 1
        $Published = Find-Module -Name "Evergreen"
        if ($Null -eq $Installed -or [System.Version]$Published.Version -gt [System.Version]$Installed.Version) {
            Install-Module -Name "Evergreen" -Force -AllowClobber
        }
    } else {
        # For non-admin, check CurrentUser scope and suppress warnings
        $CurrentUserPath = [Environment]::GetFolderPath('MyDocuments') + '\PowerShell\Modules\Evergreen'
        if (-not (Test-Path $CurrentUserPath)) {
            $CurrentUserPath = [Environment]::GetFolderPath('MyDocuments') + '\WindowsPowerShell\Modules\Evergreen'
        }
        $Installed = Get-Module -Name "Evergreen" -ListAvailable | Where-Object { $_.Path -like "*$($env:USERNAME)*" } | `
            Sort-Object -Property @{ Expression = { [System.Version]$_.Version }; Descending = $true } | `
            Select-Object -First 1
        
        # Only check for updates if no user-scope version exists or suppress update notifications
        if ($Null -eq $Installed) {
            Install-Module -Name "Evergreen" -Scope CurrentUser -Force -AllowClobber -WarningAction SilentlyContinue
        }
    }
    Import-Module -Name "Evergreen" -Force
}

function Get-EvergreenAppUri {
    param (
        [psobject]$Evergreen
    )
    $filters = @()
    if ($Evergreen.Architecture) {
        $Architecture = $Evergreen.Architecture
        $filters += '$_.Architecture -eq ''' + $Architecture + ''''
    }
    if ($Evergreen.InstallerType) {
        $InstallerType = $Evergreen.InstallerType
        $filters += '$_.InstallerType -eq ''' + $InstallerType + ''''
    }
    if ($Evergreen.Language) {
        $Language = $Evergreen.Language
        $filters += '$_.Language -eq ''' + $Language + ''''
    }
    if ($Evergreen.Type) {
        $Type = $Evergreen.Type
        $filters += '$_.Type -eq ''' + $Type + ''''
    } 
    if ($filters.Count -gt 0) {
        $WhereObject = ($filters -join ' -and ').replace('  ', ' ')
        $ScriptBlock = [scriptblock]::Create("Get-EvergreenApp -name $($Evergreen.name) | Where-Object {$($WhereObject)}")
        Return (Invoke-Command -ScriptBlock $ScriptBlock).Uri
    } Else {
        Return (Get-EvergreenApp -Name $($Evergreen.name)).Uri
    }
}