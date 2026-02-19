[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$AppDisplayNamePrefix,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$GraphEndpoint,

    [Parameter(Mandatory = $false)]
    [string]$PrivateEndpoint = "false",

    [Parameter(Mandatory = $false)]
    [string]$EnableCloudGroupSids = "false"
)

$ErrorActionPreference = "Stop"

# Convert strings to boolean
$PrivateLink = [System.Convert]::ToBoolean($PrivateEndpoint)
$UpdateTag = [System.Convert]::ToBoolean($EnableCloudGroupSids)

# Setup Logging
$logPath = "C:\Windows\Logs"
$logFile = Join-Path -Path $logPath -ChildPath "Update-StorageAccountApplicationManifest-$(Get-Date -Format 'yyyyMMdd-HHmm').log"
Start-Transcript -Path $logFile -Force

# Helper function to invoke Graph API with retry logic for DoD endpoints
function Invoke-GraphApiWithRetry {
    param (
        [Parameter(Mandatory = $true)]
        [string] $GraphEndpoint,
        
        [Parameter(Mandatory = $true)]
        [string] $AccessToken,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Get', 'Post', 'Patch', 'Delete')]
        [string] $Method,
        
        [Parameter(Mandatory = $true)]
        [string] $Uri,
        
        [Parameter()]
        [string] $Body,
        
        [Parameter()]
        [hashtable] $Headers = @{}
    )
    
    # Ensure GraphEndpoint doesn't have trailing slash
    $graphBase = if ($GraphEndpoint[-1] -eq '/') { 
        $GraphEndpoint.Substring(0, $GraphEndpoint.Length - 1) 
    } else { 
        $GraphEndpoint 
    }
    
    # Setup headers
    $requestHeaders = $Headers.Clone()
    $requestHeaders['Authorization'] = "Bearer $AccessToken"
    if (-not $requestHeaders.ContainsKey('Content-Type')) {
        $requestHeaders['Content-Type'] = 'application/json'
    }
    
    # List of endpoints to try
    $endpointsToTry = @($graphBase)
    
    # If we're using GCCH endpoint, also try DoD
    if ($graphBase -eq 'https://graph.microsoft.us') {
        $endpointsToTry += 'https://dod-graph.microsoft.us'
    }
    
    $lastError = $null
    foreach ($endpoint in $endpointsToTry) {
        try {
            $attemptUri = "$endpoint$Uri"
            
            $params = @{
                Uri     = $attemptUri
                Method  = $Method
                Headers = $requestHeaders
            }
            
            if ($Body -and $Method -in @('Post', 'Patch')) {
                $params['Body'] = $Body
            }
            
            $result = Invoke-RestMethod @params
            
            # If we succeeded with a different endpoint than the one provided, log it
            if ($endpoint -ne $graphBase) {
                Write-Warning "Graph API call succeeded with alternate endpoint: $endpoint"
                Write-Warning "Consider updating GraphEndpoint parameter to: $endpoint"
            }
            
            return $result
        }
        catch {
            $lastError = $_
            $statusCode = $null
            
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            
            # Try to extract detailed error from Graph API response
            $errorDetails = ""
            try {
                if ($_.Exception.Response) {
                    $responseStream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($responseStream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Close()
                    $responseStream.Close()
                    
                    $errorObj = $responseBody | ConvertFrom-Json
                    if ($errorObj.error) {
                        $errorDetails = "`n  Error Code: $($errorObj.error.code)`n  Error Message: $($errorObj.error.message)"
                        if ($errorObj.error.details) {
                            $errorDetails += "`n  Details: $($errorObj.error.details | ConvertTo-Json -Compress)"
                        }
                    }
                }
            }
            catch {
                # If we can't parse error details, just continue
            }
            
            # Retry on authentication/authorization errors (401, 403) or if endpoint not found (404 on base endpoint)
            if ($statusCode -in @(401, 403, 404) -and $endpoint -ne $endpointsToTry[-1]) {
                Write-Warning "Graph API call to $endpoint failed with status $statusCode$errorDetails. Trying alternate endpoint..."
                continue
            }
            else {
                # Don't retry - either not an auth error or we've tried all endpoints
                Write-Error "Graph API call failed with status $statusCode : $($_.Exception.Message)$errorDetails"
                throw
            }
        }
    }
    
    # If we get here, all endpoints failed
    Write-Error "All Graph API endpoints failed. Last error: $($lastError.Exception.Message)"
    throw $lastError
}

try {
    Write-Output "============================================"
    Write-Output "PHASE 1: Update Storage Account Application Manifest"
    Write-Output "This updates tags and identifier URIs for privatelink FQDN support"
    Write-Output "============================================"
    
    # Get Graph Access Token using Managed Identity
    $GraphUri = if ($GraphEndpoint[-1] -eq '/') { $GraphEndpoint.Substring(0, $GraphEndpoint.Length - 1) } else { $GraphEndpoint }
    $TokenUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$GraphUri&client_id=$ClientId"
    Write-Output "Requesting access token from IMDS..."
    $Response = Invoke-RestMethod -Headers @{ Metadata = "true" } -Uri $TokenUri
    If ($Response) {
        Write-Output "Successfully obtained access token"
        $AccessToken = $Response.access_token
    }
    else {
        throw "Failed to obtain access token from IMDS."
    }
        
    # Search for the application by DisplayName
    $searchUri = "/v1.0/applications?" + '$filter=' + "startswith(displayName, '$AppDisplayNamePrefix')"
    Write-Output "Searching for applications with prefix: $AppDisplayNamePrefix"
    try {
        $searchHeaders = @{ "ConsistencyLevel" = "eventual" }
        $searchResp = Invoke-GraphApiWithRetry -GraphEndpoint $GraphUri -AccessToken $AccessToken -Method Get -Uri $searchUri -Headers $searchHeaders
        
        if ($searchResp.value.Count -eq 0) {
            throw "No application found starting with '$AppDisplayNamePrefix'."
        }
        Write-Output "Found $($searchResp.value.Count) applications starting with '$AppDisplayNamePrefix'."
    }
    catch {
        Write-Error ("Failed to search for application: " + $_.Exception.Message)
        throw $_
    }

    foreach ($app in $searchResp.value) {
        $appObjectId = $app.id
        $appName = $app.displayName
        Write-Output "Processing Application: $appName (ObjectId: $appObjectId)"
        
        $uri = "/v1.0/applications/$appObjectId"

        # 1. Update Tags
        If ($UpdateTag) {
            Write-Output "Updating tags with kdc_enable_cloud_group_sids..."
            $tags = @("kdc_enable_cloud_group_sids")
            $body = @{ tags = $tags } | ConvertTo-Json -Depth 5

            try {
                Invoke-GraphApiWithRetry -GraphEndpoint $GraphUri -AccessToken $AccessToken -Method Patch -Uri $uri -Body $body
                Write-Output "Tags updated successfully for $appName."
            }
            catch {
                Write-Error ("Failed to update tags for $appName : " + $_.Exception.Message)
                throw
            }
        }
        
        # 2. Update IdentifierUris for PrivateLink
        if ($PrivateLink) {
            Write-Output "Updating IdentifierUris for PrivateLink FQDN support..."
            try {
                # Get current app again to ensure we have latest identifierUris
                $currentApp = Invoke-GraphApiWithRetry -GraphEndpoint $GraphUri -AccessToken $AccessToken -Method Get -Uri $uri
                $currentUris = $currentApp.identifierUris
                $newUris = @($currentUris)
                $urisChanged = $false

                Write-Output "Current IdentifierUris:"
                foreach ($existingUri in $currentUris) {
                    Write-Output "  - $existingUri"
                }

                foreach ($identifierUri in $currentUris) {
                    # Check for standard file endpoint pattern (works across clouds: windows.net, usgovcloudapi.net, etc.)
                    # Only process URIs that have a proper scheme (api://, http://, https://) to comply with Azure AD policy
                    if ($identifierUri -match '\.file\.core\.' -and 
                        $identifierUri -notmatch '\.privatelink\.file\.core\.' -and
                        $identifierUri -match '^(api|http|https)://') {
                        # Insert .privatelink before .file.core.
                        $privateLinkUri = $identifierUri -replace '\.file\.core\.', '.privatelink.file.core.'
                        
                        # Add to list if not already present (preserving existing URIs)
                        if ($newUris -notcontains $privateLinkUri) {
                            Write-Output "  Adding PrivateLink URI: $privateLinkUri"
                            $newUris += $privateLinkUri
                            $urisChanged = $true
                        }
                    }
                }

                if ($urisChanged) {
                    $uriBody = @{ identifierUris = $newUris } | ConvertTo-Json -Depth 5
                    Invoke-GraphApiWithRetry -GraphEndpoint $GraphUri -AccessToken $AccessToken -Method Patch -Uri $uri -Body $uriBody
                    Write-Output "IdentifierUris updated successfully for $appName."
                    Write-Output "New IdentifierUris:"
                    foreach ($newUri in $newUris) {
                        Write-Output "  - $newUri"
                    }
                }
                else {
                    Write-Output "PrivateLink IdentifierUris already present or not applicable for $appName."
                }
            }
            catch {
                Write-Error ("Failed to update IdentifierUris for $appName : " + $_.Exception.Message)
                throw
            }
        }
    }
    
    Write-Output "============================================"
    Write-Output "PHASE 1 COMPLETE: Manifest updated successfully"
    Write-Output "Storage account applications can now authenticate via privatelink endpoints"
    Write-Output "============================================"
}
catch {
    Write-Error "PHASE 1 FAILED: $($_.Exception.Message)"
    throw $_
}
finally {
    Stop-Transcript
}
