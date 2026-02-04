# SessionHostReplacer Image Management Module
# Contains image version comparison and retrieval functions

# Import Core utilities
Import-Module "$PSScriptRoot\SessionHostReplacer.Core.psm1" -Force

#Region Image Version Functions

function Compare-ImageVersion {
    <#
    .SYNOPSIS
    Compares two image versions to determine their relative order.
    
    .DESCRIPTION
    Compares two image versions using semantic versioning rules (major.minor.patch).
    Returns:
        -1 if version1 < version2
         0 if version1 = version2
         1 if version1 > version2
    
    .PARAMETER Version1
    The first version to compare.
    
    .PARAMETER Version2
    The second version to compare.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Version1,
        
        [Parameter(Mandatory = $true)]
        [string] $Version2
    )
    
    # If versions are identical strings, return equal
    if ($Version1 -eq $Version2) {
        return 0
    }
    
    try {
        # Try to parse as semantic versions (e.g., 1.0.0, 2.1.3)
        $v1Parts = $Version1 -split '\.' | ForEach-Object { 
            $num = 0
            if ([int]::TryParse($_, [ref]$num)) { $num } else { 0 }
        }
        $v2Parts = $Version2 -split '\.' | ForEach-Object { 
            $num = 0
            if ([int]::TryParse($_, [ref]$num)) { $num } else { 0 }
        }
        
        # Pad arrays to same length with zeros
        $maxLength = [Math]::Max($v1Parts.Count, $v2Parts.Count)
        while ($v1Parts.Count -lt $maxLength) { $v1Parts += 0 }
        while ($v2Parts.Count -lt $maxLength) { $v2Parts += 0 }
        
        # Compare each part
        for ($i = 0; $i -lt $maxLength; $i++) {
            if ($v1Parts[$i] -lt $v2Parts[$i]) {
                return -1
            }
            elseif ($v1Parts[$i] -gt $v2Parts[$i]) {
                return 1
            }
        }
        
        # All parts equal
        return 0
    }
    catch {
        # If parsing fails, fall back to string comparison
        Write-LogEntry -Message "Failed to parse versions as semantic versions, using string comparison: $_" -Level Warning
        if ($Version1 -lt $Version2) { return -1 }
        elseif ($Version1 -gt $Version2) { return 1 }
        else { return 0 }
    }
}

function Get-LatestImageVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ARMToken,

        [Parameter()]
        [string] $ResourceManagerUri = (Get-ResourceManagerUri),

        [Parameter()]
        [string] $SubscriptionId = (Read-FunctionAppSetting VirtualMachinesSubscriptionId),

        [Parameter()]
        [hashtable] $ImageReference,

        [Parameter()]
        [string] $Location
    )

    # Initialize variables
    $azImageVersion = $null
    $azImageDate = $null
    $azImageDefinition = $null
    
    # Marketplace image
    if ($ImageReference.publisher) {
        # Set marketplace image definition for both latest and specific versions
        $azImageDefinition = "marketplace:$($ImageReference.publisher)/$($ImageReference.offer)/$($ImageReference.sku)"
        
        if ($null -ne $ImageReference.version -and $ImageReference.version -ne 'latest') {
            Write-LogEntry  "Image version is not set to latest. Returning version '$($ImageReference.version)'"
            $azImageVersion = $ImageReference.version
            # For specific marketplace versions, use current date as fallback since we can't determine actual publish date
            $azImageDate = Get-Date -AsUTC
        }
        else {
            Write-LogEntry -Message "Getting latest version of image publisher: $($ImageReference.publisher), offer: $($ImageReference.offer), sku: $($ImageReference.sku) in region: $($Location)"
                      
            $Uri = "$ResourceManagerUri/subscriptions/$SubscriptionId/providers/Microsoft.Compute/locations/$Location/publishers/$($ImageReference.publisher)/artifacttypes/vmimage/offers/$($ImageReference.offer)/skus/$($ImageReference.sku)/versions?api-version=2024-07-01"
            
            $response = Invoke-AzureRestMethod -ARMToken $ARMToken -Uri $Uri -Method Get
            $Versions = @($response)
            
            if (-not $Versions -or $Versions.Count -eq 0) {
                throw "No image versions found for publisher: $($ImageReference.publisher), offer: $($ImageReference.offer), sku: $($ImageReference.sku)"
            }
            
            Write-LogEntry -Message "Found $($Versions.Count) image versions"
            
            # Sort versions and get the latest (sort by name as string since version format may have 4 components)
            $latestVersion = $Versions | Sort-Object -Property name -Descending | Select-Object -First 1
            
            if ($null -eq $latestVersion) {
                throw "Failed to sort and select latest version from API response"
            }
            
            $azImageVersion = $latestVersion.name
            
            if (-not $azImageVersion) {
                throw "Could not extract version name from latest image version object"
            }
            
            Write-LogEntry -Message "Latest version of image is $azImageVersion" -Level Trace

            if ($azImageVersion -match "\d+\.\d+\.(?<Year>\d{2})(?<Month>\d{2})(?<Day>\d{2})") {
                $azImageDate = Get-Date -Date ("20{0}-{1}-{2}" -f $Matches.Year, $Matches.Month, $Matches.Day)
                Write-LogEntry  "Image date is $azImageDate"
            }
            else {
                throw "Image version does not match expected format. Could not extract image date."
            }
        }
    }
    elseif ($ImageReference.id) {
        $imageDefinitionResourceIdPattern = '^\/subscriptions\/(?<subscription>[a-z0-9\-]+)\/resourceGroups\/(?<resourceGroup>[^\/]+)\/providers\/Microsoft\.Compute\/galleries\/(?<gallery>[^\/]+)\/images\/(?<image>[^\/]+)$'
        $imageVersionResourceIdPattern = '^\/subscriptions\/(?<subscription>[a-z0-9\-]+)\/resourceGroups\/(?<resourceGroup>[^\/]+)\/providers\/Microsoft\.Compute\/galleries\/(?<gallery>[^\/]+)\/images\/(?<image>[^\/]+)\/versions\/(?<version>[^\/]+)$'
        if ($ImageReference.id -match $imageDefinitionResourceIdPattern) {
            Write-LogEntry 'Image reference is an Image Definition resource.'
            $imageSubscriptionId = $Matches.subscription
            $imageResourceGroup = $Matches.resourceGroup
            $imageGalleryName = $Matches.gallery
            $imageDefinitionName = $Matches.image
            Write-LogEntry -Message "Fetching image versions for gallery '$imageGalleryName', image definition '$imageDefinitionName' in resource group '$imageResourceGroup' and subscription '$imageSubscriptionId'."
            
            # Store the image definition resource ID for tracking
            $azImageDefinition = $ImageReference.id

            # First, list all image versions (without replication status)
            $Uri = "$ResourceManagerUri/subscriptions/$imageSubscriptionId/resourceGroups/$imageResourceGroup/providers/Microsoft.Compute/galleries/$imageGalleryName/images/$imageDefinitionName/versions?api-version=2024-03-03"
            $imageVersions = Invoke-AzureRestMethod -ARMToken $ARMToken -Method Get -Uri $Uri
            
            if (-not $imageVersions -or $imageVersions.Count -eq 0) {
                throw "No image versions found in gallery '$imageGalleryName' for image '$imageDefinitionName'."
            }
            
            Write-LogEntry -Message "Found $($imageVersions.Count) total image versions in gallery" -Level Trace
            
            # Normalize location for comparison (Azure returns full names like "East US 2")
            $normalizedLocation = $Location -replace '\s', ''
            
            # Filter candidate versions (exclude flag check and published date check only)
            # We'll check replication status afterwards for the selected candidate
            $candidateVersions = $imageVersions |
            Where-Object { 
                $globalExclude = $_.properties.publishingProfile.excludeFromLatest
                $regionalExclude = $false
                
                # Check if this version is excluded in the target region
                $targetRegion = $_.properties.publishingProfile.targetRegions | Where-Object { 
                    ($_.name -replace '\s', '') -eq $normalizedLocation 
                }
                if ($targetRegion) {
                    $regionalExclude = $targetRegion.excludeFromLatest
                }
                
                # Include only if NOT excluded globally AND NOT excluded regionally AND has published date
                -not $globalExclude -and -not $regionalExclude -and $_.properties.publishingProfile.publishedDate
            }
            
            if (-not $candidateVersions -or $candidateVersions.Count -eq 0) {
                # Fallback: if no valid candidates, get first non-excluded version
                $candidateVersions = $imageVersions |
                Where-Object { -not $_.properties.publishingProfile.excludeFromLatest }
            }
            
            if (-not $candidateVersions -or $candidateVersions.Count -eq 0) {
                throw "No available image versions found (all versions are marked as excluded from latest)."
            }
            
            # Sort candidates by published date and check replication status for each until we find a replicated one
            $sortedCandidates = $candidateVersions |
            Sort-Object -Property { [DateTime]$_.properties.publishingProfile.publishedDate } -Descending
            
            $latestImageVersion = $null
            foreach ($candidate in $sortedCandidates) {
                # Fetch full details with replication status for this specific version
                $versionUri = "$ResourceManagerUri/subscriptions/$imageSubscriptionId/resourceGroups/$imageResourceGroup/providers/Microsoft.Compute/galleries/$imageGalleryName/images/$imageDefinitionName/versions/$($candidate.name)?`$expand=ReplicationStatus&api-version=2024-03-03"
                $versionDetails = Invoke-AzureRestMethod -ARMToken $ARMToken -Method Get -Uri $versionUri
                
                # Check replication status for the target region
                $isReplicated = $false
                if ($versionDetails.properties.replicationStatus.summary) {
                    $regionReplicationStatus = $versionDetails.properties.replicationStatus.summary | Where-Object {
                        ($_.region -replace '\s', '') -eq $normalizedLocation
                    }
                    
                    if ($regionReplicationStatus) {
                        $isReplicated = $regionReplicationStatus.state -eq 'Completed'
                        
                        if ($isReplicated) {
                            Write-LogEntry -Message "Image version {0} is replicated to region {1}" `
                                -StringValues $candidate.name, $Location
                            $latestImageVersion = $versionDetails
                            break
                        }
                        else {
                            Write-LogEntry -Message "Image version {0} is not yet replicated to region {1} (state: {2}, progress: {3}%)" `
                                -StringValues $candidate.name, $Location, $regionReplicationStatus.state, $regionReplicationStatus.progress `
                                -Level Warning
                        }
                    }
                    else {
                        Write-LogEntry -Message "Image version {0} does not have replication status for region {1}" `
                            -StringValues $candidate.name, $Location `
                            -Level Warning
                    }
                }
                else {
                    Write-LogEntry -Message "Image version {0} does not have replication status information" `
                        -StringValues $candidate.name `
                        -Level Warning
                }
            }
            
            if (-not $latestImageVersion) {
                throw "No replicated image versions found for region '$Location'. All candidate versions are either still replicating or missing replication status."
            }
            
            $azImageVersion = $latestImageVersion.name
            $azImageDate = [DateTime]$latestImageVersion.properties.publishingProfile.publishedDate
            Write-LogEntry -Message "Select image version is {0} and date is {1}" -StringValues $azImageVersion, $azImageDate.ToString('o')
        }
        elseif ($ImageReference.id -match $imageVersionResourceIdPattern ) {
            Write-LogEntry 'Image reference is an Image Version resource.'
            # Extract image definition path (without version)
            if ($ImageReference.id -match '^(?<definition>.+)/versions/[^/]+$') {
                $azImageDefinition = $Matches['definition']
            }
            $Uri = "$ResourceManagerUri$($ImageReference.id)?api-version=2023-07-03"
            $imageVersion = Invoke-AzureRestMethod -ARMToken $ARMToken -Method Get -Uri $Uri
            $azImageVersion = $imageVersion.name
            
            # Parse published date with null check
            if ($imageVersion.properties.publishingProfile.publishedDate) {
                $azImageDate = [DateTime]$imageVersion.properties.publishingProfile.publishedDate
                Write-LogEntry -Message "Image version is {0} and date is {1}" -StringValues $azImageVersion, $azImageDate.ToString('o')
            } else {
                # Fallback to current date if published date not available
                $azImageDate = Get-Date -AsUTC
                Write-LogEntry -Message "Image version is {0} (published date not available, using current date)" -StringValues $azImageVersion -Level Warning
            }
        }
        else {
            throw "Image reference id does not match expected format for an Image Definition resource."
        }
    }
    else {
        throw "Image reference does not contain a publisher or id property. ImageReference, publisher, and id are case sensitive!!"
    }
    return [PSCustomObject]@{
        Version    = $azImageVersion
        Date       = $azImageDate
        Definition = $azImageDefinition
    }
}

#EndRegion Image Version Functions

# Export functions
Export-ModuleMember -Function Compare-ImageVersion, Get-LatestImageVersion