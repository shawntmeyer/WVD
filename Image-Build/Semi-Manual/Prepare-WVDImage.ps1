#Requires -RunAsAdministrator

<#
.Synopsis
   Prepare a Windows System to be a WVD image
.DESCRIPTION
   Prepare a Windows System either running on Hyper-V or in Azure to be sysprep'd added as a Windows Virtual Desktop image.
   Script can install Office 365 from Microsoft CDN, OneDrive per machine, Teams per machine, FSLogix Agent, and Edge Chromium
   Script will configure each of these items in accordance with reference articles specified in the code below.
   Script will also perform WVD specific and Azure generic image configurations per reference articles.
.EXAMPLE
   WVDImagePrep.ps1 -InstallOneDrive $true -AADTenantID 'XXXXXXXX-XXX-XXXXXXX'
.EXAMPLE
   WVDImagePrep.ps1 -InstallOneDrive $true -FSLogixInstall $true -TeamsInstall $false
#>

Param
(
    # Working directory for script
    [string]$StagingPath,

    #Azure Active Directory TenantID
    [Parameter(Mandatory=$false)]
    [string]$AADTenantID,

    #install Office 365
    [boolean]$Office365Install=$true,

    # Outlook Email Cached Sync Time, Change to blank if you don't want to configure.
    [ValidateSet('3 days', '1 week', '2 weeks', '1 month', '3 months', '6 months', '12 months', '24 months', '36 months', '60 months', 'All')]
    [string]$EmailCacheTime = '1 month',

    # Outlook Calendar Sync Mode, Change to blank if you don't want to configure. See https://support.microsoft.com/en-us/help/2768656/outlook-performance-issues-when-there-are-too-many-items-or-folders-in
    [ValidateSet('Inactive','Primary Calendar Only','All Calendar Folders')]
    [string]$CalendarSync = 'Primary Calendar Only',

    # Outlook Calendar Sync Months, Change to blank if you don't want to configure. See https://support.microsoft.com/en-us/help/2768656/outlook-performance-issues-when-there-are-too-many-items-or-folders-in
    [ValidateSet(1,3,6,12)]
    [string]$CalendarSyncMonths=1,

    # Install OneDrive per-machine
    [boolean]$OneDriveInstall=$true,

    # Install FSLogix Agent
    [boolean]$FSLogixInstall=$true,

    # Enable the FSLogix Profile Container
    [boolean]$FSLogixEnabled=$false,

    #UNC Paths to FSLogix Profile Disks. Enclose each value in double quotes seperated by a ',' (ex: "\\primary\fslogix","\\failover\fslogix")
    $FSLogixVHDPath,

    # Set to true to force FSLogix to change the profile folder to "%username%%sid%" instead of "%sid%%username%". Helps for troubleshooting and searching.
    [boolean]$FSLogixFlipFlop=$true,

    # Set to true to redirect office activation to the FSLogix Office Container. For Pooled desktops.
    [boolean]$FSLogixIncludeOfficeActivation=$true,

    #Install Microsoft Teams in the Per-Machine configuration. Update the $TeamsURL variable to point to the latest version as needed.
    [boolean]$TeamsInstall=$false,

    #Install Microsoft Edge Chromium. Update $EdgeURL variable to point to latest version as needed.
    [boolean]$EdgeInstall=$true,

    #Disable Windows Update
    [boolean]$WindowsUpdateDisable=$True,

    #Run Disk Cleanup at end. Will require a reboot before sysprep.
    [boolean]$CleanupImage=$True
)

#region Variables
[string]$scriptPath = $MyInvocation.MyCommand.Definition
[string]$scriptName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
[string]$scriptFileName = Split-Path -Path $scriptPath -Leaf
[string]$scriptRoot = Split-Path -Path $scriptPath -Parent
If (!$StagingPath) {$StagingPath = $ScriptRoot}
If (!(Test-Path $StagingPath)) { cmd /c mkdir "$StagingPath" }
[String]$Script:LogDir = "$($env:SystemRoot)\Logs\ImagePrep"
[string]$Script:LogName = "$ScriptName.log"

#Cleanup Log Directory from Previous Runs
If (Test-Path "$Script:LogDir\$ScriptName.log") { Remove-Item "$Script:LogDir\$ScriptName.log" -Force }
If (Test-Path "$Script:LogDir\LGPO") { Remove-Item -Path "$Script:LogDir\LGPO" -Recurse -Force }

#Update URLs with new releases

[uri]$OneDriveUrl = "https://go.microsoft.com/fwlink/p/?linkid=2121808"
[uri]$TeamsUrl = "https://statics.teams.cdn.office.net/production-windows-x64/1.3.00.4461/Teams_windows_x64.msi"
[uri]$FSLogixUrl = "https://go.microsoft.com/fwlink/?linkid=2084562"
[uri]$EdgeUrl = "http://dl.delivery.mp.microsoft.com/filestreamingservice/files/9178ea11-b61e-465a-bc66-158a1868cfe0/MicrosoftEdgeEnterpriseX64.msi"
[uri]$EdgeTemplatesUrl ="http://dl.delivery.mp.microsoft.com/filestreamingservice/files/77969b35-d61e-4c50-8876-3b281c159a9d/MicrosoftEdgePolicyTemplates.cab"

#endregion

#region functions

Function Write-Log
{
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
		[Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[AllowEmptyCollection()]
		[string[]]$Message,
		[Parameter(Mandatory=$false,Position=1)]
		[ValidateRange(1,3)]
		[int16]$Severity = 1,
		[Parameter(Mandatory=$false,Position=2)]
		[ValidateNotNull()]
		[string]$Source = '',
		[Parameter(Mandatory=$false,Position=3)]
		[ValidateSet('CMTrace','Legacy')]
		[string]$LogType = "CMTrace",
		[Parameter(Mandatory=$false,Position=4)]
		[ValidateNotNullorEmpty()]
		[string]$LogFileDirectory = $Script:LogDir,
		[Parameter(Mandatory=$false,Position=5)]
		[ValidateNotNullorEmpty()]
		[string]$LogFileName = $Script:LogName,
		[Parameter(Mandatory=$false,Position=6)]
		[ValidateNotNullorEmpty()]
		[decimal]$MaxLogFileSizeMB = 100,
		[Parameter(Mandatory=$false,Position=7)]
		[ValidateNotNullorEmpty()]
		[boolean]$WriteHost = $true,
		[Parameter(Mandatory=$false,Position=8)]
		[ValidateNotNullorEmpty()]
		[boolean]$ContinueOnError = $true,
		[Parameter(Mandatory=$false,Position=9)]
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
			
            Try
            {
				$LogLine | Out-File -FilePath $LogFilePath -Append -NoClobber -Force -Encoding 'UTF8' -ErrorAction 'Stop'
			}
            Catch
            {
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
				[decimal]$LogFileSizeMB = $LogFile.Length/1MB
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

Function Set-RegistryValue
{
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true)]
		[ValidateNotNullorEmpty()]
		[string]$Key,
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$Name,
		[Parameter(Mandatory=$true)]
		$Value,
		[Parameter(Mandatory=$true)]
		[ValidateSet('Binary','DWord','ExpandString','MultiString','None','QWord','String','Unknown')]
		[Microsoft.Win32.RegistryValueKind]$Type = 'String'
	)

	[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

    If (-not (Get-ItemProperty -LiteralPath $key -Name $Name -ErrorAction 'SilentlyContinue'))
    {
        If (-not (Test-Path -LiteralPath $key -ErrorAction 'Stop'))
        {
		    Try
            {
				Write-Log -Message "Create registry key [$key]." -Source ${CmdletName}
				# No forward slash found in Key. Use New-Item cmdlet to create registry key
				If ((($Key -split '/').Count - 1) -eq 0)
				{
					$null = New-Item -Path $key -ItemType 'Registry' -Force -ErrorAction 'Stop'
				}
				# Forward slash was found in Key. Use REG.exe ADD to create registry key
				Else
				{
					[string]$CreateRegkeyResult = & reg.exe Add "$($Key.Substring($Key.IndexOf('::') + 2))"
					If ($global:LastExitCode -ne 0)
					{
						Throw "Failed to create registry key [$Key]"
					}
				}
			}
			Catch
            {
				Throw
			}
		}
        Write-Log -Message "Set registry key value: [$key] [$name = $value]." -Source ${CmdletName}
	    $null = New-ItemProperty -LiteralPath $key -Name $name -Value $value -PropertyType $Type -ErrorAction 'Stop'
    }
    ## Update registry value if it does exist
    Else
    {
        [string]$RegistryValueWriteAction = 'update'
	    If ($Name -eq '(Default)')
        {
	        ## Set Default registry key value with the following workaround, because Set-ItemProperty contains a bug and cannot set Default registry key value
		    $null = $(Get-Item -LiteralPath $key -ErrorAction 'Stop').OpenSubKey('','ReadWriteSubTree').SetValue($null,$value)
	    }
	    Else
        {
		    Write-Log -Message "Update registry key value: [$key] [$name = $value]." -Source ${CmdletName}
		    $null = Set-ItemProperty -LiteralPath $key -Name $name -Value $value -ErrorAction 'Stop'
	    }
    }
}

Function Download-File
{
    [CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true,Position=0)]
		[uri]$url,
		[Parameter(Mandatory=$false,Position=1)]
        [string]$outputfile

    )

    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

    $start_time = Get-Date
 
    $wc = New-Object System.Net.WebClient
    Write-Log -Message "Now Downloading file from `"$url`" to `"$outputfile`"." -Source ${CmdletName}
    $wc.DownloadFile($url, $outputfile)
    
    $time=(Get-Date).Subtract($start_time).Seconds
    
    Write-Log -Message "Time taken: `"$time`" seconds." -Source ${CmdletName}
    if(Test-Path -Path $outputfile)
    {
        $totalSize = (Get-Item $outputfile).Length / 1MB
        Write-Log -message "Download was successful. Final file size: `"$totalsize`" mb" -Source ${CmdletName}
    }
}

Function Update-LGPORegistryTxt
{
	Param (
		[Parameter(Mandatory=$true,Position=0)]
		[ValidateSet('Computer','User')]
		[string]$scope,
		[Parameter(Mandatory=$true,Position=1)]
        [string]$RegistryKeyPath,
        [Parameter(Mandatory=$true,Position=2)]
        [string]$RegistryValue,
        [Parameter(Mandatory=$true,Position=3)]
        [string]$RegistryData,
        [Parameter(Mandatory=$true,Position=4)]
        [ValidateSet('DWORD','String')]
        [string]$RegistryType,
        [string]$outputDir="$Script:LogDir\LGPO",
        [string]$outfileprefix=$Script:Section
    )

    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    # Convert $RegistryType to UpperCase to prevent LGPO errors.
    $RegistryType = $RegistryType.ToUpper()
    # Change String type to SZ for text file
    If ($RegistryType -eq 'STRING') {$RegistryType='SZ'}
    # Replace any incorrect registry entries for the format needed by text file.
    $modified=$false
    $SearchStrings = 'HKLM:\','HKCU:\','HKEY_CURRENT_USER:\','HKEY_LOCAL_MACHINE:\'
    ForEach ($String in $SearchStrings)
    {
        If ($RegistryKeyPath.StartsWith("$String") -and $modified -ne $true)
        {
            $index=$String.Length
            $RegistryKeyPath = $RegistryKeyPath.Substring($index,$RegistryKeyPath.Length-$index)
            $modified=$true
        }
    }
    
    #Create the output file if needed.
    $Outfile = "$OutputDir\$Outfileprefix-$Scope.txt"
    If (-not (Test-Path -LiteralPath $Outfile))
    {
        If (-not (Test-Path -LiteralPath $OutputDir -PathType 'Container'))
        {
	        Try
            {
		        $null = New-Item -Path $OutputDir -Type 'Directory' -Force -ErrorAction 'Stop'
		    }
            Catch {}
        }
        $null = New-Item -Path $outputdir -Name "$OutFilePrefix-$Scope.txt" -ItemType File -ErrorAction Stop
    }

    Write-Log -message "Adding registry information to `"$outfile`" for LGPO.exe" -Source ${CmdletName}
    # Update file with information
    Add-Content -Path $Outfile -Value $Scope
    Add-Content -Path $Outfile -Value $RegistryKeyPath
    Add-Content -Path $Outfile -Value $RegistryValue
    Add-Content -Path $Outfile -Value "$($RegistryType):$RegistryData"
    Add-Content -Path $Outfile -Value ""
}

Function Execute-LGPO
{
    Param (
        [string]$InputDir="$Script:LogDir\LGPO",
        [string]$SearchTerm="$Script:Section"
    )

    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    Write-Output "Gathering Registry text files for LGPO from $InputDir"
    $InputFiles = Get-ChildItem -Path $InputDir -Filter "$SearchTerm*.txt"
    Write-Output $InputFiles
    ForEach ($RegistryFile in $inputFiles)
    {
        $TxtFilePath = $RegistryFile.FullName
        Write-Log -Message "Now applying settings from `"$txtFilePath`" to Local Group Policy via LGPO.exe." -Source ${CmdletName}
        Start-Process -FilePath "$StagingPath\LGPO\lgpo.exe" -ArgumentList "/t `"$TxtFilePath`"" -PassThru -Wait -NoNewWindow
    }

}

Function Clean-Image
{
    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    Write-Log -Message "Now Cleaning image using Disk Cleanup wizard." -Source ${CmdletName}
    $RegKeyParent = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\"
    # Set up array of registry keys
    $RegKeySuffixes = "Active Setup Temp Folders","BranchCache","Downloaded Program Files","GameNewsFiles","GameStatisticsFiles","GameUpdateFiles",`
    "Internet Cache Files","Memory Dump Files","Offline Pages Files","Old ChkDsk Files","Previous Installations","Recycle Bin","Service Pack Cleanup",`
    "Setup Log Files","System error memory dump files","System error minidump files","Temporary Files","Temporary Setup Files","Temporary Sync Files",`
    "Thumbnail Cache","Update Cleanup","Upgrade Discarded Files","User file versions","Windows Defender","Windows Error Reporting Archive Files",`
    "Windows Error Reporting Queue Files","Windows Error Reporting System Archive Files","Windows Error Reporting System Queue Files",`
    "Windows ESD installation files","Windows Upgrade Log Files"
    
    ForEach ($Suffix in $RegKeySuffixes) { Set-RegistryValue -Key "$RegKeyParent$Suffix" -Name StateFlags0100 -Type DWord -Value 2 }
    Start-Process -FilePath cleanmgr.exe -ArgumentList "/sagerun:100" -Wait -PassThru


}

#endregion

#region Office365

If( $Office365Install -eq $true )
{
    $Ref = "https://docs.microsoft.com/en-us/azure/virtual-desktop/install-office-on-wvd-master-image"
    $Script:Section = 'Office 365'
    $dirOffice = "$ScriptRoot\Office365"

    Write-Log -Message "Installing and configuring Office 365 per `"$ref`"." -Source 'Main'

    If (-not(Test-Path "$env:WinDir\Logs\Software")) { New-Item -Path $env:WinDir\Logs -Name Software -ItemType Directory -Force }
    If (-not(Test-Path "$env:WinDir\Logs\Software\Office365")) { New-Item -Path $env:WinDir\Logs\Software -Name Office365 -ItemType Directory -Force }

    $Installer = Start-Process -FilePath "$dirOffice\setup.exe" -ArgumentList "/configure `"$dirOffice\Configuration.xml`"" -Wait -PassThru
 
    Write-Log -message "The exit code is $($Installer.ExitCode)" -Source 'Main'

    [string]$dirTemplates = Join-Path -Path $dirOffice -ChildPath 'Templates'
    if (Test-Path $dirTemplates)
    {
        Write-Log -message "Copying Group Policy ADMX/L files to PolicyDefinitions Folders."
        Copy-Item -Path "$DirTemplates\*.admx" -Destination "$env:WINDIR\PolicyDefinitions\"
        Copy-Item -Path "$DirTemplates\*.adml" -Destination "$env:WINDIR\PolicyDefinitions\en-us"
    }

    Write-Log -Message "Update Computer LGPO registry text file." -Source 'Main'

    # Hide Office Update Notifications
    Update-LGPORegistryTxt -scope Computer -RegistryKeyPath 'software\policies\microsoft\office\16.0\common\officeupdate' -RegistryValue HideUpdateNotifications -RegistryType DWord -RegistryData 1
    # Hide and Disable Updates
    Update-LGPORegistryTxt -Scope Computer -RegistryKeyPath 'software\policies\microsoft\office\16.0\common\officeupdate' -RegistryValue HideEnableDisableUpdates -RegistryType DWord -RegistryData 1

    Write-Log -Message "Update User LGPO registry text file." -Source 'Main'
    # Turn off insider notifications
    Update-LGPORegistryTxt -Scope User -RegistryKeyPath 'Software\policies\microsoft\office\16.0\common' -RegistryValue InsiderSlabBehavior -RegistryType DWord -RegistryData 2
    # Enable Outlook Cached Mode
    Update-LGPORegistryTxt -Scope User -RegistryKeyPath 'Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode' -RegistryValue Enable -RegistryType DWord -RegistryData 1

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

    If ($EmailCacheTime -and $EmailCacheTime -ne '') { Update-LGPORegistryTxt -Scope User -RegistryKeyPath 'Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode' -RegistryValue SyncWindowSetting -RegistryType DWORD -RegistryData $SyncWindowSetting }
    If ($SyncWindowSettingDays) { Update-LGPORegistryTxt -Scope User -RegistryKeyPath 'Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode' -RegistryValue SyncWindowSettingDays -RegistryType DWORD -RegistryData $SyncWindowSettingDays }

    # Calendar Sync Settings: https://support.microsoft.com/en-us/help/2768656/outlook-performance-issues-when-there-are-too-many-items-or-folders-in
    If ($CalendarSync -eq 'Inactive') { $CalendarSyncWindowSetting=0; }
    If ($CalendarSync -eq 'Primary Calendar Only') { $CalendarSyncWindowSetting = 1 }
    If ($CalendarSync -eq 'All Calendar Folders') { $CalendarSyncWindowSetting = 2 }

    If ($CaldendarSyncWindowSetting)
    {
        Reg LOAD HKLM\DefaultUser "$env:SystemDrive\Users\Default User\NtUser.dat"
        Set-RegistryValue -Key 'HKLM:\DefaultUser\Software\Policies\Microsoft\Office16.0\Outlook\Cached Mode' -Name CalendarSyncWindowSetting -Type DWord -Value $CalendarSyncWindowSetting
        If ($CalendarSyncMonths -and $CalendarSyncMonths -ne '')
        {
            Set-RegistryValue -Key 'HKCU:\DefaultUser\Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode' -Name CalendarSyncWindowSettingMonths -Type DWord -Value $CalendarSyncMonths
        }
        REG UNLOAD HKLM\DefaultUser
    }

    Execute-LGPO -SearchTerm "$Script:Section"
    Write-Log -Message "Completed the $Script:Section Section" -Source 'Main'

}
#endregion Office 365

#region OneDrive
If ( $OneDriveInstall -eq $true)
{
    $ref = "https://docs.microsoft.com/en-us/azure/virtual-desktop/install-office-on-wvd-master-image"

    $Script:Section='OneDrive'
    Write-Log -Message "Starting OneDrive installation and configuration in accordance with `"$ref`"." -Source 'Main'

    $output = "$StagingPath\onedrivesetup.exe"
    Download-File -url $OneDriveURL -outputfile $output
 
    Write-Log -Message "Uninstalling the OneDrive per-user installations." -Source 'Main'

    $Uninstaller = Start-Process -FilePath $output -ArgumentList "/uninstall" -wait -PassThru

    Write-Log -Message "The exit code from per-user uninstallation is $($Uninstaller.ExitCode)" -Source 'Main'

    Set-RegistryValue -Key "HKLM:\Software\Microsoft\OneDrive" -Name AllUsersInstall -Value 1 -Type DWord

    Write-Log -message "Starting installation of OneDrive for all users." -Source 'Main'
 
    $Args = "/allusers"
    Write-Log -Message "Trigger installation of file `"$output`" with switches `"$Args`"" -Source 'Main'
 
    $Installer = Start-Process -FilePath $output -ArgumentList $Args -Wait -PassThru
 
    Write-Log -message "The exit code is $($Installer.ExitCode)" -Source 'Main'

    Write-Log -message "Now copying the latest Group Policy ADMX and ADML files to the Policy Definition Folders." -Source 'Main'

    $InstallDir = "${env:ProgramFiles(x86)}\Microsoft OneDrive"

    If (Test-Path $installDir)
    {
        $ADMX = (Get-ChildItem $InstallDir -include '*.admx' -recurse)
        ForEach($file in $ADMX)
        {
            Copy-Item -Path $file.FullName -Destination "$env:Windir\PolicyDefinitions" -Force
        }

        $ADML = (get-childitem $InstallDir -include '*.adml' -recurse | Where-object {$_.Directory -like '*adm'})
        ForEach($file in $ADML)
        {
            Copy-Item -Path $file.FullName -Destination "$env:Windir\PolicyDefinitions\en-us" -Force
        }
    }

    Write-Log -Message "Now configuring OneDrive KFM to run silently" -Source 'Main'

    Set-RegistryValue -Key "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name OneDrive -Value "C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe /background" -Type String

    If ($AADTenantID -and $AADTenantID -ne '')
    {
        Write-Log "Now applying OneDrive for Business Known Folder Move Silent Configuration Settings." -Source 'Main'
        Update-LGPORegistryTxt -scope Computer -RegistryKeyPath "SOFTWARE\Policies\Microsoft\OneDrive" -RegistryValue SilentAccountConfig -RegistryType DWord -RegistryData 1
        Update-LGPORegistryTxt -Scope Computer -RegistryKeyPath "SOFTWARE\Policies\Microsoft\OneDrive" -RegistryValue KFMSilentOptIn -RegistryType String -RegistryData "$AADTenantID"
    }
    Execute-LGPO -SearchTerm "$Script:Section"
    Write-Log -Message "Complete $Script:Section Section." -Source 'Main'
}

#endregion OneDrive

#region Teams

If ( $TeamsInstall -eq $true )
{
    # Download and install Microsoft Teams 
    $ref = "https://docs.microsoft.com/en-us/azure/virtual-desktop/teams-on-wvd"
    # Link to downloads: https://docs.microsoft.com/en-us/microsoftteams/teams-for-vdi#deploy-the-teams-desktop-app-to-the-vm

    $Script:Section='Teams'

    Write-Log -Message "Starting Teams Installation and Configuration in accordance with `"$ref`"." -Source 'Main'
    $output = "$StagingPath\Teams_Windows_x64.msi"
    Download-File -url $TeamsUrl -outputfile $output
 
    Set-RegistryValue -Key "HKLM:\Software\Microsoft\Teams" -Name IsWVDEnvironment -Value 1 -Type DWord

    Write-Log -message "Starting installation of Microsoft Teams for all users." -Source 'Main'
 
    # Command line looks like: msiexec /i <msi_name> /l*v < install_logfile_name> ALLUSER=1
    $Args = "/i `"$output`" /l*v `"$env:WinDir\Logs\Software\Teams_MSI.log`" ALLUSER=1" 
    Write-Log -message "Running `"msiexec.exe $Args`"" -Source 'Main'
    $Installer = Start-Process -FilePath "msiexec.exe" -ArgumentList $Args -Wait -PassThru
    Write-Log -message "The exit code is $($Installer.ExitCode)" -Source 'Main'
    Write-Log -message "Completed $Script:Section Section." -Source 'Main'

}

#endregion

#region FSLogix Agent

If ($FSLogixInstall)
{
    $Script:Section='FSLogix Agent'
    Write-Log "Starting FSLogix Agent Installation and Configuration." -Source 'Main'
    Write-Log "Downloading FSLogix Agent from Microsoft." -Source 'Main'
    $output = "$StagingPath\fslogix.zip"
    Download-File -url $FSLogixUrl -outputfile $output
    Write-Log -message "Extracting FSLogix Agent from zip." -Source 'Main'
    $destpath = "$stagingPath\FSLogix"
    Expand-Archive $output -DestinationPath $destpath -Force
    Start-Sleep -Seconds 5
    Write-Log -message "Now copying the latest Group Policy ADMX and ADML files to the Policy Definition Folders." -Source 'Main'
    $admx = Get-ChildItem "$destpath" -Filter "*.admx" -Recurse
    $adml = Get-ChildItem "$destpath" -filter "*.adml" -Recurse
    ForEach($file in $admx)
    {
        Copy-item -Path $file.fullname -Destination "$env:Windir\PolicyDefinitions" -Force
    }
    ForEach($file in $adml)
    {
        Copy-item -Path $file.fullname -Destination "$env:Windir\PolicyDefinitions\en-us" -Force
    }
    $Installer="$stagingPath\fslogix\x64\release\fslogixappssetup.exe"
    If (Test-Path $Installer)
    {
        Write-Log -Message "Installation File: `"$installer`" successfully extracted." -Source 'Main'
    }

    $Arguments = "/quiet"
    Write-Log -Message "Now starting FSLogix Agent installation with command line: `"$installer $Arguments`"." -Source 'Main'

    $Install = Start-Process -FilePath $Installer -ArgumentList "$Arguments" -Wait -PassThru

    Write-Log -message "The fslogixappssetup.exe exit code is $($Install.ExitCode)" -Source 'Main'

    Write-Log -Message "Now performing FSLogix Configuration if enabled." -Source 'Main'
    $RegistryKey = 'HKLM:\Software\FSLogix\Profiles'
    If ( $FSLogixEnabled -eq $True )
    {
        Write-Log -Message "Enabling FSLogix Profile Container in Registry"
        Set-RegistryValue -Key $RegistryKey -Name Enabled -Value 1 -Type DWord
    }
    if ( $FSLogixVHDPath -and $FSLogixVHDPath -ne '' )
    {
        Write-Log -Message "Setting VHDLocation to `"$FSLogixVHDPath`" in registry."
        Set-RegistryValue -Key $RegistryKey -Name VHDLocations -Value $FSLogixVHDPath -Type MultiString
        Add-MpPreference -ExclusionPath $FSLogixVHDPath
    }
    if ( $FSLogixFlipFlop -eq $True )
    {
        Write-Log -Message "Configuring VHD Folder name to begin with username instead of SID"
        Set-RegistryValue -Key $RegistryKey -Name FlipFlopProfileDirectoryName -Value 1 -Type DWord
    }
    if ( $FSLogixIncludeOfficeActivation -eq $True )
    {
        Write-Log -Message "Configuring FSLogix Office Container to include Office Activation Information."
        Update-LGPORegistryTxt -Scope Computer -RegistryKeyPath 'Software\Policies\FSLogix\ODFC' -RegistryValue IncludeOfficeActivation -RegistryType DWord -RegistryData 1
    }
    Execute-LGPO -SearchTerm "$Script:Section"
    Write-Log -Message "Completed $Script:Section script section." -Source 'Main'
}

#endregion FSLogix Agent

#region Edge Enterprise
If ( $EdgeInstall -eq $true )
{

    $Script:Section='Edge Enterprise'
    $ref = 'https://docs.microsoft.com/en-us/deployedge/deploy-edge-with-configuration-manager'
    # Disable Edge Updates
    Write-Log -Message "Starting Microsoft Edge Enterprise Installation and Configuration in accordance with `"$ref`"." -Source 'Main'

    $dirTemplates = "$StagingPath\Edge\Templates"
    if (Test-Path $dirTemplates)
    {
        Write-Log -message "Copying Group Policy ADMX/L files to PolicyDefinitions Folders." -Source 'Main'
        Copy-Item -Path "$DirTemplates\*.admx" -Destination "$env:WINDIR\PolicyDefinitions\" -force
        Copy-Item -Path "$DirTemplates\*.adml" -Destination "$env:WINDIR\PolicyDefinitions\en-us" -force
    }
    Write-Log -Message "Now disabling Edge Automatic Updates" -Source 'Main'
    Update-LGPORegistryTxt -scope Computer -RegistryKeyPath 'Software\Policies\Microsoft\EdgeUpdate' -RegistryValue UpdateDefault -RegistryType DWORD -RegistryData 0
    # Disable Edge Desktop Shortcut Creation
    Write-Log -Message "Now disabling Edge Automatic Desktop Shortcut Creation." -Source 'Main'
    Set-RegistryValue -Key "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name DisableEdgeDesktopShortcutCreation -Value 1 -Type Dword
    Write-Log "Now Downloading Enterprise Version of Edge from Microsoft." -Source 'Main'
    $output = "$StagingPath\MicrosoftEdgeEnteprisex64.msi"
    Download-File -url $EdgeUrl -outputfile $output
    $installer = "msiexec.exe"
    $MSIfile = "$output" 
    Write-Log -message "Starting installation of Microsoft Edge Enterprise." -Source 'Main'
    $Args = "/i `"$msifile`" /q" 
    Write-Log -message "Running `"$installer $Args`"" -Source 'Main'
    $Install = Start-Process -FilePath "$installer" -ArgumentList $Args -Wait -PassThru
    Write-Log -message "The exit code is $($Install.ExitCode)" -Source 'Main'
    Write-Log -Message "Complete $Script:Section script section." -Source 'Main'

}

#endregion Edge Enterprise

#region Workplace Join

$Script:Section='WorkPlace Join'
Write-Log "Now disabling Workplace Join to prevent issue with Office Activation." -Source 'Main'
# Block domain joined machines from inadvertently getting Azure AD registered by users.
Set-RegistryValue -Key 'HKLM:\Software\Policies\Microsoft\Windows\WorkplaceJoin' -Name BlockAADWorkplaceJoin -Type DWord -Value 1

#endregion

#region WVD Image Settings

$Script:Section='WVD Image Settings'

$ref = "https://docs.microsoft.com/en-us/azure/virtual-desktop/set-up-customize-master-image"

Write-Log "Now starting to apply $Script:Section in accordance with `"$ref`"." -Source 'Main'

If ($WindowsUpdateDisable -eq $True)
{
    Write-Log "Disabling Windows Updates via Group Policy setting" -Source 'Main'
    Update-LGPORegistryTxt -scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -RegistryValue NoAutoUpdate -RegistryType Dword -RegistryData 1
}
Write-Log "Enabling Time Zone Redirection from Client to Session Host." -Source 'Main'
Update-LGPORegistryTxt -scope Computer -RegistryKeyPath "SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -RegistryValue fEnableTimeZoneRedirection -RegistryType DWord -RegistryData 1

Write-Log "Disabling Storage Sense GPO" -Source 'Main'

Update-LGPORegistrytxt -Scope Computer -RegistryKeyPath 'Software\Policies\Microsoft\Windows\StorageSense' -RegistryValue AllowStorageSenseGlobal -RegistryType DWORD -RegistryData 0

# Fix issues with Doctor Watson Crashes
# List of Registry Values from https://docs.microsoft.com/en-us/windows/win32/wer/wer-settings
Write-Log -Message "Removing Corporate Windows Error Reporting Server if set in registry." -Source 'Main'
$RegValues = "CorporateWERDirectory", "CorporateWERPortNumber","CorporateWERServer","CorporateWERUseAuthentication","CorporateWERUseSSL"
$RegPath = "HKLM:\Software\Microsoft\Windows\Windows Error Reporting"
ForEach ($value in $regvalues)
{
    If (Get-ItemProperty $RegPath -name $value -ErrorAction SilentlyContinue)
    {
        Remove-ItemProperty $RegPath -Name $Value -Force -ErrorAction SilentlyContinue
    }
}

# Fix 5k resolution support
Write-Log -Message "Fixing 5K Resolution Support" -Source 'Main'

$RegistryKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
Set-RegistryValue -Key $RegistryKey -Name MaxMonitors -Type DWord -Value 4
Set-RegistryValue -Key $RegistryKey -Name MaxXResolution -Type DWord -Value 5120
Set-RegistryValue -Key $RegistryKey -Name MaxYResolution -Type DWord -Value 2880
$RegistryKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\rdp-sxs"
Set-RegistryValue -Key $RegistryKey -Name MaxMonitors -Type DWord -Value 4
Set-RegistryValue -Key $RegistryKey -Name MaxXResolution -Type DWord -Value 5120
Set-RegistryValue -Key $RegistryKey -Name MaxYResolution -Type DWord -Value 2880

Execute-LGPO -SearchTerm "$Script:Section"
Write-Log "Completed $Script:Section script section." -Source 'Main'

#endregion

#region Generic VHD Image Prep

$Script:Section='Azure VHD Image Settings'

# The following steps are from: https://docs.microsoft.com/en-us/azure/virtual-machines/windows/prepare-for-upload-vhd-image
Write-Log -Message "Performing Configuration spelled out in `"https://docs.microsoft.com/en-us/azure/virtual-machines/windows/prepare-for-upload-vhd-image`"." -Source 'Main'

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
Update-LGPORegistryTxt -Scope Computer -RegistryKeyPath 'Software\Policies\Microsoft\Windows NT\Terminal Services' -RegistryValue fDenyTSConnections -RegistryType DWord -RegistryData 0

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
Update-LGPORegistryTxt -scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -RegistryValue 'KeepAliveEnable' -RegistryType DWord -RegistryData 1
Update-LGPORegistryTxt -scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -RegistryValue 'KeepAliveInterval' -RegistryType DWord -RegistryData 1
Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "KeepAliveTimeout" -Value 1 -Type DWord

# Reconnect
Update-LGPORegistryTxt -Scope Computer -RegistryKeyPath 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -RegistryValue fDisableAutoReconnect -RegistryType DWord -RegistryData 0
Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "fInheritReconnectSame" -Value 1 -Type DWord
Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "fReconnectSame" -Value 0 -Type DWord

# Limit number of concurrent sessions
Set-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -name "MaxInstanceCount" -Value 4294967295 -Type DWord

# Remove any self signed certs
if ((Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp').Property -contains "SSLCertificateSHA1Hash")
{
    Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "SSLCertificateSHA1Hash" -Force
}

# Turn on Firewall
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# Allow WinRM
Set-RegistryValue -Key 'HKLM:\System\CurrentControlSet\Services\WinRM' -Name Start -Value 2 -Type DWord
Start-Service -Name WinRM
Enable-PSRemoting -force
Set-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -Enabled True

# Allow RDP
Set-NetFirewallRule -DisplayGroup "Remote Desktop" -Enabled True

# Enable File and Printer sharing for ping
Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -Enabled True

New-NetFirewallRule -DisplayName "AzurePlatform" -Direction Inbound -RemoteAddress 168.63.129.16 -Profile Any -Action Allow -EdgeTraversalPolicy Allow
New-NetFirewallRule -DisplayName "AzurePlatform" -Direction Outbound -RemoteAddress 168.63.129.16 -Profile Any -Action Allow

Execute-LGPO -SearchTerm "$Script:Section"

Write-Log "Completed $Script:Section script section." -Source 'Main'
#endregion
$Script:Section='Cleanup'
Write-Log "Outputing Group Policy Results and Local GPO Backup to `"$Script:LogDir\LGPO`"" -Source 'Main'
Start-Process -FilePath gpresult.exe -ArgumentList "/h `"$Script:LogDir\LGPO\LocalGroupPolicy.html`"" -PassThru -Wait
Start-Process -FilePath "$StagingPath\LGPO\lgpo.exe" -ArgumentList "/b `"$Script:LogDir\LGPO`" /n `"WVD Image Local Group Policy Settings`"" -PassThru -Wait
If ($CleanupImage -eq $true) { Clean-Image }
Write-Log -message "$scriptFileName completed." -source 'Main'
Remove-Item "$StagingPath\*" -Recurse -Force -ErrorAction SilentlyContinue