<#
.SYNOPSIS
Sends a console message to all active users on a specific session host or an entire hostpool.

.PARAMETER SessionHostName
Optional. Name of a specific sessionhost. Must be fqdn (i.e., VM1.contoso.com)

.PARAMETER HostPoolName
Mandatory. Name of the hostpool to process

.PARAMETER ResourceGroupName
Mandatory. Resource group of the hostpool to process

.PARAMETER LogOffMessageTitle
Mandatory. Title of the popup the users receive when they get notified of their pending session logoff 

.PARAMETER LogOffMessageBody
Mandatory. Message of the popup the users receive when they get notified of their pending session logoff. The text "You will be automatically logged off at <DeadlineDateTime>." is appended

.EXAMPLE 1
.\send-messagetoUsers.ps1 -HostPoolName 'test-cse-hp' -ResourceGroupName 'WVD-HostPool-01-PO-RG' -MessageTitle 'Kidding' -MessageBody 'Just'
Sends Message to active users on all session hosts in hostpool 'test-cse-hp' located in resourcegroup 'WVD-HostPool-01-PO-RG'

.EXAMPLE 2
.\send-messagetoUsers.ps1 -SessionHostName 'WVD-0.contoso.com' -HostPoolName 'Hostpool1' -ResourceGroupName 'WVD-Hostpool-1_RG' -MessageTitle 'Warning' -MessageBody 'Boss is coming'
Sends a message to active users on 'WVD-0.contoso.com' in 'Hostpool1' located in resourcegroup 'WVD-Hostpool-1_RG'

#>
param
(
    [Parameter(Mandatory=$false)]
    [string] $SessionHostName,

    [Parameter(Mandatory)]
    [string] $HostPoolName,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $MessageTitle,

    [Parameter(Mandatory)]
    [string] $MessageBody
)

Function Send-MessagetoActiveWVDUsers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $SessionHostName,
    
        [Parameter(Mandatory)]
        [string] $HostPoolName,
    
        [Parameter(Mandatory)]
        [string] $ResourceGroupName,
    
        [Parameter(Mandatory)]
        [string] $MessageTitle,
    
        [Parameter(Mandatory)]
        [string] $MessageBody

    )
    Write-Output "------------------------------------------------------"
    Write-Output "[$SessionHostName]: Checking for active user sessions."

    $ActiveUserSessions = Get-AzWvdUserSession -HostPoolName $HostpoolName -ResourceGroupName $ResourceGroupName -SessionHostName $SessionHostName | Where-Object {$_.SessionState -eq 'Active'}
    if (($ActiveUserSessions).Count -gt 0) {
        Write-Output "[$SessionHostName]: There are active user sessions. Sending console message to all active users."
        Foreach ($Session in $ActiveUserSessions) {
            $SplitSessionID = $Session.Id.Split("/")
            $SessionID = $SplitSessionID[$SplitSessionID.Count - 1]
            $UserName = $Session.ActiveDirectoryUserName
            Write-Output "[$SessionHostName]: Sending message to [$UserName]."
            try {
                Send-AzWvdUserSessionMessage -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -SessionHostName $SessionHostName -UserSessionId $SessionID -MessageTitle $MessageTitle -MessageBody $MessageBody
                Write-output "[$SessionHostName]: Message sent to [$UserName] successfully."
            }
            Catch {
                Write-Warning "[$SessionHostName]: Failed to send message to user: '$($UserName)', session ID: $SessionID $($PSItem | Format-List -Force | Out-String)"
            }
        }
    }
    Else {
        Write-Output "[$SessionHostName]: There are no active user sessions on this session host. No messages sent."
    }
}

$HostPool = $null
try {
    Write-Output "Verification: Hostpool: [$HostPoolName] exists in resource group: [$ResourceGroupName]."
    $HostPool = Get-AzWvdHostPool -Name $HostPoolName -ResourceGroupName $ResourceGroupName
    if (-not $HostPool) {
        throw $HostPool
    }
    Write-Output "Verification: Hostpool information verified."
}
catch {
    Write-Warning "Hostpool: [$HostpoolName] does not exist in the resource group: [$ResourceGroupName]. Ensure that you have entered the correct values."
    exit
}

If ($SessionHostName) {
    $SessionHost = $null
    Try {
        Write-Output "Verification: Session host: [$SessionHostName] exists in hostpool: [$HostpoolName]."
        $SessionHost = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -eq "$Hostpoolname/$SessionHostName" }
        If (-not $SessionHost) {
            throw $SessionHost
        }
        Send-MessagetoActiveWVDUsers -SessionHostName $SessionHostName -HostpoolName $HostPoolName -ResourceGroupName $ResourceGroupName -MessageTitle $MessageTitle -MessageBody $MessageBody
    }
    Catch {
        Write-Warning "SessionHost: [$SessionHostName] does not exist in the hostpool: [$HostPoolName] in the resource group: [$ResourceGroupName]."
        exit
    } 
}
Else {
    Write-Output "[$HostpoolName]: Retrieving list of session hosts in hostpool."
    $SessionHosts = Get-AzWvdSessionHost -HostPoolName $HostpoolName -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Sort-Object Name
    if (-not $SessionHosts) {
        Write-Warning "[$HostpoolName]: There are no session hosts in this hostpool."
        exit
    }
    
    ForEach ($SessionHost in $SessionHosts) {
        $SessionHostName = $SessionHost.Name.Split("/")[1]
        Send-MessagetoActiveWVDUsers -SessionHostName $SessionHostName -HostpoolName $HostPoolName -ResourceGroupName $ResourceGroupName -MessageTitle $MessageTitle -MessageBody $MessageBody
    }
}
