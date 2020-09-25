<#
.SYNOPSIS
Run the Image Update process for the given host pool resource

.DESCRIPTION
Run the Image Update process for the given host pool resource
- Update the host pool

.PARAMETER HostPoolName
Mandatory. Name of the hostpool to process

.PARAMETER ResourceGroupName
Mandatory. Resource group of the hostpool to process

.PARAMETER LogoffDeadline
Mandatory. Logoff Deadline in yyyyMMddHHmm

.PARAMETER LogOffMessageTitle
Mandatory. Title of the popup the users receive when they get notified of their pending session logoff 

.PARAMETER LogOffMessageBody
Mandatory. Message of the popup the users receive when they get notified of their pending session logoff. The text "You will be automatically logged off at <DeadlineDateTime>." is appended

.PARAMETER LimitSecondsToForceLogOffUser
Optional. The number of seconds to provide the user as a grace period once the logoff deadline has passed before an automatic logoff occurs. The user will be presented with a message on the screen with the pending logoff and new logoff time displayed before the logoff is forced. Leave at 0 to not provide a grace period.

.PARAMETER DeleteVMDeadline
Optional. Controls when to delete the host pool VMs (Very Destructive) in yyyyMMddHHmm

.PARAMETER UtcOffset
Offset to UTC in hours

.PARAMETER TargetImageVersion
Optional. Specify the Target Image Version without any additional image parameters. Used primarily when not using Marketplace or Shared Gallery Images.

.PARAMETER MarketplaceImageVersion
Optional. Version of the used marketplace image. Use 'latest' to automatically specify the lastest version from the Marketplace. Mandatory if 'TargetImageVersion' or 'Shared Image Gallery' parameters are not provided.

.PARAMETER MarketplaceImagePublisher
Optional. Publisher of the used marketplace image. Mandatory if 'TargetImageVersion' or 'Shared Image Gallery' parameters are not provided.

.PARAMETER MarketplaceImageOffer
Optional. Offer of the used marketplace image. Mandatory if 'TargetImageVersion' or 'Shared Image Gallery' parameters are not provided.

.PARAMETER MarketplaceImageSku
Optional. Sku of the used marketplace image. Mandatory if 'TargetImageVersion' or 'Shared Image Gallery' parameters are not provided.

.PARAMETER MarketplaceImageLocation
Optional. Location of the used marketplace image. Mandatory if 'TargetImageVersion' or 'Shared Image Gallery' parameters are not provided and 'MarketplaceImageVersion = latest'.

.PARAMETER SIGName
Optional. Shared Image Gallery Name. Mandatory if 'TargetImageVersion' or 'Marketplace Image' parameters are not provided.

.PARAMETER SIGResourceGroup
Optional. The resource group that contains the Shared Image Gallery. Mandatory if 'TargetImageVersion' or 'Marketplace Image' parameters are not provided.

.PARAMETER SIGImageDefinitionName
Optional. The Shared Image Gallery Definition name for the image. Mandatory if 'TargetImageVersion' or 'Marketplace Image' parameters are not provided.

.PARAMETER SIGImageVersion
Optional. The name of the image version in the Shared Image Gallery under the specified Image Definition. Use 'latest' to automatically specify the latest image version. Mandatory if 'TargetImageVersion' or 'Marketplace Image' parameters are not provided.

.PARAMETER MaintenanceTagName
Optional. The tag name used to tell the scaling script not to process this session host.

.PARAMETER LAWorkspaceName
Optional. Name of the LA workspace to send logs to

.PARAMETER Confirm
Optional. Will promt user to confirm the action to create invisible commands

.PARAMETER WhatIf
Optional.  Dry run of the script

.EXAMPLE
Update-WVDHostPool -HostPoolName 'test-cse-hp' -ResourceGroupName 'WVD-HostPool-01-PO-RG' -LogoffDeadline '202007042000' -LogOffMessageTitle 'Kidding' -LogOffMessageBody 'Just' -UtcOffset '1' -customImageReferenceId '/subscriptions/62826c76-d304-46d8-a0f6-718dbdcc536c/resourceGroups/WVD-Imaging-PO-RG/providers/Microsoft.Compute/galleries/aaddsgallery/images/W10-19H2-O365-AADDS/versions/0.24322.55884'

Invoke the update host pool orchestration script with the given parameters
#>
Function Update-WVDHostPool {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [string] $HostPoolName,

        [Parameter(Mandatory)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory)]
        [string] $LogOffMessageTitle,

        [Parameter(Mandatory)]
        [string] $LogOffMessageBody,
    
        [Parameter(Mandatory)]
        [string] $UtcOffset,
        
        [Parameter(ParameterSetName = 'OtherCustomImage', Mandatory)]
        [string] $CustomImageVersion,

        [Parameter(ParameterSetName = 'MarketplaceImage', Mandatory)]
        [string] $MarketplaceImageVersion,
        
        [Parameter(ParameterSetName = 'MarketplaceImage', Mandatory)]
        [string] $MarketplaceImagePublisher,

        [Parameter(ParameterSetName = 'MarketplaceImage', Mandatory)]
        [string] $MarketplaceImageOffer,

        [Parameter(ParameterSetName = 'MarketplaceImage', Mandatory)]
        [string] $MarketplaceImageSku,

        [Parameter(ParameterSetName = 'MarketplaceImage', Mandatory = $false)]
        [string] $MarketplaceImageLocation,

        [Parameter(ParameterSetName = 'SIGImage', Mandatory)]
        [String] $SIGName,

        [Parameter(ParameterSetName = 'SIGImage', Mandatory)]
        [String] $SIGResourceGroup,

        [Parameter(ParameterSetName = 'SIGImage', Mandatory)]
        [String] $SIGImageDefinitionName,
        
        [Parameter(ParameterSetName = 'SIGImage', Mandatory)]
        [string] $SIGImageVersion,

        [Parameter(Mandatory = $false)]
        [string] $MaintenanceTagName,

        [Parameter(Mandatory)]
        [string] $LogoffDeadline, # Logoff Deadline in yyyyMMddHHmm

        [Parameter(Mandatory = $false)]
        [string] $LimitSecondsToForceLogOffUser = 0,

        [Parameter(Mandatory = $false)]
        [string] $DeleteVMDeadline = (Get-Date -Format yyyyMMddHHmm), # Removal Deadline in yyyyMMddHHmm

        [Parameter(mandatory = $false)]
        [string] $LAWorkspaceName = ""
    )

    # Setting ErrorActionPreference to stop script execution when error occurs
    $ErrorActionPreference = "Stop"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    #region Helper Functions
    function Get-LocalDateTime {
        return (Get-Date).ToUniversalTime().AddHours($TimeDiffHrsMin[0]).AddMinutes($TimeDiffHrsMin[1])
    }

    function Write-Log {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [switch]$Err,

            [Parameter(Mandatory = $false)]
            [switch]$Warn
        )

        [string]$MessageTimeStamp = (Get-LocalDateTime).ToString('yyyy-MM-dd HH:mm:ss')
        $Message = "[$($MyInvocation.ScriptLineNumber)] $Message"
        [string]$WriteMessage = "$MessageTimeStamp $Message"

        if ($Err) {
            Write-Error $WriteMessage
            $Message = "ERROR: $Message"
        }
        elseif ($Warn) {
            Write-Warning $WriteMessage
            $Message = "WARN: $Message"
        }
        else {
            Write-Verbose $WriteMessage -Verbose
        }
			
        if (-not $LogAnalyticsWorkspaceId -or -not $LogAnalyticsPrimaryKey) {
            return
        }

        try {
            $body_obj = @{
                'hostpoolName' = $HostPoolName
                'logmessage'   = $Message
                'TimeStamp'    = $MessageTimeStamp
            }
            $json_body = ConvertTo-Json -Compress $body_obj
            
            $laInputObject = @{
                customerId     = $LogAnalyticsWorkspaceId 
                sharedKey      = $LogAnalyticsPrimaryKey 
                Body           = $json_body 
                logType        = 'WVDHostpoolUpdate_CL'
                TimeStampField = 'TimeStamp'
            }
            
            $PostResult = Send-OMSAPIIngestionFile @laInputObject
            if ($PostResult -ine 'Accepted') {
                throw "Error posting to OMS: $PostResult"
            }
        }
        catch {
            Write-Warning "$MessageTimeStamp Some error occurred while logging to log analytics workspace: $($PSItem | Format-List -Force | Out-String)"
        }
    }

    function Convert-UTCtoLocalTime {
        <#
    .SYNOPSIS
    Convert from UTC to Local time
    #>
        param(
            [Parameter(Mandatory)]
            [string] $UtcOffset
        )

        $UniversalTime = (Get-Date).ToUniversalTime()
        $UtcOffsetMinutes = 0
        if ($UtcOffset -match ":") {
            $UtcOffsetHours = $UtcOffset.Split(":")[0]
            $UtcOffsetMinutes = $UtcOffset.Split(":")[1]
        }
        else {
            $UtcOffsetHours = $UtcOffset
        }
        #Azure is using UTC time, justify it to the local time
        $ConvertedTime = $UniversalTime.AddHours($UtcOffsetHours).AddMinutes($UtcOffsetMinutes)
        return $ConvertedTime
    }

    function Remove-ResourcesWithDeleteTag {

        <#
        .SYNOPSIS
        Remove resources with a 'ForDeletion' tag in an async job loop

        .DESCRIPTION
        Remove resources with a 'ForDeletion' tag in an async job loop

        .PARAMETER ResourceGroupName
        Mandatory. Name of the resource group to search the tagged resources in

        .PARAMETER ThrottleLimit
        Optional. The maximum number of threads to start at the same time. Defaults to 30.

        .PARAMETER Tag
        Optional. The tag to search for . Defaults to @{"ForDeletion" = $true} 

        .EXAMPLE
        Remove-ResourcesWithDeleteTag -ResourceGroupName 'WVD-HostPool-01-PO-RG' $Tag = @{"MyTag" = 'SomeValue'} -ThrottleLimit 10 

        Remove all resources that have the Tag @{"MyTag" = 'SomeValue'} in resource group 'WVD-HostPool-01-PO-RG' using a maximum of 10 simultaneous jobs
        #>
        param(
            [Parameter(Mandatory)]
            [string] $ResourceGroupName,

            [Parameter(Mandatory = $false)]
            [int] $ThrottleLimit = 30,

            [Parameter(Mandatory = $false)]
            [Hashtable] $Tag = @{"ForDeletion" = $true}
        )

        $leftoverResources = Get-AzResource -Tag $Tag -ResourceGroupName $ResourceGroupName

        if ($leftoverResources.Count -gt 0) {
            Write-Log "##----------------------------------##"
            Write-Log "## REMOVE RESOURCES WITH DELETE TAG ##"
            Write-Log ("[{0}] resources tagged for removal have not been deleted. Trying again." -f $leftoverResources.Count)
            $removalJobs = $leftoverResources | Foreach-Object -AsJob -ThrottleLimit $ThrottleLimit -Parallel { 
                Write-Log ("Retry removal of resource [{0}]" -f $_.Name)
                $null = Remove-AzResource -ResourceId $_.ResourceId -Force -ErrorAction 'SilentlyContinue'
                Write-Log "--------------------------------------------------------------------"
            }

            $null = Wait-Job -Job $removalJobs

            foreach ($job in $removalJobs) {
                Receive-Job -Job $job -ErrorAction 'SilentlyContinue'
            } 
        }
    }

    function Remove-VirtualMachineByLoop {
    
        <#
        .SYNOPSIS
        Remove all VMs in the given ArrayList in parallel using jobs
        
        .DESCRIPTION
        Remove all VMs in the given ArrayList in parallel using jobs
            
        .PARAMETER VmsToRemove
        Optional. An ArrayList of the VMs to remove. Should contain VM instances (e.g. provided by 'Get-AzVM')
        
        .PARAMETER ThrottleLimit
        Optional. The maximum number of threads to start at the same time. Defaults to 30.
        
        .EXAMPLE
        Remove-VirtualMachineByLoop -VmsToRemove ([ArrayList] Get-AzVM) -ThrottleLimit 10

        Removes all VMs in the subscription using 10 parallel jobs at a time
        #>
        param
        (
            [Parameter(Mandatory = $false)]
            [System.Collections.ArrayList] $VmsToRemove = @(),

            [Parameter(Mandatory = $false)]
            [int] $ThrottleLimit = 30
        )

        ##########
        ### VM ###
        ##########
        $vmRemovalJobs = $VmsToRemove | Foreach-Object -AsJob -ThrottleLimit $ThrottleLimit -Parallel { 
            $vm = $_
            $VmName = $vm.Name
            $deletionTag = @{"ForDeletion" = $true} 
            Write-Log "[VM:$VmName] Entered vm deletion job."

            Write-Log ("[VM:$VmName] Remove Azure VM [{0}]" -f $VmName)
            $null = New-AzTag -ResourceId $vm.Id -Tag $deletionTag
            $null = $vm | Remove-AzVM -Force
            Write-Log "--------------------------------------------------------------------"
        }

        if ($vmRemovalJobs.Length -gt 0) {
            Write-Log "##-------------------------------##"
            Write-Log ("## WAIT FOR [{0}] VM REMOVAL JOBS ##" -f $vmRemovalJobs.Count)
            Write-Log "##-------------------------------##"

            $null = Wait-Job -Job $vmRemovalJobs
        
            foreach ($job in $vmRemovalJobs) {
                Receive-Job -Job $job -ErrorAction 'SilentlyContinue'  
            } 
        }

        # INTERMEDIATE STEP: RETRY REMOVAL OF LEFTOVERS
        Remove-ResourcesWithDeleteTag -ResourceGroupName $VmsToRemove[0].ResourceGroupName -ThrottleLimit $ThrottleLimit     
        
        ########################
        ### SUB-VM-RESOURCES ###
        ########################
        $removalJobs = $VmsToRemove | Foreach-Object -AsJob -ThrottleLimit $ThrottleLimit -Parallel { 

            $vm = $_
            $VmName = $vm.Name
            $deletionTag = @{"ForDeletion" = $true} 
            Write-Log "[VM:$VmName] Entered vm sub-resource deletion job."

            ###############
            ### NETWORK ###
            foreach ($nicUri in $vm.NetworkProfile.NetworkInterfaces.Id) {
                # NIC
                Write-Log ("[VM:$VmName] Remove Network Interface [$nicUri]")	
                $nic = Get-AzNetworkInterface -ResourceId $nicUri -ErrorAction 'SilentlyContinue'
                $null = New-AzTag -ResourceId $nicUri -Tag $deletionTag
                if ($nic) {
                    $null = $nic | Remove-AzNetworkInterface -Force
                    # PIP
                    foreach ($ipConfig in $nic.IpConfigurations) {
                        if ($ipConfig.PublicIpAddress) {
                            $pipName = $ipConfig.PublicIpAddress.Id.Split('/')[-1]
                            Write-Log ("[VM:$VmName] Remove Public IP Address [$pipName]")
                            $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $vm.ResourceGroupName -ErrorAction 'SilentlyContinue'
                            if ($pip) {
                                $null = New-AzTag -ResourceId $pip.Id -Tag $deletionTag
                                $null = $pip | Remove-AzPublicIpAddress -Force
                            }
                            else {
                                Write-Log ("[VM:$VmName] No public ip [$pipName] found in resource group [{0}]" -f $vm.ResourceGroupName)
                            }
                        }                       
                    } 
                } 
                else {
                    Write-Log ("[VM:$VmName] No nic [{0}] found in resource group [{1}]" -f $nic.Name, $vm.ResourceGroupName)
                }
            }

            ###############
            ### OS DISK ### 
            $diskName = $vm.StorageProfile.OsDisk.Name
            Write-Log "[VM:$VmName] Remove managed OS Disk [$diskName]"
            $disk = Get-AzResource -ResourceType 'Microsoft.Compute/disks' -Name $diskName -ResourceGroupName $vm.ResourceGroupName
            if ($disk) {
                $null = New-AzTag -ResourceId $disk.ResourceId -Tag $deletionTag
                $null = $disk | Remove-AzDisk -Force
            }
            else {
                Write-Log ("[VM:$VmName] No disk [$diskName] found in resource group [{0}]" -f $vm.ResourceGroupName)
            }

            #################
            ### DATA DISK ###
            if ('DataDiskNames' -in $vm.PSObject.Properties.Name -and @($vm.DataDiskNames).Count -gt 0) {
                # Removing Data Disks for VM
                foreach ($uri in $vm.StorageProfile.DataDisks.Vhd.Uri) {
                    $dataDiskStorageAcct = Get-AzStorageAccount -Name $uri.Split('/')[2].Split('.')[0]
                    $containerName = $uri.Split('/')[-2]
                    $blobName = $uri.Split('/')[-1]
                    $dataDiskBlob = Get-AzStorageBlob -Container $containerName -Blob $blobName -Context $dataDiskStorageAcct.Context
                    Write-Log "[VM:$VmName] Remove  data disk [$blobName] in container [$containerName]"
                    $null = $dataDiskBlob | Remove-AzStorageBlob -Force
                }
            }
            Write-Log "--------------------------------------------------------------------"
        }

        if ($removalJobs.Length -gt 0) {
            Write-Log "##-----------------------------------##"
            Write-Log ("## WAIT FOR [{0}] VM-SUB-RESOURCE JOBS ##" -f $removalJobs.Count)
            Write-Log "##-----------------------------------##"

            $null = Wait-Job -Job $removalJobs

            foreach ($job in $removalJobs) {
                Receive-Job -Job $job -ErrorAction 'SilentlyContinue'
            } 

            # INTERMIDATE STEP: RETRY REMOVAL OF LEFTOVERS
            Remove-ResourcesWithDeleteTag -ResourceGroupName $VmsToRemove[0].ResourceGroupName -ThrottleLimit $ThrottleLimit
        }

        ## SPECIAL CASE: EVEN RETRY OF REMOVAL FAILED
        $unhandledResources = Get-AzResource -Tag @{"ForDeletion" = $true} -ResourceGroupName $VmsToRemove[0].ResourceGroupName
        if ($unhandledResources.count -gt 0) {
            Write-Log ("FAILED to remove several resources in resource group [{0}]. IDs are:" -f $VmsToRemove[0].ResourceGroupName) -Warn
            foreach ($unhandledRsource in $unhandledResources) {
                Write-Log ("- {0}" -f $unhandledRsource.ResourceId) -Warn
            }
        }
    }

    function Stop-SessionHost {
        <#
    .SYNOPSIS
    Stop the Session Host
    #>
        param(
            [Parameter(Mandatory)]
            [string] $VMName
        )

        try {
            Get-AzVM -Name $VMName | Stop-AzVM -Force -NoWait | Out-Null
        }
        catch {
            Write-Log "ERROR: Failed to stop Azure VM: $($VMName) with error: $($_.exception.message)"
            Write-Error ($_.exception.message)	
        }
    }

    function Add-ResourceTag {

        <#
        .SYNOPSIS
        Add/Overwrite a tag for a given resource
        
        .DESCRIPTION
        Add/Overwrite a tag for a given resource. Does not remove any.
        
        .PARAMETER resourceId
        Id of the resource to add tags to
        
        .PARAMETER name
        Name of the tag
        
        .PARAMETER value
        Value of the tag
        
        .EXAMPLE
        Add-ResourceTag -resourceId '/subscriptions/62826c76-d304-46d8-a0f6-718dbdcc536c/resourceGroups/myRG' -name 'test' -value 'withTagValue'

        Add the tag 'test = withTagValue' to resource group 'myRG'
        #>
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [string] $resourceId,

            [Parameter(Mandatory)]
            [string] $name,

            [Parameter(Mandatory)]
            [string] $value
        )

        $existingTags = Get-AzTag -ResourceId $resourceId

        if ($existingTags.Properties.TagsProperty.Keys -contains $name) {
            $existingTags.Properties.TagsProperty.$name = $value
        }
        else {
            $existingTags.Properties.TagsProperty.Add($name, $value)
        }
        
        $null = New-AzTag -ResourceId $ResourceId -Tag $existingTags.Properties.TagsProperty
    }

    function Set-ResourceGroupLifecycleTag {

        <#
        .SYNOPSIS
        Set resource group level tags to inform about the host pools resource state
        
        .DESCRIPTION
        The tags help to get an overview of the host-pools state on a resource group level. Tags that are assigned are:
        - LifecycleState = Consistent
        - LifecycleState = UpdateInitialized
        - LifecycleState = UpdateCompleted
        - LifecycleState = RequiresReRun
        
        .PARAMETER HostPoolName
        Name of the host pool to check
        
        .PARAMETER ResourceGroupName
        Manadatory. Name of the resource group the host pool is in. This is the one that gets the tags
        
        .PARAMETER TargetImageVersion
        Manadatory. The image version the host pool VMs should have that are considered up-to-date
        
        .PARAMETER ShutDownVMDeadlinePassed
        Mandatory. Flag to specify whether the deadline for deprecated host pool VMs to shut down has already passed

        .EXAMPLE
        Set-ResourceGroupLifecycleTag -ResourceGroupName 'WVD-HostPool-01-PO-RG' -HostPoolName 'test-cse-hp' -TargetImageVersion '0.24322.55884' -ShutDownVMDeadlinePassed $false
        
        Evaluate the current state of the host pool 'test-cse-hp' VMs and set the flags accordingly. The deadline for deprecated VMs to be force shut-down has not yet passed.
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [Parameter(Mandatory)]
            [string] $HostPoolName,

            [Parameter(Mandatory)]
            [string] $ResourceGroupName,

            [Parameter(Mandatory)]
            [string] $TargetImageVersion,

            [Parameter(Mandatory)]
            [bool] $ShutDownVMDeadlinePassed
        )
    
        $lifecycleTagName = 'LifecycleState'
        $lifecycleTagValueConsistent = 'Consistent' 
        $lifecycleTagValueUpdateInit = 'UpdateInitialized' 
        $lifecycleTagValueUpdateCom = 'UpdateCompleted' 
        $lifecycleTagValueReRun = 'RequiresReRun' 
    
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName
        
        # Case 1 : First deployment
        if ($resourceGroup.Tags.Keys -notcontains $lifecycleTagName) {
            Write-Log "First run for this resource group. No lifecycle tag existing yet, creating new. State is consistent."
            if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueConsistent] on resource group $ResourceGroupName", "Set")) {
                Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueConsistent
            }
            return
        }
    
        $sessionHosts = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Sort-Object 'SessionHostName'

        # Case 2 : No VMs are deployed
        if (-not $sessionHosts) {
            if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueConsistent] on resource group $ResourceGroupName", "Set")) {  
                Write-Log "No session hosts deployed. Host Pool is consistent."
                Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueConsistent
            }           
            return
        }

        $outdatedVMs = Get-AzVm -ResourceGroupName $ResourceGroupName -Status | Where-Object { $_.Tags.ImageVersion -ne $TargetImageVersion }
    
        # Handle case: Deadline has not passed yet
        if (-not $ShutDownVMDeadlinePassed) {
            # Case 3 : There are outdated VMs that are starting or running
            $case3VMs = $outdatedVMs | Where-Object { ($_.PowerState -eq 'VM running' -or $_.PowerState -eq 'VM starting') }
            if ($case3VMs.Count -gt 0) {
                if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueUpdateInit] on resource group $ResourceGroupName", "Set")) {  
                    Write-Log "Setting ResourceGroup Tag. Host Pool image update was initialized."
                    Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueUpdateInit
                }
                return
            }
            else {
                # Case 4 If we have outdated VMs, but they are all already either deallocating or deallocated 
                if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueUpdateCom] on resource group $ResourceGroupName", "Set")) {
                    Write-Log "Setting ResourceGroup Tag. Host Pool image update was initialized, but all outdated VMs are already shutting/shut down. Update is completed."
                    Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueUpdateCom
                }
                return
            }
        }
        # Handle case: Deadline has passed 
        else {
            $case5VMs = $outdatedVMs | Where-Object { ($_.PowerState -eq 'VM deallocated' -or $_.PowerState -eq 'VM deallocating') }
            if ($case5VMs.Count -eq $outdatedVMs.Count) {
                # Case 5 : VMs post deadline that aren't active anymore, but still exist
                if ($case5VMs.Count -gt 0) {
                    if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueUpdateCom] on resource group $ResourceGroupName", "Set")) {
                        Write-Log "Setting ResourceGroup Tag. Host pool image update completed."
                        Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueUpdateCom
                    }
                    return
                }
                # Case 6 : No more VMs post deadline that don't match latest image  
                else {
                    if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueConsistent] on resource group $ResourceGroupName", "Set")) {
                        Write-Log "Setting ResourceGroup-Tag. No outdated VMs left in the host pool. State is consistent."
                        Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueConsistent
                    }
                    return
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess("Log entry that update was not successful and ask for re-run.", "Add")) {
                    Write-Log "WARNING: VMs should be deallocated, but are not (yet). Please re-run" -Warn
                    Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueReRun               
                }
                else {
                    Add-LogEntry -LogMessageObj @{ hostpool = $HostpoolName; msg = "VMs should be deallocated, but are not (yet). Please re-run" }
                }
                return
            }
        }
    }
    #endregion

    ##################
    ### MAIN LOGIC ###
    ##################

    # Converting date time from UTC to Local
    $CurrentDateTime = Convert-UTCtoLocalTime -UtcOffset $UtcOffset
    [string[]]$TimeDiffHrsMin = "$($UtcOffset):0".Split(':')

    ## Log Analytics
    ## -------------
    if (-not [String]::IsNullOrEmpty($LAWorkspaceName)) {
        if (-not ($LAWorkspace = Get-AzOperationalInsightsWorkspace | Where-Object { $_.Name -eq $LAWorkspaceName })) {
            throw "Provided log analytic workspace doesn't exist in your Subscription."
        }

        $WorkSpace = Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $LAWorkspace.ResourceGroupName -Name $LAWorkspaceName -WarningAction Ignore
        $LogAnalyticsPrimaryKey = $Workspace.PrimarySharedKey
        $LogAnalyticsWorkspaceId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $LAWorkspace.ResourceGroupName -Name $LAWorkspaceName).CustomerId.GUID
    }

    if ($LogAnalyticsWorkspaceId -and $LogAnalyticsPrimaryKey) {
        Write-Verbose "Log analytics is enabled" -Verbose
    }

    # Calculate Image Version from Parameters
    if ($PSCmdlet.ParameterSetName -eq 'MarketplaceImage') {
        if ($MarketplaceImageVersion -eq 'latest') {
            Write-Log "Using Azure Marketplace Image"
            $getImageInputObject = @{
                Location      = $MarketplaceImageLocation
                PublisherName = $MarketplaceImagePublisher 
                Offer         = $MarketplaceImageOffer 
                Sku           = $MarketplaceImageSku
            }
            Try {
                $AvailableVersions = Get-AzVMImage @getImageInputObject | Select-Object Version
                $LatestVersion = (($availableVersions.Version -as [Version[]]) | Measure-Object -Maximum).Maximum
                Write-Log "The latest available '$MarketPlaceImageSku' is '$latestVersion'. Using this version as 'TargetImageVersion'."
                [Version]$TargetImageVersion = $latestVersion
            }
            Catch {
                throw "Check Azure Marketplace image parameter values. Could not retrieve image versions."
                Exit
            }
        }
        else {
            Write-Log "Using the specified image version '$MarketplaceImageVersion' as 'TargetImageVersion'."
            [Version]$TargetImageVersion = $MarketplaceImageVersion
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'SIGImage') {
        Write-Log "Using Shared Image Gallery Image"
        If ($SIGImageVersion -eq 'latest') {
            $getImageInputObject = @{
                GalleryName = $SIGName
                ResourceGroupName = $SIGResourceGroup
                GalleryImageDefinitionName = $SIGImageDefinitionName
        }
        Try {
            # Get all versions of the Shared Image Gallery Definition that are not excluded from Latest. The Version is stored as the Name property.
            $AvailableVersions = Get-AzGalleryImageVersion @getImageInputObject | Where-Object {$_.PublishingProfile.ExcludeFromLatest -ne $true} | Select-Object Name
            $LatestVersion = (($AvailableVersions.Name -as [Version[]]) | Measure-Object -Maximum).Maximum
            Write-Log "The latest available '$SIGImageDefinitionName' in the '$SIGName' is '$latestversion'. Using this version as 'TargetImageVersion'."
            [Version]$TargetImageVersion = $latestVersion
        }
        Catch {
            throw "Check Shared Image Gallery image parameter values. Could not retrieve Image versions."
            Exit
        }
        else {
            Write-Log "Using the specified image version '$SIGImageVersion' as 'TargetImageVersion'."
            [Version]$TargetImageVersion = $SIGImageVersion
        }
    }
    else {
        Write-Log "Image version specified is '$CustomImageVersion'. Using this version as 'TargetImageVersion'."
        [Version]$TargetImageVersion = $CustomImageVersion
    }

    ## Handle user session DeadlineTime
    $DeadlineDateTime = [System.DateTime]::ParseExact($LogoffDeadline, 'yyyyMMddHHmm', $null)
    ## Set Force Logoff if at or after deadline
    if ($CurrentDateTime -ge $DeadlineDateTime) {
        $ShutDownVMDeadlinePassed = $true
    }
    else {
        $ShutDownVMDeadlinePassed = $false
    }

    ## Handle delete VM DeadlineTime
    $DeleteVMDeadlineDataTime = [System.DateTime]::ParseExact($DeleteVMDeadline, 'yyyyMMddHHmm', $null)
    ## Set Force Logoff if at or after deadline
    if ($CurrentDateTime -ge $DeleteVMDeadlineDataTime) {
        $DeleteVMDeadlinePassed = $true
    }
    else {
        $DeleteVMDeadlinePassed = $false
    }

    # Validate and get HostPool info
    $HostPool = $null
    try {
        Write-Log "Get Hostpool info: '$HostPoolName' in resource group: '$ResourceGroupName'."
        $HostPool = Get-AzWvdHostPool -Name $HostPoolName -ResourceGroupName $ResourceGroupName
        if (-not $HostPool) {
            throw $HostPool
        }
    }
    catch {
        Write-Log "Hostpoolname '$HostpoolName' does not exist. Ensure that you have entered the correct values."
        exit
    }

    Write-Log "Starting WVD Hostpool Update: Current Date Time is: $CurrentDateTime."

    # Get list of session hosts in hostpool
    $SessionHosts = Get-AzWvdSessionHost -HostPoolName $HostpoolName -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Sort-Object Name
    # Check if the hostpool has session hosts
    if (-not $SessionHosts) {
        Write-Log "There are no session hosts in the '$HostpoolName' Hostpool."
        exit
    }

    Write-Log "Processing hostpool '$($HostpoolName)' which contains '$($SessionHosts).Count' session hosts."

    # Initialize variables for tracking running old session hosts.
    $RunningObsoleteSessionHosts = @()
    $vmsToRemove = [System.Collections.ArrayList]@()

    # Analyze the SessionHosts and Azure VM instances for applicability and to determine power state. Delete any turned off VMs if DeleteVM is specified.
    Write-Log "####################"
    Write-Log "##  ANALYZE HOSTS ##"
    Write-Log "##----------------##"

    Write-Log "Fetch VMs from resource group [$ResourceGroupName]"
    $HostPoolVMs = Get-AzVM -Status -ResourceGroupName $ResourceGroupName

    foreach ($SessionHost in $SessionHosts) {
        $SessionHostName = $SessionHost.Name.Split("/")[1]
        Write-Log "--------------------------------------------------------------------"
        $VMName = $SessionHostName.split('.')[0]
        $VMInstance = $HostPoolVMs | Where-Object { $_.Name -eq $VMName }
        Write-Log "[$VMName] Analyzing session host [$SessionHostName] for image version and power state."     

        if (-not $VMInstance) {
            Write-Log "[$VMName] The VM connected to session host [$SessionHostName] does not exist. Unregistering it."
            Remove-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -Name $SessionHostName
            continue
        }

        # Check if VM has new Image or old image based on ImageVersion tag Value
        if ($VMInstance.Tags.Keys -notcontains 'ImageVersion') {
            Write-Log "[$VMName] First time VM is touched by script. Adding required tags to VM and skipping further actions."
            Add-ResourceTag -resourceId $VMInstance.id -name 'ImageVersion' -value $TargetImageVersion
        }
        elseif ($VMInstance.Tags.ImageVersion -eq $TargetImageVersion) {
            Write-Log "[$VMName] VM is based on correct image version, skipping this VM."
        }
        else {
            Write-Log "[$VMName] VM is not based on correct image version."
            If ($MaintenanceTagName) {
                Add-ResourceTag -resourceId $VMInstance.id -name "$MaintenanceTagName" -value $true # Used e.g. by the scaling script to identify machines to ignore
            }
            # Set Drain Mode if not already set
            if ($SessionHost.AllowNewSession) {
                Update-AzWvdSessionHost -Name $SessionHostName -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -AllowNewSession:$False | Out-Null
            }
            # Check if the Azure vm is running       
            if ($VMInstance.PowerState -eq "VM running") {
                    Write-Log "[$VMName] VM is currently powered on."
                    $null = $RunningObsoleteSessionHosts.Add($SessionHost)
            }
            else {
                Write-Log "[$VMName] VM is currently powered off."
                if ($DeleteVMDeadlinePassed) {
                    Write-Log "[$VMName] The 'DeleteVM Deadline' passed. The stopped VM is being scheduled to be deleted from resource group [$ResourceGroupName] and removed from hostpool [$HostPoolName]"
                    $null = $vmsToRemove.Add($VMInstance)
                    Remove-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -Name $SessionHostName
                }
            }
        }          
    }

    Write-Log "#####################"
    Write-Log "##  PROCESS HOSTS ##"
    Write-Log "##----------------##"

    # Process powered on VMs to determine if there are user sessions. If no sessions, stop (or delete VM). If sessions, then send message to active sessions or forcefully logoff users if Deadline has passed.
    # Stop or Delete VM after all user sessions are removed.
    if (($RunningObsoleteSessionHosts).Count -gt 0) {
        $SessionHost = $null
        Write-Log "Current number of running hosts that need to be stopped and/or deleted: $RunningObsoleteSessionHosts.Count"
        Write-Log "Now processing each host."

        foreach ($SessionHost in $RunningObsoleteSessionHosts) {
            Write-Log "--------------------------------------------------------------------" 
            $SessionHostName = $SessionHost.Name.Split("/")[1]
            $VMName = $SessionHostName.split('.')[0]
            $VMInstance = $HostPoolVMs | Where-Object { $_.Name -eq $VMName }

            Write-Log "[$VMName] Processing session host [$SessionHostName]"

            if ($SessionHostName.ToLower().Contains($VMInstance.Name.ToLower())) {
                $UserSessions = Get-AzWvdUserSession -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -SessionHostName $SessionHostName
                If ((-not $UserSessions) -or ($($UserSessions).Count -eq 0)) {
                    # No user sessions on these Session Hosts
                    if ($DeleteVMDeadlinePassed) {
                        Write-Log "[$VMName] The 'DeleteVM Deadline' passed. The stopped VM is being scheduled to be deleted from resource group [$ResourceGroupName] and removed from hostpool [$HostPoolName]"
                        $null = $vmsToRemove.Add($VMInstance)
                        Remove-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -Name $SessionHostName
                    }
                    else {
                        # Shutdown the Azure VM
                        Write-Log "[$VMName] There are no more active user sessions on session host [$SessionHostName], but the delete VM deadline did not yes pass. Stopping the Azure VM."
                        $VMInstance | Stop-AzVM -AsJob -Force
                    }
                }
                Else {
                    # User Sessions exist on these Session Hosts
                    If ($ShutDownVMDeadlinePassed) {
                        $LogoffinSecs = [int]$LimitSecondstoForceLogoff
                        $ActiveUserSessions = Get-AzWvdUserSession -HostPoolName $HostpoolName -ResourceGroupName $ResourceGroupName -SessionHostName $SessionHostName | Where-Object {$_.SessionState -eq 'Active'}
                        if (($ActiveUserSessions).Count -gt 0 -and $LogoffinSecs -ne 0) {
                            Write-Log "[$VMName] There are [$ActiveUserSessions.Count] active user sessions on session host [$SessionHostName]"                        
                            Write-Log "[$VMName] Sending the last logoff warning message to users because deadline has passed."
                            foreach ($Session in $ActiveUserSessions) {
                                $SplitSessionID = $Session.Id.Split("/")
                                $SessionID = $SplitSessionID[$SplitSessionID.Count - 1]
                                try {
                                    $logofftime = (Get-Date).AddSeconds($LogoffinSecs) 
                                    Send-AzWvdUserSessionMessage -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -SessionHostName $SessionHostName -UserSessionId $SessionID -MessageTitle 'Warning' -MessageBody "Please save your work. You will be automatically logged off at $Logofftime. You can log back in immediately to continue your work."
                                }
                                Catch {
                                    Write-Log "Failed to send a logoff message to user: '$($Session.ActiveDirectoryUserName)', session ID: $SessionID $($PSItem |Format-List -Force | Out-String)"
                                }
                            }
                            Start-Sleep $LogoffinSecs
                            # Recheck user sessions after logoff timeout
                            $UserSessions = Get-AzWvdUserSession -HostPoolName $HostpoolName -ResourceGroupName $ResourceGroupName -SessionHostName $SessionHostName     
                        }          
        
                        if (($UserSessions).Count -gt 0) {
                            Write-Log "[$VMName] There are [$UserSessions.Count] user sessions remaining on session host [$SessionHostName]"
                            foreach ($Session in $UserSessions) {
                                $SplitSessionID = $Session.Id.Split("/")
                                $SessionID = $SplitSessionID[$SplitSessionID.Count - 1]
                                try {
                                    Remove-AzWvdUserSession -ResourceGroupName $ResourceGroupName -HostPoolName $HostpoolName -SessionHostName $SessionHostName -Id $SessionId -Force
                                    Write-Log ("[$VMName] Forcefully logged off the user [{0}]" -f ($Session.ActiveDirectoryUserName))
                                }
                                catch {
                                    Write-Log "[$VMName] Failed to log off user with error: $($_.exception.message)"
                                }
                            }
                        }

                        # Check for User Sessions every 5 seconds and wait for them to equal 0 or 60 sec timeout to expire.
                        $timer = 0
                        do {
                            $RemainingSessions = (Get-AzWvdUserSession -HostPoolName $HostpoolName -ResourceGroupName $ResourceGroupName -SessionHostName $SessionHostName).Count
                            $timer = $timer + 5
                            Start-Sleep -seconds 5
                        } until (($RemainingSessions -eq 0) -or ($timer -ge 60))

                        # Don't want to stop or delete a VM if we couldn't remove existing sessions because it could cause profile corruption or the user(s) may not be able to logon afterwards.
                        If ($RemainingSessions -eq 0) {
                            if ($DeleteVMDeadlinePassed) {
                                Write-Log "[$VMName] The 'DeleteVM Deadline' passed. The stopped VM is being scheduled to be deleted from resource group [$ResourceGroupName] and removed from hostpool [$HostPoolName]."
                                $null = $vmsToRemove.Add($VMInstance)
                                Remove-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -Name $SessionHostName
                            }
                            else {
                                # Shutdown the Azure VM
                                Write-Log "[$VMName] There are no more active user sessions on session host [$SessionHostName], but the delete VM deadline did not yet pass. Stopping the Azure VM."
                                $VMInstance | Stop-AZVm -AsJob -Force
                            }
                        }
                        else {
                            Write-Log "[$VMName] Unable to stop Azure VM: because it still has existing sessions."
                        }                      
                    }
                    Else {
                        # SessionHost Shutdown Deadline has not passed
                        $ActiveUserSessions = Get-AzWvdUserSession -HostPoolName $HostpoolName -ResourceGroupName $ResourceGroupName -SessionHostName $SessionHostName | Where-Object {$_.SessionState -eq 'Active'}
                        if (($ActiveUserSessions).Count -gt 0) {
                            Write-Log "[$VMName] There are [$ActiveUserSessions.Count] active user sessions on session host [$SessionHostName]"                        
                            Write-Log "[$VMName] Sending the logoff message to users with deadline."
                            foreach ($Session in $ActiveUserSessions) {
                                $SplitSessionID = $Session.Id.Split("/")
                                $SessionID = $SplitSessionID[$SplitSessionID.Count - 1]
                                try {
                                    Send-AzWvdUserSessionMessage -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -SessionHostName $SessionHostName -UserSessionId $SessionID -MessageTitle "$LogOffMessageTitle" -MessageBody "$LogoffMessageBody You will be logged off automatically at '$DeadlineDateTime'."
                                }
                                Catch {
                                    Write-Log "Failed to send a logoff message to user: '$($Session.ActiveDirectoryUserName)', session ID: $SessionID $($PSItem |Format-List -Force | Out-String)"
                                }
                            }
                        }
                    }  
                }               
            }    
        }
    }
    else {
        Write-Log "No currently running VMs to be shut down and or removed."
    }

    if ($vmsToRemove.Count -gt 0) {

        Write-Log "################################"
        Write-Log "## HANDLE VMs SET FOR REMOVAL ##"
        Write-Log "##----------------------------##"
        Write-Log ("Removing [{0}] VMs" -f $vmsToRemove.Count)

        Remove-VirtualMachineByLoop -VmsToRemove $vmsToRemove
    }

    Write-Log "#########################"
    Write-Log "##  SET RG-LEVEL TAGS ##"
    Write-Log "##--------------------##"

    $rgLevelTaggingInput = @{
        ResourceGroupName        = $ResourceGroupName 
        HostPoolName             = $HostPoolName
        TargetImageVersion       = $TargetImageVersion
        ShutDownVMDeadlinePassed = $ShutDownVMDeadlinePassed
    }
    Set-ResourceGroupLifecycleTag @rgLevelTaggingInput
}
Write-Host 'Starting Function'
Update-WVDHostpool -ResourceGroupName 'RG-WVD-Hostpools' -HostPoolName 'Windows10MSFullDesktop' -UtcOffset '-4:00' -LogOffMessageTitle 'Warning' -LogOffMessageBody 'Please logoff' -TargetImageVersion '1.0.0' -LimitSecondsToForceLogOffUser 60 -MaintenanceTagName 'ExemptAutoScale' -LogoffDeadline '202009222200'
