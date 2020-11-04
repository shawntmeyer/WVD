# ***************************************************************************
#
# Purpose: WVD Image Prep
#
# ------------- DISCLAIMER -------------------------------------------------
# This script code is provided as is with no guarantee or waranty concerning
# the usability or impact on systems and may be used, distributed, and
# modified in any way provided the parties agree and acknowledge the 
# Microsoft or Microsoft Partners have neither accountabilty or 
# responsibility for results produced by use of this script.
#
# Microsoft will not provide any support through any means.
# ------------- DISCLAIMER -------------------------------------------------
#
# ***************************************************************************
<#
.DESCRIPTION
   Prepare a Windows System either running on Hyper-V or in Azure to be sysprep'd added as a Windows Virtual Desktop image.
   Script can install Office 365 from Microsoft CDN, OneDrive per machine, Teams per machine, FSLogix Agent, and Edge Chromium
   Script will configure each of these items in accordance with reference articles specified in the code below.
   Script will also perform WVD specific and Azure generic image configurations per reference articles.
#>
[CmdletBinding(DefaultParameterSetName = 'Automation')]
Param
(
    #Display Input Form
    [Parameter(ParameterSetName = 'Manual')]
    [switch]$DisplayForm,

    #Determine if Azure MarketPlace Image. If it is then do not complete the generic VHD image prep steps.
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [bool]$MarketPlaceSource = $true,

    #install Office 365
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [bool]$Office365Install = $true,

    # Outlook Email Cached Sync Time, Microsoft Recommendation is 1 month.
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [ValidateSet("Not Configured", "3 days", "1 week", "2 weeks", "1 month", "3 months", "6 months", "12 months", "24 months", "36 months", "60 months", "All")]
    [string]$EmailCacheTime = "Not Configured",

    # Outlook Calendar Sync Mode, Microsoft Recommendation is Primary Calendar Only. See https://support.microsoft.com/en-us/help/2768656/outlook-performance-issues-when-there-are-too-many-items-or-folders-in
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [ValidateSet("Not Configured", "Inactive", "Primary Calendar Only", "All Calendar Folders")]
    [string]$CalendarSync = "Not Configured",

    # Outlook Calendar Sync Months, Microsoft Recommendation is 1 Month. See https://support.microsoft.com/en-us/help/2768656/outlook-performance-issues-when-there-are-too-many-items-or-folders-in
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [ValidateSet("Not Configured", "1", "3", "6", "12")]
    [string]$CalendarSyncMonths = "Not Configured",

    # Install OneDrive per-machine
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [bool]$OneDriveInstall = $true,

    #Azure Active Directory TenantID
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [string]$AADTenantID,

    # Install FSLogix Agent
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [bool]$FSLogixInstall = $true,

    #UNC Paths to FSLogix Profile Disks. Enclose each value in double quotes seperated by a ',' (ex: "\\primary\fslogix","\\failover\fslogix")
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    $FSLogixVHDPath,

    #Install Microsoft Teams in the Per-Machine configuration. Update the $TeamsURL variable to point to the latest version as needed.
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [bool]$TeamsInstall = $true,

    #Install Microsoft Edge Chromium. Update $EdgeURL variable to point to latest version as needed.
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [bool]$EdgeInstall = $true,

    #Disable Windows Update
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [bool]$DisableUpdates,

    #Run Disk Cleanup at end. Will require a reboot before sysprep.
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [bool]$CleanupImage,

    #Remove Built-in Windows Apps
    [Parameter(ParameterSetName = 'Automation', Mandatory = $false)]
    [bool]$RemoveApps = $true
)

#region Initialization
[string]$scriptPath = $MyInvocation.MyCommand.Definition
[string]$scriptName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
[string]$scriptFileName = Split-Path -Path $scriptPath -Leaf
[String]$Script:LogDir = "$($env:SystemRoot)\Logs\ImagePrep"
[string]$Script:LogName = "$ScriptName.log"

#Cleanup Log Directory from Previous Runs
If (Test-Path "$Script:LogDir\$ScriptName.log") { Remove-Item "$Script:LogDir\$ScriptName.log" -Force }
If (Test-Path "$Script:LogDir\LGPO") { Remove-Item -Path "$Script:LogDir\LGPO" -Recurse -Force }

#Update URLs with new releases
[uri]$O365DepToolWebUrl = 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=49117'
[uri]$O365TemplatesWebUrl = 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=49030'
[uri]$OneDriveUrl = "https://go.microsoft.com/fwlink/p/?linkid=2121808"
[uri]$VSRedistUrl = "https://aka.ms/vs/16/release/vc_redist.x64.exe"
[uri]$WebSocketWebUrl = "https://docs.microsoft.com/en-us/azure/virtual-desktop/teams-on-wvd"
[uri]$TeamsWebUrl = "https://docs.microsoft.com/en-us/microsoftteams/teams-for-vdi"
[uri]$FSLogixUrl = "https://aka.ms/fslogix_download"
[uri]$EdgeUpdatesAPIURL = "https://edgeupdates.microsoft.com/api/products?view=enterprise"
#endregion

#region functions
Function Write-Log {
    <#
        .SYNOPSIS
	        Write messages to a log file in CMTrace.exe compatible format or Legacy text file format.
        .DESCRIPTION
	        Write messages to a log file in CMTrace.exe compatible format or Legacy text file format and optionally display in the console.
        .PARAMETER Message
	        The message to write to the log file or output to the console.
        .PARAMETER Severity
	        Defines message type. When writing to console or CMTrace.exe log format, it allows highlighting of message type.
	        Options: 1 = Information (default), 2 = Warning (highlighted in yellow), 3 = Error (highlighted in red)
        .PARAMETER Source
	        The source of the message being logged.
        .PARAMETER ScriptSection
	        The heading for the portion of the script that is being executed. Default is: $script:installPhase.
        .PARAMETER LogType
	        Choose whether to write a CMTrace.exe compatible log file or a Legacy text log file.
        .PARAMETER LogFileDirectory
	        Set the directory where the log file will be saved.
        .PARAMETER LogFileName
	        Set the name of the log file.
        .PARAMETER MaxLogFileSizeMB
	        Maximum file size limit for log file in megabytes (MB). Default is 10 MB.
        .PARAMETER WriteHost
	        Write the log message to the console.
        .PARAMETER ContinueOnError
	        Suppress writing log message to console on failure to write message to log file. Default is: $true.
        .PARAMETER PassThru
	        Return the message that was passed to the function
        .PARAMETER DebugMessage
	        Specifies that the message is a debug message. Debug messages only get logged if -LogDebugMessage is set to $true.
        .PARAMETER LogDebugMessage
	        Debug messages only get logged if this parameter is set to $true in the config XML file.
        .EXAMPLE
	        Write-Log -Message "Installing patch MS15-031" -Source 'Add-Patch' -LogType 'CMTrace'
        .EXAMPLE
	        Write-Log -Message "Script is running on Windows 8" -Source 'Test-ValidOS' -LogType 'Legacy'
        .NOTES
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowEmptyCollection()]
        [string[]]$Message,
        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(1, 3)]
        [int16]$Severity = 1,
        [Parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNull()]
        [string]$Source = '',
        [Parameter(Mandatory = $false, Position = 3)]
        [ValidateSet('CMTrace', 'Legacy')]
        [string]$LogType = "CMTrace",
        [Parameter(Mandatory = $false, Position = 4)]
        [ValidateNotNullorEmpty()]
        [string]$LogFileDirectory = $Script:LogDir,
        [Parameter(Mandatory = $false, Position = 5)]
        [ValidateNotNullorEmpty()]
        [string]$LogFileName = $Script:LogName,
        [Parameter(Mandatory = $false, Position = 6)]
        [ValidateNotNullorEmpty()]
        [decimal]$MaxLogFileSizeMB = 100,
        [Parameter(Mandatory = $false, Position = 7)]
        [ValidateNotNullorEmpty()]
        [boolean]$WriteHost = $true,
        [Parameter(Mandatory = $false, Position = 8)]
        [ValidateNotNullorEmpty()]
        [boolean]$ContinueOnError = $true,
        [Parameter(Mandatory = $false, Position = 9)]
        [switch]$PassThru = $false
    )
	
    Begin {
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		
        ## Logging Variables
        #  Log file date/time
        [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
        [string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
        If (-not (Test-Path -LiteralPath 'variable:LogTimeZoneBias')) { [int32]$script:LogTimeZoneBias = [timezone]::CurrentTimeZone.GetUtcOffset([datetime]::Now).TotalMinutes }
        [string]$LogTimePlusBias = $LogTime + $script:LogTimeZoneBias
        #  Initialize variables
        [boolean]$ExitLoggingFunction = $false
        #  Check if the script section is defined
        [boolean]$Script:SectionDefined = [boolean](-not [string]::IsNullOrEmpty($Script:Section))
        #  Get the file name of the source script
        Try {
            If ($script:MyInvocation.Value.ScriptName) {
                [string]$ScriptSource = Split-Path -Path $script:MyInvocation.Value.ScriptName -Leaf -ErrorAction 'Stop'
            }
            Else {
                [string]$ScriptSource = Split-Path -Path $script:MyInvocation.MyCommand.Definition -Leaf -ErrorAction 'Stop'
            }
        }
        Catch {
            $ScriptSource = ''
        }
		
        ## Create script block for generating CMTrace.exe compatible log entry
        [scriptblock]$CMTraceLogString = {
            Param (
                [string]$lMessage,
                [string]$lSource,
                [int16]$lSeverity
            )
            "<![LOG[$lMessage]LOG]!>" + "<time=`"$LogTimePlusBias`" " + "date=`"$LogDate`" " + "component=`"$lSource`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$lSeverity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
        }
		
        ## Create script block for writing log entry to the console
        [scriptblock]$WriteLogLineToHost = {
            Param (
                [string]$lTextLogLine,
                [int16]$lSeverity
            )
            If ($WriteHost) {
                #  Only output using color options if running in a host which supports colors.
                If ($Host.UI.RawUI.ForegroundColor) {
                    Switch ($lSeverity) {
                        3 { Write-Host -Object $lTextLogLine -ForegroundColor 'Red' -BackgroundColor 'Black' }
                        2 { Write-Host -Object $lTextLogLine -ForegroundColor 'Yellow' -BackgroundColor 'Black' }
                        1 { Write-Host -Object $lTextLogLine }
                    }
                }
                #  If executing "powershell.exe -File <filename>.ps1 > log.txt", then all the Write-Host calls are converted to Write-Output calls so that they are included in the text log.
                Else {
                    Write-Output -InputObject $lTextLogLine
                }
            }
        }
		
        ## Create the directory where the log file will be saved
        If (-not (Test-Path -LiteralPath $LogFileDirectory -PathType 'Container')) {
            Try {
                $null = New-Item -Path $LogFileDirectory -Type 'Directory' -Force -ErrorAction 'Stop'
            }
            Catch {
                [boolean]$ExitLoggingFunction = $true
                #  If error creating directory, write message to console
                If (-not $ContinueOnError) {
                    Write-Host -Object "[$LogDate $LogTime] [${CmdletName}] $Script:Section :: Failed to create the log directory [$LogFileDirectory]. `n$(Resolve-Error)" -ForegroundColor 'Red'
                }
                Return
            }
        }
		
        ## Assemble the fully qualified path to the log file
        [string]$LogFilePath = Join-Path -Path $LogFileDirectory -ChildPath $LogFileName
    }
    Process {
        ## Exit function if logging is disabled
		
        ForEach ($Msg in $Message) {
            ## If the message is not $null or empty, create the log entry for the different logging methods
            [string]$CMTraceMsg = ''
            [string]$ConsoleLogLine = ''
            [string]$LegacyTextLogLine = ''
            If ($Msg) {
                #  Create the CMTrace log message
                If ($Script:SectionDefined) { [string]$CMTraceMsg = "[$Script:Section] :: $Msg" }
				
                #  Create a Console and Legacy "text" log entry
                [string]$LegacyMsg = "[$LogDate $LogTime]"
                If ($Script:SectionDefined) { [string]$LegacyMsg += " [$Script:Section]" }
                If ($Source) {
                    [string]$ConsoleLogLine = "$LegacyMsg [$Source] :: $Msg"
                    Switch ($Severity) {
                        3 { [string]$LegacyTextLogLine = "$LegacyMsg [$Source] [Error] :: $Msg" }
                        2 { [string]$LegacyTextLogLine = "$LegacyMsg [$Source] [Warning] :: $Msg" }
                        1 { [string]$LegacyTextLogLine = "$LegacyMsg [$Source] [Info] :: $Msg" }
                    }
                }
                Else {
                    [string]$ConsoleLogLine = "$LegacyMsg :: $Msg"
                    Switch ($Severity) {
                        3 { [string]$LegacyTextLogLine = "$LegacyMsg [Error] :: $Msg" }
                        2 { [string]$LegacyTextLogLine = "$LegacyMsg [Warning] :: $Msg" }
                        1 { [string]$LegacyTextLogLine = "$LegacyMsg [Info] :: $Msg" }
                    }
                }
            }
			
            ## Execute script block to create the CMTrace.exe compatible log entry
            [string]$CMTraceLogLine = & $CMTraceLogString -lMessage $CMTraceMsg -lSource $Source -lSeverity $Severity
			
            ## Choose which log type to write to file
            If ($LogType -ieq 'CMTrace') {
                [string]$LogLine = $CMTraceLogLine
            }
            Else {
                [string]$LogLine = $LegacyTextLogLine
            }
			
            Try {
                $LogLine | Out-File -FilePath $LogFilePath -Append -NoClobber -Force -Encoding 'UTF8' -ErrorAction 'Stop'
            }
            Catch {
                If (-not $ContinueOnError) {
                    Write-Host -Object "[$LogDate $LogTime] [$Script:Section] [${CmdletName}] :: Failed to write message [$Msg] to the log file [$LogFilePath]. `n$(Resolve-Error)" -ForegroundColor 'Red'
                }
            }
						
            ## Execute script block to write the log entry to the console if $WriteHost is $true
            & $WriteLogLineToHost -lTextLogLine $ConsoleLogLine -lSeverity $Severity
        }
    }
    End {
        ## Archive log file if size is greater than $MaxLogFileSizeMB and $MaxLogFileSizeMB > 0
        Try {
            If ((-not $ExitLoggingFunction) -and (-not $DisableLogging)) {
                [IO.FileInfo]$LogFile = Get-ChildItem -LiteralPath $LogFilePath -ErrorAction 'Stop'
                [decimal]$LogFileSizeMB = $LogFile.Length / 1MB
                If (($LogFileSizeMB -gt $MaxLogFileSizeMB) -and ($MaxLogFileSizeMB -gt 0)) {
                    ## Change the file extension to "lo_"
                    [string]$ArchivedOutLogFile = [IO.Path]::ChangeExtension($LogFilePath, 'lo_')
                    [hashtable]$ArchiveLogParams = @{ ScriptSection = $Script:Section; Source = ${CmdletName}; Severity = 2; LogFileDirectory = $LogFileDirectory; LogFileName = $LogFileName; LogType = $LogType; MaxLogFileSizeMB = 0; WriteHost = $WriteHost; ContinueOnError = $ContinueOnError; PassThru = $false }
					
                    ## Log message about archiving the log file
                    $ArchiveLogMessage = "Maximum log file size [$MaxLogFileSizeMB MB] reached. Rename log file to [$ArchivedOutLogFile]."
                    Write-Log -Message $ArchiveLogMessage @ArchiveLogParams
					
                    ## Archive existing log file from <filename>.log to <filename>.lo_. Overwrites any existing <filename>.lo_ file. This is the same method SCCM uses for log files.
                    Move-Item -LiteralPath $LogFilePath -Destination $ArchivedOutLogFile -Force -ErrorAction 'Stop'
					
                    ## Start new log file and Log message about archiving the old log file
                    $NewLogMessage = "Previous log file was renamed to [$ArchivedOutLogFile] because maximum log file size of [$MaxLogFileSizeMB MB] was reached."
                    Write-Log -Message $NewLogMessage @ArchiveLogParams
                }
            }
        }
        Catch {
            ## If renaming of file fails, script will continue writing to log file even if size goes over the max file size
        }
        Finally {
            If ($PassThru) { Write-Output -InputObject $Message }
        }
    }
}

Function Set-RegistryValue {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        $Value,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Binary', 'DWord', 'ExpandString', 'MultiString', 'None', 'QWord', 'String', 'Unknown')]
        [Microsoft.Win32.RegistryValueKind]$Type = 'String'
    )

    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

    If (-not (Get-ItemProperty -LiteralPath $key -Name $Name -ErrorAction 'SilentlyContinue')) {
        If (-not (Test-Path -LiteralPath $key -ErrorAction 'Stop')) {
            Try {
                Write-Log -Message "Create registry key [$key]." -Source ${CmdletName}
                # No forward slash found in Key. Use New-Item cmdlet to create registry key
                If ((($Key -split '/').Count - 1) -eq 0) {
                    $null = New-Item -Path $key -ItemType 'Registry' -Force -ErrorAction 'Stop'
                }
                # Forward slash was found in Key. Use REG.exe ADD to create registry key
                Else {
                    $null = & reg.exe Add "$($Key.Substring($Key.IndexOf('::') + 2))"
                    If ($global:LastExitCode -ne 0) {
                        Throw "Failed to create registry key [$Key]"
                    }
                }
            }
            Catch {
                Throw
            }
        }
        Write-Log -Message "Set registry key value: [$key] [$name = $value]." -Source ${CmdletName}
        $null = New-ItemProperty -LiteralPath $key -Name $name -Value $value -PropertyType $Type -ErrorAction 'Stop'
    }
    ## Update registry value if it does exist
    Else {
        If ($Name -eq '(Default)') {
            ## Set Default registry key value with the following workaround, because Set-ItemProperty contains a bug and cannot set Default registry key value
            $null = $(Get-Item -LiteralPath $key -ErrorAction 'Stop').OpenSubKey('', 'ReadWriteSubTree').SetValue($null, $value)
        }
        Else {
            Write-Log -Message "Update registry key value: [$key] [$name = $value]." -Source ${CmdletName}
            $null = Set-ItemProperty -LiteralPath $key -Name $name -Value $value -ErrorAction 'Stop'
        }
    }
}

Function Get-InternetUrl {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        [uri]$Url,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$searchstring
    )
    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

    Try {
        Write-Log -Message "Now extracting download URL from '$Url'." -Source ${CmdletName}
        $HTML = Invoke-WebRequest -Uri $Url -UseBasicParsing
        $Links = $HTML.Links
        $ahref = $null
        $ahref=@()
        $ahref = ($Links | Where-Object {$_.href -like "*$searchstring*"}).href
        If ($ahref.count -eq 0 -or $null -eq $ahref) {
            $ahref = ($Links | Where-Object {$_.OuterHTML -like "*$searchstring*"}).href
        }
        If ($ahref.Count -eq 1) {
            Write-Log -Message "Download URL = '$ahref'" -Source ${CmdletName}
            Return $ahref

        }
        Elseif ($ahref.Count -gt 1) {
            Write-Log -Message "Download URL = '$($ahref[0])'" -Source ${CmdletName}
            Return $ahref[0]
        }
    }
    Catch {
        Write-Log -Message "Error Downloading HTML and determining link for download." -Severity 3 -Source ${CmdletName}
        Exit
    }
}

Function Get-InternetFile {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        [uri]$url,
        [Parameter(Mandatory = $false, Position = 1)]
        [string]$outputfile

    )

    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

    $start_time = Get-Date
 
    $wc = New-Object System.Net.WebClient
    Write-Log -Message "Downloading file at '$url' to '$outputfile'." -Source ${CmdletName}
    Try {
        $wc.DownloadFile($url, $outputfile)
    
        $time = (Get-Date).Subtract($start_time).Seconds
        
        Write-Log -Message "Time taken: '$time' seconds." -Source ${CmdletName}
        if (Test-Path -Path $outputfile) {
            $totalSize = (Get-Item $outputfile).Length / 1MB
            Write-Log -message "Download was successful. Final file size: '$totalsize' mb" -Source ${CmdletName}
        }
    }
    Catch {
        Write-Log -Message "Error downloading file. Please check url." -Severity 3 -Source ${CmdletName}
        Exit
    }
}

Function Update-LocalGPOTextFile {
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('Computer', 'User')]
        [string]$scope,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$RegistryKeyPath,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$RegistryValue,
        [Parameter(Mandatory = $true, Position = 3)]
        [string]$RegistryData,
        [Parameter(Mandatory = $true, Position = 4)]
        [ValidateSet('DWORD', 'String')]
        [string]$RegistryType,
        [string]$outputDir = "$Script:LogDir\LGPO",
        [string]$outfileprefix = $Script:Section
    )

    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    # Convert $RegistryType to UpperCase to prevent LGPO errors.
    $ValueType = $RegistryType.ToUpper()
    # Change String type to SZ for text file
    If ($ValueType -eq 'STRING') { $ValueType = 'SZ' }
    # Replace any incorrect registry entries for the format needed by text file.
    $modified = $false
    $SearchStrings = 'HKLM:\', 'HKCU:\', 'HKEY_CURRENT_USER:\', 'HKEY_LOCAL_MACHINE:\'
    ForEach ($String in $SearchStrings) {
        If ($RegistryKeyPath.StartsWith("$String") -and $modified -ne $true) {
            $index = $String.Length
            $RegistryKeyPath = $RegistryKeyPath.Substring($index, $RegistryKeyPath.Length - $index)
            $modified = $true
        }
    }
    
    #Create the output file if needed.
    $Outfile = "$OutputDir\$Outfileprefix-$Scope.txt"
    If (-not (Test-Path -LiteralPath $Outfile)) {
        If (-not (Test-Path -LiteralPath $OutputDir -PathType 'Container')) {
            Try {
                $null = New-Item -Path $OutputDir -Type 'Directory' -Force -ErrorAction 'Stop'
            }
            Catch {}
        }
        $null = New-Item -Path $outputdir -Name "$OutFilePrefix-$Scope.txt" -ItemType File -ErrorAction Stop
    }

    Write-Log -message "Adding registry information to '$outfile' for LGPO.exe" -Source ${CmdletName}
    # Update file with information
    Add-Content -Path $Outfile -Value $Scope
    Add-Content -Path $Outfile -Value $RegistryKeyPath
    Add-Content -Path $Outfile -Value $RegistryValue
    Add-Content -Path $Outfile -Value "$($ValueType):$RegistryData"
    Add-Content -Path $Outfile -Value ""
}

Function Invoke-LGPO {
    Param (
        [string]$InputDir = "$Script:LogDir\LGPO",
        [string]$SearchTerm = "$Script:Section"
    )
    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    Write-Log -message "Gathering Registry text files for LGPO from '$InputDir'" -Source ${CmdletName}
    $InputFiles = Get-ChildItem -Path $InputDir -Filter "$SearchTerm*.txt"
    ForEach ($RegistryFile in $inputFiles) {
        $TxtFilePath = $RegistryFile.FullName
        Write-Log -Message "Now applying settings from '$txtFilePath' to Local Group Policy via LGPO.exe." -Source ${CmdletName}
        $lgpo = Start-Process -FilePath "$PSScriptRoot\LGPO\lgpo.exe" -ArgumentList "/t `"$TxtFilePath`"" -Wait -PassThru -NoNewWindow
        Write-Log -Message "'lgpo.exe' exited with code [$($lgpo.ExitCode)]." -Source ${CmdletName}
    }
}

Function Invoke-CleanMgr {
    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    Write-Log -Message "Now Cleaning image using Disk Cleanup wizard." -Source ${CmdletName}
    $RegKeyParent = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\"
    # Set up array of registry keys
    $RegKeySuffixes = "Active Setup Temp Folders", "BranchCache", "Downloaded Program Files", "GameNewsFiles", "GameStatisticsFiles", "GameUpdateFiles", `
        "Internet Cache Files", "Memory Dump Files", "Offline Pages Files", "Old ChkDsk Files", "Previous Installations", "Recycle Bin", "Service Pack Cleanup", `
        "Setup Log Files", "System error memory dump files", "System error minidump files", "Temporary Files", "Temporary Setup Files", "Temporary Sync Files", `
        "Thumbnail Cache", "Update Cleanup", "Upgrade Discarded Files", "User file versions", "Windows Defender", "Windows Error Reporting Archive Files", `
        "Windows Error Reporting Queue Files", "Windows Error Reporting System Archive Files", "Windows Error Reporting System Queue Files", `
        "Windows ESD installation files", "Windows Upgrade Log Files"
    
    ForEach ($Suffix in $RegKeySuffixes) { Set-RegistryValue -Key "$RegKeyParent$Suffix" -Name StateFlags0100 -Type DWord -Value 2 }
    $null = Start-Process -FilePath cleanmgr.exe -ArgumentList "/sagerun:100" -Wait -PassThru    
}

Function Invoke-ImageCustomization {
    Param
    (
        #Determine if Azure MarketPlace Image. If it is then do not complete the generic VHD image prep steps.
        [Parameter(Mandatory = $false)]
        [bool]$MarketPlaceSource,

        #install Office 365
        [Parameter(Mandatory = $false)]
        [bool]$Office365Install,

        # Outlook Email Cached Sync Time
        [Parameter(Mandatory = $false)]
        [ValidateSet("Not Configured", "3 days", "1 week", "2 weeks", "1 month", "3 months", "6 months", "12 months", "24 months", "36 months", "60 months", "All")]
        [string]$EmailCacheTime = "Not Configured",

        # Outlook Calendar Sync Mode. See https://support.microsoft.com/en-us/help/2768656/outlook-performance-issues-when-there-are-too-many-items-or-folders-in
        [Parameter(Mandatory = $false)]
        [ValidateSet("Not Configured", "Inactive", "Primary Calendar Only", "All Calendar Folders")]
        [string]$CalendarSync = "Not Configured",

        # Outlook Calendar Sync Months. See https://support.microsoft.com/en-us/help/2768656/outlook-performance-issues-when-there-are-too-many-items-or-folders-in
        [Parameter(Mandatory = $false)]
        [ValidateSet("Not Configured", "1", "3", "6", "12")]
        [string]$CalendarSyncMonths = "Not Configured",

        # Install OneDrive per-machine
        [Parameter(Mandatory = $false)]
        [bool]$OneDriveInstall,

        #Azure Active Directory TenantID
        [Parameter(Mandatory = $false)]
        [string]$AADTenantID,

        # Install FSLogix Agent
        [Parameter(Mandatory = $false)]
        [bool]$FSLogixInstall,

        #UNC Paths to FSLogix Profile Disks. Enclose each value in double quotes seperated by a ',' (ex: "\\primary\fslogix","\\failover\fslogix")
        [Parameter(Mandatory = $false)]
        $FSLogixVHDPath,

        #Install Microsoft Teams in the Per-Machine configuration. Update the $TeamsURL variable to point to the latest version as needed.
        [Parameter(Mandatory = $false)]
        [bool]$TeamsInstall,

        #Install Microsoft Edge Chromium. Update $EdgeURL variable to point to latest version as needed.
        [Parameter(Mandatory = $false)]
        [bool]$EdgeInstall,

        #Disable Windows Update
        [Parameter(Mandatory = $false)]
        [bool]$DisableUpdates,

        #Run Disk Cleanup at end. Will require a reboot before sysprep.
        [Parameter(Mandatory = $false)]
        [bool]$CleanupImage,

        #Remove Apps
        [Parameter(Mandatory = $false)]
        [bool]$RemoveApps
    )

    Write-Log -Message "Starting ImagePrep Build Script."
    If (-not(Test-Path "$env:WinDir\Logs\Software")) {
        $null = New-Item -Path $env:WinDir\Logs -Name Software -ItemType Directory -Force
    }

    #region Office365

    If ( $Office365Install ) {
        $Ref = "https://docs.microsoft.com/en-us/azure/virtual-desktop/install-office-on-wvd-master-image"
        $Script:Section = 'Office 365'

        $dirOffice = "$PSScriptRoot\Office365"
        $OfficeDeploymentToolExe = "$DirOffice\OfficeDeploymentTool.exe"
        $O365Setup = "$DirOffice\setup.exe"
        Write-Log -Message "Starting script section: `"$Script:Section`"."
        Write-Log -Message "Downloading Office Deployment Tool and extracting setup.exe"
        $ODTDownloadUrl = Get-InternetUrl -url $O365DepToolWebUrl -searchstring "OfficeDeploymentTool"
        Get-InternetFile -url $ODTDownloadUrl -outputfile $OfficeDeploymentToolExe
        Write-Log -Message "Extracting 'setup.exe' from Office Deployment Tool."
        $null = Start-Process -FilePath $OfficeDeploymentToolExe -ArgumentList "/Extract:$DirOffice /quiet" -Wait
        Write-Log -Message "Downloading, installing and configuring Office 365 per '$ref'."
        $Installer = Start-Process -FilePath "$O365Setup" -ArgumentList "/configure `"$dirOffice\Configuration.xml`"" -Wait -PassThru 
        Write-Log -message "Setup.exe exited with code [$($Installer.ExitCode)]"
        Write-Log -message "Downloading the latest Office 365 ADMX files."
        [string]$dirTemplates = Join-Path -Path $dirOffice -ChildPath 'Templates'
        If (-not (Test-Path $DirTemplates)) {
            $null = New-Item -Path $DirOffice -Name "Templates" -ItemType Directory -Force
        }
        $O365TemplatesExe = "$DirTemplates\AdminTemplates_x64.exe"
        $O365TemplatesUrl = Get-InternetUrl -Url $O365TemplatesWebUrl -searchstring "AdminTemplates_x64"
        Get-InternetFile -url $O365TemplatesUrl -outputfile $O365TemplatesExe
        Write-Log -Message "Extracting the templates to '$DirTemplates'."
        $null = Start-Process -FilePath $O365TemplatesExe -ArgumentList "/extract:$dirTemplates /quiet" -Wait -PassThru
        Write-Log -message "Copying ADMX and ADML files to PolicyDefinitions folder."
        $null = Copy-Item -Path "$DirTemplates\admx\*.admx" -Destination "$env:WINDIR\PolicyDefinitions\" -Force
        $null = Copy-Item -Path "$DirTemplates\admx\en-us\*.adml" -Destination "$env:WINDIR\PolicyDefinitions\en-us" -force -PassThru

        Write-Log -Message "Update User LGPO registry text file."
        # Turn off insider notifications
        Update-LocalGPOTextFile -Scope User -RegistryKeyPath 'Software\policies\microsoft\office\16.0\common' -RegistryValue InsiderSlabBehavior -RegistryType DWord -RegistryData 2

        If (($EmailCacheTime -ne 'Not Configured') -or ($CalendarSync -ne 'Not Configured') -or ($CalendarSyncMonths -ne 'Not Configured')) {
            # Enable Outlook Cached Mode
            Write-Log -Message "Configuring Outlook Cached Mode."
            Update-LocalGPOTextFile -Scope User -RegistryKeyPath 'Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode' -RegistryValue 'Enable' -RegistryType DWord -RegistryData 1
        }
        
        # Cached Exchange Mode Settings: https://support.microsoft.com/en-us/help/3115009/update-lets-administrators-set-additional-default-sync-slider-windows
        If ($EmailCacheTime -eq '3 days') { $SyncWindowSetting = 0; $SyncWindowSettingDays = 3 }
        If ($EmailCacheTime -eq '1 week') { $SyncWindowSetting = 0; $SyncWindowSettingDays = 7 }
        If ($EmailCacheTime -eq '2 weeks') { $SyncWindowSetting = 0; $SyncWindowSettingDays = 14 }
        If ($EmailCacheTime -eq '1 month') { $SyncWindowSetting = 1 }
        If ($EmailCacheTime -eq '3 months') { $SyncWindowSetting = 3 }
        If ($EmailCacheTime -eq '6 months') { $SyncWindowSetting = 6 }
        If ($EmailCacheTime -eq '12 months') { $SyncWindowSetting = 12 }
        If ($EmailCacheTime -eq '24 months') { $SyncWindowSetting = 24 }
        If ($EmailCacheTime -eq '36 months') { $SyncWindowSetting = 36 }
        If ($EmailCacheTime -eq '60 months') { $SyncWindowSetting = 60 }
        If ($EmailCacheTime -eq 'All') { $SyncWindowSetting = 0; $SyncWindowSettingDays = 0 }

        If ($SyncWindowSetting) {
            Update-LocalGPOTextFile -Scope User -RegistryKeyPath 'Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode' -RegistryValue 'SyncWindowSetting' -RegistryType DWORD -RegistryData $SyncWindowSetting
        }
        If ($SyncWindowSettingDays) {
            Update-LocalGPOTextFile -Scope User -RegistryKeyPath 'Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode' -RegistryValue 'SyncWindowSettingDays' -RegistryType DWORD -RegistryData $SyncWindowSettingDays
        }

        # Calendar Sync Settings: https://support.microsoft.com/en-us/help/2768656/outlook-performance-issues-when-there-are-too-many-items-or-folders-in
        If ($CalendarSync -eq 'Inactive') {
            $CalendarSyncWindowSetting = 0 
        }
        If ($CalendarSync -eq 'Primary Calendar Only') {
            $CalendarSyncWindowSetting = 1
        }
        If ($CalendarSync -eq 'All Calendar Folders') {
            $CalendarSyncWindowSetting = 2
        }

        If ($CaldendarSyncWindowSetting) {
            Reg LOAD HKLM\DefaultUser "$env:SystemDrive\Users\Default User\NtUser.dat"
            Set-RegistryValue -Key 'HKLM:\DefaultUser\Software\Policies\Microsoft\Office16.0\Outlook\Cached Mode' -Name CalendarSyncWindowSetting -Type DWord -Value $CalendarSyncWindowSetting
            If ($CalendarSyncMonths -ne 'Not Configured') {
                Set-RegistryValue -Key 'HKCU:\DefaultUser\Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode' -Name CalendarSyncWindowSettingMonths -Type DWord -Value $CalendarSyncMonths
            }
            REG UNLOAD HKLM\DefaultUser
        }
        Write-Log -Message "Update Computer LGPO registry text file."
        $RegistryKeyPath = 'SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate'
        # Hide Office Update Notifications
        Update-LocalGPOTextFile -scope Computer -RegistryKeyPath $RegistryKeyPath -RegistryValue 'HideUpdateNotifications' -RegistryType DWord -RegistryData 1
        # Hide and Disable Updates
        Update-LocalGPOTextFile -Scope Computer -RegistryKeyPath $RegistryKeyPath -RegistryValue 'HideEnableDisableUpdates' -RegistryType DWord -RegistryData 1
        If ($DisableUpdates) {
            # Disable Updates            
            Update-LocalGPOTextFile -Scope Computer -RegistryKeyPath $RegistryKeyPath -RegistryValue 'EnableAutomaticUpdates' -RegistryType DWord -RegistryData 0
        }

        Invoke-LGPO -SearchTerm "$Script:Section"
        Write-Log -Message "Completed the $Script:Section Section"
    }
    #endregion Office 365

    #region OneDrive
    If ( $OneDriveInstall ) {
        $ref = "https://docs.microsoft.com/en-us/azure/virtual-desktop/install-office-on-wvd-master-image"

        $Script:Section = 'OneDrive'
        Write-Log -Message "Starting OneDrive installation and configuration in accordance with '$ref'."

        $output = "$PSScriptRoot\onedrivesetup.exe"
        Get-InternetFile -url $OneDriveURL -outputfile $output

        $OneDriveUninstaller = "$env:WinDir\SysWow64\OneDriveSetup.exe"

        If (Test-Path -Path $OneDriveUninstaller) {
            Write-Log -Message "Uninstalling the OneDrive per-user installations."
            $Uninstaller = Start-Process -FilePath $OneDriveUninstaller -ArgumentList "/uninstall" -wait -PassThru
            Write-Log -Message "OneDriveSetup.exe exited with code [$($Uninstaller.ExitCode)]."
        }
 
        Set-RegistryValue -Key "HKLM:\Software\Microsoft\OneDrive" -Name 'AllUsersInstall' -Value 1 -Type DWord

        Write-Log -message "Starting installation of OneDrive for all users."
 
        $Arguments = "/allusers"
        Write-Log -Message "Trigger installation of file '$output' with switches '$Arguments'"
 
        $Installer = Start-Process -FilePath $output -ArgumentList $Arguments -Wait -PassThru
 
        Write-Log -message "The OneDriveSetup.exe install exited with code [$($Installer.ExitCode)]"

        Write-Log -message "Copying the latest Group Policy ADMX and ADML files to the Policy Definition Folders."

        $InstallDir = "${env:ProgramFiles(x86)}\Microsoft OneDrive"
        $OnedriveVersion = (Get-ItemProperty -Path "$installDir\onedrive.exe").VersionInfo.ProductVersion

        If (Test-Path $installDir\$onedriveversion) {
            $ADMX = (Get-ChildItem "$InstallDir\$OneDriveVersion" -include '*.admx' -recurse)
            ForEach ($file in $ADMX) {
                $null = Copy-Item -Path $file.FullName -Destination "$env:Windir\PolicyDefinitions" -Force
            }

            $ADML = (get-childitem "$InstallDir\$OneDriveVersion" -include '*.adml' -recurse | Where-object { $_.Directory -like '*adm' })
            ForEach ($file in $ADML) {
                $null = Copy-Item -Path $file.FullName -Destination "$env:Windir\PolicyDefinitions\en-us" -Force
            }
        }
        Write-Log -message "Now configuring OneDrive to start in the background for each user."
        Set-RegistryValue -Key "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name 'OneDrive' -Value '"C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe" /background' -Type String
        Write-Log -message "Now configuring OneDrive to start in the background when apps accessed through Remote App."
        Set-RegistryValue -Key "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RailRunonce" -Name 'OneDrive' -Value '"C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe" /background' -Type String
        Write-Log -Message "Now Configuring the Update Ring to Production"
        Update-LocalGPOTextFile -Scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\OneDrive' -RegistryValue 'GPOSetUpdateRing' -RegistryType DWORD -RegistryData 5
        Write-Log -Message "Now Configuring OneDrive to automatically sign-in with logged on user credentials."
        Update-LocalGPOTextFile -scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\OneDrive' -RegistryValue 'SilentAccountConfig' -RegistryType DWord -RegistryData 1
        Write-Log -Message "Enabling Files on Demand"
        Update-LocalGPOTextFile -Scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\OneDrive' -RegistryValue 'FilesOnDemandEnabled' -RegistryType DWORD -RegistryData 1
        If ($AADTenantID -and $AADTenantID -ne '') {
            Write-Log -message "Applying OneDrive for Business Known Folder Move Silent Configuration Settings."
            Update-LocalGPOTextFile -Scope Computer -RegistryKeyPath "SOFTWARE\Policies\Microsoft\OneDrive" -RegistryValue 'KFMSilentOptIn' -RegistryType String -RegistryData "$AADTenantID"
        }
        Invoke-LGPO -SearchTerm "$Script:Section"
        Write-Log -Message "Complete $Script:Section Section."
    }

    #endregion OneDrive

    #region Teams

    If ( $TeamsInstall ) {
        # Download and install Microsoft Teams 
        $ref = "https://docs.microsoft.com/en-us/azure/virtual-desktop/teams-on-wvd"
        # Link to downloads: https://docs.microsoft.com/en-us/microsoftteams/teams-for-vdi#deploy-the-teams-desktop-app-to-the-vm

        $Script:Section = 'Teams'

        Write-Log -Message "Starting Teams Installation and Configuration in accordance with '$ref'."
        $VSRedist = "$PSScriptRoot\VSRedist.exe"
        Write-Log -Message "Downloading Visual Studio Redistributable Installer."
        Get-InternetFile -url $VSRedistUrl -outputfile $VSRedist

        Write-Log -Message "Downloading the latest Websocket Service Installer."
        $WebSocketMSI = "$PSScriptRoot\Websocket.msi"
        $WebSocketUrl = Get-InternetUrl -Url $WebSocketWebUrl -searchstring "WebSocket Service"
        Get-InternetFile -url $WebSocketUrl -outputfile $WebSocketMSI

        Write-Log -Message "Now downloading the latest Teams 64-bit installer."
        $TeamsMSI = "$PSScriptRoot\Teams_Windows_x64.msi"
        $TeamsUrl = Get-InternetUrl -URL $TeamsWebUrl -searchstring "Teams_windows_x64.msi"
        Get-InternetFile -url $TeamsUrl -outputfile $TeamsMSI
 
        Write-Log -message "Installing the latest VS Redistributables"
        $Arguments = "/install /quiet /norestart"
        Write-Log -message "Running `"$VSRedist $Arguments`"."
        $Installer = Start-Process -FilePath $VSRedist -ArgumentList $Arguments -Wait -PassThru
        Write-Log -message "The exit code is $($Installer.ExitCode)"

        Write-Log -message "Installating the WebSocket Service."
        $Arguments = "/i `"$WebsocketMSI`" /l*v `"$env:WinDir\Logs\Software\WebSocket_MSI.log`" /quiet"
        Write-Log -message "Running 'msiexec.exe $Arguments'"
        $Installer = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru
        Write-Log -message "The exit code is $($Installer.ExitCode)"

        Set-RegistryValue -Key "HKLM:\Software\Microsoft\Teams" -Name IsWVDEnvironment -Value 1 -Type DWord

        Write-Log -message "Starting installation of Microsoft Teams for all users."
        $Arguments = "/i `"$TeamsMSI`" /l*v `"$env:WinDir\Logs\Software\Teams_MSI.log`" ALLUSER=1 ALLUSERS=1" 
        Write-Log -message "Running 'msiexec.exe $Arguments'"
        $Installer = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -PassThru
        Write-Log -message "'msiexec.exe' exited with code [$($Installer.ExitCode)]."

        <# Create run key in default user hive to delete Teams Shortcuts. Look to delete this later.
        Reg LOAD HKLM\DefaultUser "$env:SystemDrive\Users\Default User\NtUser.dat"
        $Key = "HKLM:\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Run"
        $ValueName = "Delete_Teams_Shortcuts"
        $Value = "Powershell.exe -NoProfile -WindowStyle Hidden -command `"& {`$Desktop=[environment]::GetFolderPath('Desktop');Remove-Item -Path `$Desktop\* -filter 'Microsoft Teams*.*'}`""
        Set-RegistryValue -Key $Key -Name $ValueName -Value $Value -Type 'String'
        Reg Unload HKLM\DefaultUser
        
        #>
        
        Write-Log -message "Completed $Script:Section Section."
    }

    #endregion

    #region FSLogix Agent

    If ($FSLogixInstall) {
        $Script:Section = 'FSLogix Agent'
        Write-Log -message "Starting FSLogix Agent Installation and Configuration."
        Write-Log -message "Downloading FSLogix Agent from Microsoft."
        $output = "$PSScriptRoot\fslogix.zip"
        Get-InternetFile -url $FSLogixUrl -outputfile $output
        Write-Log -message "Extracting FSLogix Agent from zip."
        $destpath = "$PSScriptRoot\FSLogix"
        Expand-Archive $output -DestinationPath $destpath -Force
        Start-Sleep -Seconds 5
        Write-Log -message "Now copying the latest Group Policy ADMX and ADML files to the Policy Definition Folders."
        $admx = Get-ChildItem "$destpath" -Filter "*.admx" -Recurse
        $adml = Get-ChildItem "$destpath" -filter "*.adml" -Recurse
        ForEach ($file in $admx) {
            $null = Copy-item -Path $file.fullname -Destination "$env:Windir\PolicyDefinitions" -Force
        }
        ForEach ($file in $adml) {
            $null = Copy-item -Path $file.fullname -Destination "$env:Windir\PolicyDefinitions\en-us" -Force
        }
        $Installer = "$PSScriptRoot\fslogix\x64\release\fslogixappssetup.exe"
        If (Test-Path $Installer) {
            Write-Log -Message "Installation File: '$installer' successfully extracted."
        }

        $Arguments = "/quiet"
        Write-Log -Message "Now starting FSLogix Agent installation with command line: '$installer $Arguments'."

        $Install = Start-Process -FilePath $Installer -ArgumentList "$Arguments" -Wait -PassThru

        Write-Log -message "The fslogixappssetup.exe exit code is [$($Install.ExitCode)]."

        Write-Log -Message "Now performing FSLogix Configuration if enabled."
        $RegistryKey = 'HKLM:\Software\FSLogix\Profiles'

        if ( $FSLogixVHDPath -and $FSLogixVHDPath -ne '' ) {
            Write-Log -Message "Enabling FSLogix Profile Container in Registry"
            Set-RegistryValue -Key $RegistryKey -Name 'Enabled' -Value 1 -Type DWord
            Write-Log -Message "Setting VHDLocation to '$FSLogixVHDPath' in registry."
            Set-RegistryValue -Key $RegistryKey -Name 'VHDLocations' -Value $FSLogixVHDPath -Type MultiString
            Add-MpPreference -ExclusionPath $FSLogixVHDPath
            Write-Log -Message "Configuring VHD Folder name to begin with username instead of SID"
            Set-RegistryValue -Key $RegistryKey -Name 'FlipFlopProfileDirectoryName' -Value 1 -Type DWord
            Write-Log -Message "Configuring FSLogix Office Container to include Office Activation Information."
            Update-LocalGPOTextFile -Scope Computer -RegistryKeyPath 'Software\Policies\FSLogix\ODFC' -RegistryValue IncludeOfficeActivation -RegistryType DWord -RegistryData 1
        }
        Invoke-LGPO -SearchTerm "$Script:Section"
        Write-Log -Message "Completed $Script:Section script section."
    }

    #endregion FSLogix Agent

    #region Edge Enterprise
    If ( $EdgeInstall ) {

        $Script:Section = 'Edge Enterprise'
        $ref = 'https://docs.microsoft.com/en-us/deployedge/deploy-edge-with-configuration-manager'
        # Disable Edge Updates
        Write-Log -Message "Starting Microsoft Edge Enterprise Installation and Configuration in accordance with '$ref'."

        $dirTemplates = "$PSScriptRoot\Edge\Templates"
        Write-Log -message "Now downloading latest Edge installer and Administrative Templates."

        $EdgeUpdatesJSON = Invoke-WebRequest -Uri $EdgeUpdatesAPIURL -UseBasicParsing
        $content = $EdgeUpdatesJSON.content | ConvertFrom-Json
        $policyfiles = ($content | Where-Object {$_.Product -eq 'Policy'}).releases    
        $latestpolicyfiles = $policyfiles | Sort-Object ProductVersion | Select-Object -last 1        
        $EdgeTemplatesUrl = ($latestpolicyfiles.artifacts | Where-Object {$_.location -like '*.zip'}).Location         
        $Edgereleases = ($content | Where-Object {$_.Product -eq 'Stable'}).releases
        $latestrelease = $Edgereleases | Where-Object {$_.Platform -eq 'Windows' -and $_.Architecture -eq 'x64'} | Sort-Object ProductVersion | Select-Object -last 1
        $EdgeUrl = $latestrelease.artifacts.location
                
        $templateszip = "$PSScriptRoot\MicrosoftEdgePolicyTemplates.zip"
        Get-InternetFile -url $EdgeTemplatesUrl -outputfile $templateszip
        $destPath = "$PSScriptRoot\EdgeTemplates"
        Expand-Archive $templateszip -DestinationPath $destpath -Force
        $msifile = "$PSScriptRoot\MicrosoftEdgeEnteprisex64.msi"
        Get-InternetFile -url $EdgeUrl -outputfile $msifile
        Write-Log -message "Now copying the latest Group Policy ADMX and ADML files to the Policy Definition Folders."
        $admx = Get-ChildItem "$destpath" -Filter "*.admx" -Recurse
        $adml = Get-ChildItem "$destpath" -filter "*.adml" -Recurse
        ForEach ($file in $admx) {
            $null = Copy-item -Path $file.fullname -Destination "$env:Windir\PolicyDefinitions" -Force
        }
        ForEach ($file in $adml) {
            $null = Copy-item -Path $file.fullname -Destination "$env:Windir\PolicyDefinitions\en-us" -Force
        }
        Write-Log -Message "Disabling Edge Desktop shortcut creation via policy."
        Update-LocalGPOTextFile -scope 'Computer' -RegistryKeyPath 'Software\Policies\Microsoft\EdgeUpdate' -RegistryValue 'CreateDesktopShortcutDefault' -RegistryType DWORD -RegistryData 0
        If ($DisableUpdates) {
            Write-Log -Message "Now disabling Edge Automatic Updates via policy."
            Update-LocalGPOTextFile -scope 'Computer' -RegistryKeyPath 'Software\Policies\Microsoft\EdgeUpdate' -RegistryValue 'UpdateDefault' -RegistryType DWORD -RegistryData 0
        }
        Invoke-LGPO -SearchTerm "$Script:Section"
        $installer = "msiexec.exe"
        Write-Log -message "Starting installation of Microsoft Edge Enterprise."
        $Arguments = "/i `"$msifile`" /q" 
        Write-Log -message "Running '$installer $Arguments'"
        $Install = Start-Process -FilePath "$installer" -ArgumentList $Arguments -Wait -PassThru
        Write-Log -message "'$installer' exit code is [$($Install.ExitCode)]."
        Write-Log -Message "Complete $Script:Section script section."

    }

    #endregion Edge Enterprise

    #region Workplace Join

    $Script:Section = 'WorkPlace Join'
    Write-Log -message "Now disabling Workplace Join to prevent issue with Office Activation."
    # Block domain joined machines from inadvertently getting Azure AD registered by users.
    Set-RegistryValue -Key 'HKLM:\Software\Policies\Microsoft\Windows\WorkplaceJoin' -Name BlockAADWorkplaceJoin -Type DWord -Value 1

    #endregion

    #region RemoveApps
    If ($RemoveApps) {
        $Script:Section = 'Remove Apps'
        Write-Log -message "Now Removing Built-in Windows Apps."
        & "$PSScriptRoot\RemoveApps\Remove-Apps.ps1"
        $Script:Section = 'Start Menu'
        $Destination = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell\Layoutmodification.xml"
        Write-Log -message "Setting 'SpecialRoamingOverride' Registry Key per 'https://docs.microsoft.com/en-us/windows-server/storage/folder-redirection/deploy-roaming-user-profiles#step-7-optionally-specify-a-start-layout-for-windows-10-pcs'"
        Set-RegistryValue -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer' -Name 'SpecialRoamingOverrideAllowed' -Value '1' -Type 'DWord'
        Write-Log -message "Replacing default Start Menu layout with custom layoutmodification file due to app removal."
        If ($Office365Install) {
            $LayoutFile = "$PSScriptRoot\StartMenu\StartLayout-Office.xml"
            If (Test-Path $LayoutFile) {
                Write-Log -Message "Importing new Start Menu Layout with Office Group."
                $null = Copy-Item -Path "$LayoutFile" -Destination "$Destination" -Force -ErrorAction SilentlyContinue
            }
        }
        Else {
            $LayoutFile = "$PSScriptRoot\StartMenu\StartLayout-NoOffice.xml"
            If (Test-Path $LayoutFile) {
                Write-Log -Message "Importing new Start Menu Layout."
                $null = Copy-Item -Path "$LayoutFile" -Destination "$Destination" -Force -ErrorAction SilentlyContinue
            }
        }
    }  
    #endregion

    #region WVD Image Settings

    $Script:Section = 'WVD Image Settings'

    $ref = "https://docs.microsoft.com/en-us/azure/virtual-desktop/set-up-customize-master-image"

    Write-Log -message "Now starting to apply $Script:Section in accordance with '$ref'."

    If ($DisableUpdates) {
        Write-Log -message "Disabling Windows Updates via Group Policy setting"
        Update-LocalGPOTextFile -scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -RegistryValue 'NoAutoUpdate' -RegistryType 'Dword' -RegistryData 1
    }
    Write-Log -message "Enabling Time Zone Redirection from Client to Session Host."
    Update-LocalGPOTextFile -scope Computer -RegistryKeyPath "SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -RegistryValue 'fEnableTimeZoneRedirection' -RegistryType 'DWord' -RegistryData 1
    Write-Log -message "Disabling Storage Sense GPO"
    Update-LocalGPOTextFile -Scope Computer -RegistryKeyPath 'Software\Policies\Microsoft\Windows\StorageSense' -RegistryValue 'AllowStorageSenseGlobal' -RegistryType 'DWord' -RegistryData 0
    Write-Log -message "Allow Telemetry in Feedback Hub for Windows 10 Multi-Session."
    Update-LocalGPOTextFile -Scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\Windows\DataCollection' -RegistryValue 'AllowTelemetry' -RegistryType 'DWord' -RegistryData 3
    # Fix issues with Doctor Watson Crashes
    # List of Registry Values from https://docs.microsoft.com/en-us/windows/win32/wer/wer-settings
    Write-Log -Message "Removing Corporate Windows Error Reporting Server if set in registry."
    $RegValues = "CorporateWERDirectory", "CorporateWERPortNumber", "CorporateWERServer", "CorporateWERUseAuthentication", "CorporateWERUseSSL"
    $RegPath = "HKLM:\Software\Microsoft\Windows\Windows Error Reporting"
    ForEach ($value in $regvalues) {
        If (Get-ItemProperty $RegPath -name $value -ErrorAction SilentlyContinue) {
            Remove-ItemProperty $RegPath -Name $Value -Force -ErrorAction SilentlyContinue
        }
    }

    # Fix 5k resolution support
    Write-Log -Message "Fixing 5K Resolution Support"

    $RegistryKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
    Set-RegistryValue -Key $RegistryKey -Name MaxMonitors -Type DWord -Value 4
    Set-RegistryValue -Key $RegistryKey -Name MaxXResolution -Type DWord -Value 5120
    Set-RegistryValue -Key $RegistryKey -Name MaxYResolution -Type DWord -Value 2880
    $RegistryKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\rdp-sxs"
    Set-RegistryValue -Key $RegistryKey -Name MaxMonitors -Type DWord -Value 4
    Set-RegistryValue -Key $RegistryKey -Name MaxXResolution -Type DWord -Value 5120
    Set-RegistryValue -Key $RegistryKey -Name MaxYResolution -Type DWord -Value 2880

    Invoke-LGPO -SearchTerm "$Script:Section"
    Write-Log -message "Completed $Script:Section script section."

    #endregion

    #region Generic VHD Image Prep

    If (!$MarketPlaceSource) {
        $Script:Section = 'Azure VHD Image Settings'

        # The following steps are from: https://docs.microsoft.com/en-us/azure/virtual-machines/windows/prepare-for-upload-vhd-image
        Write-Log -Message "Performing Configuration spelled out in 'https://docs.microsoft.com/en-us/azure/virtual-machines/windows/prepare-for-upload-vhd-image'."
    
        # Remove the WinHTTP proxy
        netsh winhttp reset proxy
    
        # Set Coordinated Universal Time (UTC) time for Windows and the startup type of the Windows Time (w32time) service to Automatically
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name RealTimeIsUniversal -Value 1 -Type DWord
        Set-Service -Name w32time -StartupType Automatic
    
        # Set the power profile to the High Performance
        powercfg /setactive SCHEME_MIN
    
        # Make sure that the environment variables TEMP and TMP are set to their default values
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name 'TEMP' -Value "%SystemRoot%\TEMP" -Type ExpandString
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name 'TMP' -Value "%SystemRoot%\TEMP" -Type ExpandString
    
        # Set Windows services to defaults
        Get-Service -Name bfe | Where-Object { $_.StartType -ne 'Automatic' } | Set-Service -StartupType 'Automatic'
        Get-Service -Name dhcp | Where-Object { $_.StartType -ne 'Automatic' } | Set-Service -StartupType 'Automatic'
        Get-Service -Name dnscache | Where-Object { $_.StartType -ne 'Automatic' } | Set-Service -StartupType 'Automatic'
        Get-Service -Name IKEEXT | Where-Object { $_.StartType -ne 'Automatic' } | Set-Service -StartupType 'Automatic'
        Get-Service -Name iphlpsvc | Where-Object { $_.StartType -ne 'Automatic' } | Set-Service -StartupType 'Automatic'
        Get-Service -Name netlogon | Where-Object { $_.StartType -ne 'Manual' } | Set-Service -StartupType 'Manual'
        Get-Service -Name netman | Where-Object { $_.StartType -ne 'Manual' } | Set-Service -StartupType 'Manual'
        Get-Service -Name nsi | Where-Object { $_.StartType -ne 'Automatic' } | Set-Service -StartupType 'Automatic'
        Get-Service -Name TermService | Where-Object { $_.StartType -ne 'Manual' } | Set-Service -StartupType 'Manual'
        Get-Service -Name MpsSvc | Where-Object { $_.StartType -ne 'Automatic' } | Set-Service -StartupType 'Automatic'
        Get-Service -Name RemoteRegistry | Where-Object { $_.StartType -ne 'Automatic' } | Set-Service -StartupType 'Automatic'
    
        # Ensure RDP is enabled
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Type DWord
        Update-LocalGPOTextFile -Scope Computer -RegistryKeyPath 'Software\Policies\Microsoft\Windows NT\Terminal Services' -RegistryValue fDenyTSConnections -RegistryType DWord -RegistryData 0
    
        # Set RDP Port to 3389 - Unnecessary for WVD due to reverse connect, but helpful for backdoor administration with a jump box
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "PortNumber" -Value 3389 -Type DWord
    
        # Listener is listening on every network interface
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "LanAdapter" -Value 0 -Type DWord
    
        # Configure NLA
        # require user authentication for remote connections to the RD Session Host server by using Network Level Authentication
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "UserAuthentication" -Value 1 -Type DWord
        # Enforce the strongest security layer supported by the client
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "SecurityLayer" -Value 1 -Type DWord
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "fAllowSecProtocolNegotiation" -Value 1 -Type DWord
    
        # Set RDP keep-alive value
        Update-LocalGPOTextFile -scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -RegistryValue 'KeepAliveEnable' -RegistryType DWord -RegistryData 1
        Update-LocalGPOTextFile -scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -RegistryValue 'KeepAliveInterval' -RegistryType DWord -RegistryData 1
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "KeepAliveTimeout" -Value 1 -Type DWord
    
        # Reconnect
        Update-LocalGPOTextFile -Scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -RegistryValue fDisableAutoReconnect -RegistryType DWord -RegistryData 0
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "fInheritReconnectSame" -Value 1 -Type DWord
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "fReconnectSame" -Value 0 -Type DWord
    
        # Limit number of concurrent sessions
        Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "MaxInstanceCount" -Value 4294967295 -Type DWord
    
        # Remove any self signed certs
        if ((Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp').Property -contains "SSLCertificateSHA1Hash") {
            Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "SSLCertificateSHA1Hash" -Force
        }
    
        # Turn on Firewall
        Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True
        $ConnectedAdapters = get-ciminstance -classname "win32_networkadapter" -filter "netconnectionstatus = 2"
        ForEach ($Adapter in $ConnectedAdapters) {
            $InterfaceAlias = $Adapter.NetConnectionID
            If ((Get-NetConnectionProfile -InterfaceAlias $InterfaceAlias).NetworkCategory -eq 'Public') {
                Set-NetConnectionProfile -InterfaceAlias $InterfaceAlias -NetworkCategory Private
            }
        }
    
        # Allow WinRM
        Set-RegistryValue -Key 'HKLM:\System\CurrentControlSet\Services\WinRM' -Name Start -Value 2 -Type DWord
        #Start-Service -Name WinRM
        Enable-PSRemoting -force
        Set-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -Enabled True
    
        # Allow RDP
        Set-NetFirewallRule -DisplayGroup "Remote Desktop" -Enabled True
    
        # Enable File and Printer sharing for ping
        Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -Enabled True
    
        New-NetFirewallRule -DisplayName "AzurePlatform" -Direction Inbound -RemoteAddress 168.63.129.16 -Profile Any -Action Allow -EdgeTraversalPolicy Allow
        New-NetFirewallRule -DisplayName "AzurePlatform" -Direction Outbound -RemoteAddress 168.63.129.16 -Profile Any -Action Allow
    
        Invoke-LGPO -SearchTerm "$Script:Section"
    
        Write-Log -message "Completed $Script:Section script section."

    }
    #endregion
    #region VDI Optimizations
    If ($VDOptimization) {
        $Script:Section = 'VDI Optimizations'

        Write-Log -message "Starting '$Script:Section' script section."
        Write-Log -message "Applying selective settings from the Virtual Desktop Optimization Tool available at https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool"

    }
    #endregion
    $Script:Section = 'Cleanup'
    Write-Log -message "Outputing Group Policy Results and Local GPO Backup to '$Script:LogDir\LGPO'"
    $null = Start-Process -FilePath gpresult.exe -ArgumentList "/h `"$Script:LogDir\LGPO\LocalGroupPolicy.html`"" -Wait
    $null = Start-Process -FilePath "$PSScriptRoot\LGPO\lgpo.exe" -ArgumentList "/b `"$Script:LogDir\LGPO`" /n `"WVD Image Local Group Policy Settings`"" -Wait
    If ( $CleanupImage ) {
        Write-Log -message "Performing system cleanup activities spelled out in 'https://docs.microsoft.com/en-us/windows-server/remote/remote-desktop-services/rds-vdi-recommendations-2004'."
        Get-ChildItem -Path c:\ -Include *.tmp, *.dmp, *.etl, *.evtx, thumbcache*.db, *.log -File -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
        Remove-Item -Path $env:ProgramData\Microsoft\Windows\WER\Temp\* -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $env:ProgramData\Microsoft\Windows\WER\ReportArchive\* -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $env:ProgramData\Microsoft\Windows\WER\ReportQueue\* -Recurse -Force -ErrorAction SilentlyContinue
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Clear-BCCache -Force -ErrorAction SilentlyContinue
    }
    Write-Log -message "$scriptFileName completed."
    Remove-Item "$PSScriptRoot\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$PSScriptRoot" -Recurse -force -ErrorAction SilentlyContinue
}

#endregion

If ($DisplayForm) {
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $DropdownArraySyncMonths = @(
        'Not Configured', '1', '2', '6', '12'
    )

    $DropdownArrayEmailCacheSync = @(
        'Not Configured', '3 days', '1 week', '2 weeks', '1 month', '3 months', '6 months', '12 months', '24 months', '36 months', '60 months', 'All'
    )

    $DropdownArrayCalSyncMode = @(
        'Not Configured', 'Inactive', 'Primary Calendar Only', 'All Calendar Folders'
    )

    $WVDGoldenImagePrep = New-Object system.Windows.Forms.Form
    $WVDGoldenImagePrep.ClientSize = '700,800'
    $WVDGoldenImagePrep.text = "WVD Image Preparation"
    $WVDGoldenImagePrep.TopMost = $false
    $WVDGoldenImagePrep.StartPosition = "CenterScreen"

    $Execute = New-Object system.Windows.Forms.Button
    $Execute.BackColor = "#417505"
    $Execute.text = "Execute"
    $Execute.width = 655
    $Execute.height = 60
    $Execute.location = New-Object System.Drawing.Point(20, 670)
    $Execute.Font = 'Microsoft Sans Serif,18,style=Bold'
    $Execute.ForeColor = "#ffffff"
    $Execute.Add_Click( {
            $Office365Install = $InstallOffice365.Checked
            $EmailCacheTime = $EmailCacheMonths.text
            $CalendarSync = $CalendarSyncMode.text
            $CalendarSyncMonths = $CalSyncTime.text
            $OneDriveInstall = $InstallOneDrive.Checked
            If ($TenantID.text -ne '') {
                $AADTenantID = $TenantID.text
            }
            $FSLogixInstall = $InstallFSLogix.Checked
            If ($VHDPath.text -ne '') {
                $FSLogixVHDPath = $VHDPath.text
            }
            $TeamsInstall = $InstallTeams.Checked
            $EdgeInstall = $InstallEdge.Checked
            $DisableUpdates = $DisableWU.Checked
            $CleanupImage = $RunCleanMgr.Checked
            $RemoveApps = $AppRemove.Checked
            $WVDGoldenImagePrep.Close()
            Invoke-ImageCustomization `
                -Office365Install $Office365Install -EmailCacheTime $EmailCacheTime -CalendarSync $CalendarSync -CalendarSyncMonths $CalendarSyncMonths `
                -OneDriveInstall $OneDriveInstall -AADTenantID $AADTenantID `
                -FSLogixInstall $FSLogixInstall -FSLogixVHDPath $FSLogixVHDPath `
                -TeamsInstall $TeamsInstall `
                -EdgeInstall $EdgeInstall `
                -DisableUpdates $DisableUpdates `
                -CleanupImage $CleanupImage `
                -RemoveApps $RemoveApps
        })

    $ScriptTitle = New-Object system.Windows.Forms.Label
    $ScriptTitle.text = "WVD Golden Image Preparation"
    $ScriptTitle.AutoSize = $true
    $ScriptTitle.width = 25
    $ScriptTitle.height = 10
    $ScriptTitle.location = New-Object System.Drawing.Point(40, 40)
    $ScriptTitle.Font = 'Microsoft Sans Serif,30,style=Bold'

    $InstallOffice365 = New-Object system.Windows.Forms.CheckBox
    $InstallOffice365.text = "Install Office 365 ProPlus"
    $InstallOffice365.AutoSize = $false
    $InstallOffice365.width = 300
    $InstallOffice365.height = 30
    $InstallOffice365.location = New-Object System.Drawing.Point(30, 140)
    $InstallOffice365.Font = 'Microsoft Sans Serif,14'

    $InstallOffice365.Add_CheckStateChanged( {
            $EmailCacheMonths.Enabled = $InstallOffice365.Checked
            $CalendarSyncMode.Enabled = $InstallOffice365.Checked
            $CalSyncTime.Enabled = $InstallOffice365.Checked
        })

    $labelEmailCache = New-Object system.Windows.Forms.Label
    $labelEmailCache.text = "Cache email for:"
    $labelEmailCache.AutoSize = $true
    $labelEmailCache.width = 25
    $labelEmailCache.height = 10
    $labelEmailCache.location = New-Object System.Drawing.Point(46, 170)
    $labelEmailCache.Font = 'Microsoft Sans Serif,12'

    $EmailCacheMonths = New-Object system.Windows.Forms.ComboBox
    $EmailCacheMonths.text = "1 month"
    $EmailCacheMonths.width = 180
    $EmailCacheMonths.height = 29
    $EmailCacheMonths.location = New-Object System.Drawing.Point(46, 200)
    $EmailCacheMonths.Font = 'Microsoft Sans Serif,12'
    $EmailCacheMonths.Enabled = $false

    $labelCalSyncType = New-Object system.Windows.Forms.Label
    $labelCalSyncType.text = "Cal Sync Type"
    $labelCalSyncType.AutoSize = $true
    $labelCalSyncType.width = 25
    $labelCalSyncType.height = 10
    $labelCalSyncType.location = New-Object System.Drawing.Point(250, 170)
    $labelCalSyncType.Font = 'Microsoft Sans Serif,12'

    $CalendarSyncMode = New-Object system.Windows.Forms.ComboBox
    $CalendarSyncMode.text = "Primary Calendar Only"
    $CalendarSyncMode.width = 180
    $CalendarSyncMode.height = 29
    $CalendarSyncMode.location = New-Object System.Drawing.Point(250, 200)
    $CalendarSyncMode.Font = 'Microsoft Sans Serif,12'
    $CalendarSyncMode.Enabled = $false

    $labelCalSyncTime = New-Object system.Windows.Forms.Label
    $labelCalSyncTime.text = "Cal Sync Months"
    $labelCalSyncTime.AutoSize = $true
    $labelCalSyncTime.width = 25
    $labelCalSyncTime.height = 10
    $labelCalSyncTime.location = New-Object System.Drawing.Point(450, 170)
    $labelCalSyncTime.Font = 'Microsoft Sans Serif,12'

    $CalSyncTime = New-Object system.Windows.Forms.ComboBox
    $CalSyncTime.text = "1"
    $CalSyncTime.width = 180
    $CalSyncTime.height = 29
    $CalSyncTime.location = New-Object System.Drawing.Point(450, 200)
    $CalSyncTime.Font = 'Microsoft Sans Serif,12'
    $CalSyncTime.Enabled = $false

    $InstallFSLogix = New-Object system.Windows.Forms.CheckBox
    $InstallFSLogix.text = "Install FSLogix Agent"
    $InstallFSLogix.AutoSize = $false
    $InstallFSLogix.width = 250
    $InstallFSLogix.height = 30
    $InstallFSLogix.location = New-Object System.Drawing.Point(30, 240)
    $InstallFSLogix.Font = 'Microsoft Sans Serif,14'

    $InstallFSLogix.Add_CheckStateChanged( {
            $VHDPath.Enabled = $InstallFSLogix.Checked
        })

    $LabelVHDLocation = New-Object system.Windows.Forms.Label
    $LabelVHDLocation.text = "FSLogix VHD Location"
    $LabelVHDLocation.AutoSize = $true
    $LabelVHDLocation.width = 25
    $LabelVHDLocation.height = 20
    $LabelVHDLocation.location = New-Object System.Drawing.Point(46, 270)
    $LabelVHDLocation.Font = 'Microsoft Sans Serif,12'

    $VHDPath = New-Object system.Windows.Forms.TextBox
    $VHDPath.multiline = $false
    $VHDPath.text = "\\Server\ShareName (Clear to not set)"
    $VHDPath.width = 390
    $VHDPath.height = 20
    $VHDPath.location = New-Object System.Drawing.Point(270, 270)
    $VHDPath.Font = 'Microsoft Sans Serif,12'
    $VHDPath.Enabled = $false

    $InstallOneDrive = New-Object system.Windows.Forms.CheckBox
    $InstallOneDrive.text = "Install OneDrive per Machine "
    $InstallOneDrive.AutoSize = $false
    $InstallOneDrive.width = 400
    $InstallOneDrive.height = 30
    $InstallOneDrive.location = New-Object System.Drawing.Point(30, 300)
    $InstallOneDrive.Font = 'Microsoft Sans Serif,14'

    $InstallOneDrive.Add_CheckStateChanged( {
            $TenantID.Enabled = $InstallOneDrive.Checked
        })

    $LabelAADTenant = New-Object system.Windows.Forms.Label
    $LabelAADTenant.text = "AAD Tenant ID (Configures KFM)"
    $LabelAADTenant.AutoSize = $true
    $LabelAADTenant.width = 60
    $LabelAADTenant.height = 20
    $LabelAADTenant.location = New-Object System.Drawing.Point(46, 330)
    $LabelAADTenant.Font = 'Microsoft Sans Serif,12'

    $TenantID = New-Object system.Windows.Forms.TextBox
    $TenantID.multiline = $false
    $TenantID.text = "include '-'s (Clear to not set)"
    $TenantID.width = 300
    $TenantID.height = 20
    $TenantID.location = New-Object System.Drawing.Point(300, 330)
    $TenantID.Font = 'Microsoft Sans Serif,12'
    $TenantID.Enabled = $false

    $InstallTeams = New-Object system.Windows.Forms.CheckBox
    $InstallTeams.text = "Install Microsoft Teams per Machine"
    $InstallTeams.AutoSize = $false
    $InstallTeams.width = 400
    $InstallTeams.height = 30
    $InstallTeams.location = New-Object System.Drawing.Point(30, 360)
    $InstallTeams.Font = 'Microsoft Sans Serif,14'

    $InstallEdge = New-Object system.Windows.Forms.CheckBox
    $InstallEdge.text = "Install Microsoft Edge Enterprise"
    $InstallEdge.AutoSize = $false
    $InstallEdge.width = 400
    $InstallEdge.height = 30
    $InstallEdge.location = New-Object System.Drawing.Point(30, 390)
    $InstallEdge.Font = 'Microsoft Sans Serif,14'

    $DisableWU = New-Object system.Windows.Forms.CheckBox
    $DisableWU.text = "Disable All Software Updates"
    $DisableWU.AutoSize = $false
    $DisableWU.width = 400
    $DisableWU.height = 30
    $DisableWU.location = New-Object System.Drawing.Point(30, 420)
    $DisableWU.Font = 'Microsoft Sans Serif,14'

    $AppRemove = New-Object System.Windows.Forms.CheckBox
    $AppRemove.text = "Remove inbox Windows 10 Apps"
    $AppRemove.AutoSize = $false
    $AppRemove.Width = 550
    $AppRemove.height = 30
    $AppRemove.Location = New-Object System.Drawing.Point(30, 450)
    $AppRemove.Font = 'Microsoft Sans Serif,14'
    
    $RunCleanMgr = New-Object system.Windows.Forms.CheckBox
    $RunCleanMgr.text = "Run System Clean Up (CleanMgr.exe)"
    $RunCleanMgr.AutoSize = $false
    $RunCleanMgr.width = 400
    $RunCleanMgr.height = 30
    $RunCleanMgr.location = New-Object System.Drawing.Point(30, 480)
    $RunCleanMgr.Font = 'Microsoft Sans Serif,14'

    ForEach ($Item in $DropdownArraySyncMonths) {
        [void] $CalSyncTime.Items.Add($Item)
    }

    ForEach ($Item in $DropdownArrayEmailCacheSync) {
        [void] $EmailCacheMonths.Items.Add($Item)
    }

    ForEach ($Item in $DropdownArrayCalSyncMode) {
        [void] $CalendarSyncMode.Items.Add($Item)
    }

    $WVDGoldenImagePrep.controls.AddRange(@($Execute, $ScriptTitle, $CalendarSyncMode, $EmailCacheMonths, $CalSyncTime, $VHDPath, $TenantID, $InstallOffice365, $InstallFSLogix, $InstallOneDrive, $DisableWU, $InstallTeams, $InstallEdge, $AppRemove, $RunCleanMgr, $LabelVHDLocation, $LabelAADTenant, $labelEmailCache, $labelCalSyncType, $labelCalSyncTime))

    [void]$WVDGoldenImagePrep.ShowDialog()
}
Else {
    Invoke-ImageCustomization `
        -MarketPlaceSource $MarketPlaceSource `
        -Office365Install $Office365Install -EmailCacheTime $EmailCacheTime -CalendarSync $CalendarSync -CalendarSyncMonths $CalendarSyncMonths `
        -OneDriveInstall $OneDriveInstall -AADTenantID $AADTenantID `
        -FSLogixInstall $FSLogixInstall -FSLogixVHDPath $FSLogixVHDPath `
        -TeamsInstall $TeamsInstall `
        -EdgeInstall $EdgeInstall `
        -DisableUpdates $DisableUpdates `
        -CleanupImage $CleanupImage `
        -RemoveApps $RemoveApps
}
