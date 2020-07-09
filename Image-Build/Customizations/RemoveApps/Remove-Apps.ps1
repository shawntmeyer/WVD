# ***************************************************************************
# 
# File:      RemoveApps.ps1
# 
# Version:   2.0
# 
# Author:    Shawn Meyer, Built on Michael Niehaus' similar app.
#
# Purpose:   Removes some or all of the in-box apps on Windows 8, Windows 8.1,
#            or Windows 10 systems.  The script supports both offline and
#            online removal.  By default it will remove all apps, but you can
#            provide a separate RemoveApps.xml file with a list of apps that
#            you want to instead remove.  If this file doesn't exist, the
#            script will recreate one in the log or temp folder, so you can
#            run the script once, grab the file, make whatever changes you
#            want, then put the file alongside the script and it will remove
#            only the apps you specified.
#
# Usage:     This script can be added into any MDT or ConfigMgr task sequences.
#            It has a few dependencies:
#              1.  For offline use in Windows PE, the .NET Framework, 
#                  PowerShell, DISM Cmdlets, and Storage cmdlets must be 
#                  included in the boot image.
#              2.  Script execution must be enabled, e.g. "Set-ExecutionPolicy
#                  Bypass".  This can be done via a separate task sequence 
#                  step if needed, see http://blogs.technet.com/mniehaus for
#                  more information.
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
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>

[string]$invokingScript = (Get-Variable -Name 'MyInvocation').Value.ScriptName

If (! $invokingScript)
{

    #region Required Functions

    #region Function Get-LogDir
    function Get-LogDir
    {
      try
      {
        $ts = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
        if ($ts.Value("LogPath") -ne "")
        {
          $logDir = $ts.Value("LogPath")
        }
        else
        {
          $logDir = $ts.Value("_SMSTSLogPath")
        }
      }
      catch
      {
        $logDir = "$($env:Systemroot)\logs"
      }
      return $logDir
    }
    #endregion

    #region Function Write-Log
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
		[Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[AllowEmptyCollection()]
		[Alias('Text')]
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
		[string]$LogFileDirectory = $LogDir,
		[Parameter(Mandatory=$false,Position=5)]
		[ValidateNotNullorEmpty()]
		[string]$LogFileName = $LogName,
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
		If (-not (Test-Path -LiteralPath 'variable:DisableLogging')) { $DisableLogging = $false }
		#  Check if the script section is defined
		[boolean]$ScriptSectionDefined = [boolean](-not [string]::IsNullOrEmpty($ScriptSection))
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
		
		## Exit function if it is a debug message and logging debug messages is not enabled in the config XML file
		If (($DebugMessage) -and (-not $LogDebugMessage)) { [boolean]$ExitLoggingFunction = $true; Return }
		## Exit function if logging to file is disabled and logging to console host is disabled
		If (($DisableLogging) -and (-not $WriteHost)) { [boolean]$ExitLoggingFunction = $true; Return }
		## Exit Begin block if logging is disabled
		If ($DisableLogging) { Return }
		## Exit function function if it is an [Initialization] message and the toolkit has been relaunched
		If (($AsyncToolkitLaunch) -and ($ScriptSection -eq 'Initialization')) { [boolean]$ExitLoggingFunction = $true; Return }
		
		## Create the directory where the log file will be saved
		If (-not (Test-Path -LiteralPath $LogFileDirectory -PathType 'Container')) {
			Try {
				$null = New-Item -Path $LogFileDirectory -Type 'Directory' -Force -ErrorAction 'Stop'
			}
			Catch {
				[boolean]$ExitLoggingFunction = $true
				#  If error creating directory, write message to console
				If (-not $ContinueOnError) {
					Write-Host -Object "[$LogDate $LogTime] [${CmdletName}] $ScriptSection :: Failed to create the log directory [$LogFileDirectory]. `n$(Resolve-Error)" -ForegroundColor 'Red'
				}
				Return
			}
		}
		
		## Assemble the fully qualified path to the log file
		[string]$LogFilePath = Join-Path -Path $LogFileDirectory -ChildPath $LogFileName
	}
	Process {
		## Exit function if logging is disabled
		If ($ExitLoggingFunction) { Return }
		
		ForEach ($Msg in $Message) {
			## If the message is not $null or empty, create the log entry for the different logging methods
			[string]$CMTraceMsg = ''
			[string]$ConsoleLogLine = ''
			[string]$LegacyTextLogLine = ''
			If ($Msg) {
				#  Create the CMTrace log message
				If ($ScriptSectionDefined) { [string]$CMTraceMsg = "[$ScriptSection] :: $Msg" }
				
				#  Create a Console and Legacy "text" log entry
				[string]$LegacyMsg = "[$LogDate $LogTime]"
				If ($ScriptSectionDefined) { [string]$LegacyMsg += " [$ScriptSection]" }
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
			
			## Write the log entry to the log file if logging is not currently disabled
			If (-not $DisableLogging) {
				Try {
					$LogLine | Out-File -FilePath $LogFilePath -Append -NoClobber -Force -Encoding 'UTF8' -ErrorAction 'Stop'
				}
				Catch {
					If (-not $ContinueOnError) {
						Write-Host -Object "[$LogDate $LogTime] [$ScriptSection] [${CmdletName}] :: Failed to write message [$Msg] to the log file [$LogFilePath]. `n$(Resolve-Error)" -ForegroundColor 'Red'
					}
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
					[hashtable]$ArchiveLogParams = @{ ScriptSection = $ScriptSection; Source = ${CmdletName}; Severity = 2; LogFileDirectory = $LogFileDirectory; LogFileName = $LogFileName; LogType = $LogType; MaxLogFileSizeMB = 0; WriteHost = $WriteHost; ContinueOnError = $ContinueOnError; PassThru = $false }
					
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
    #endregion

    ## Variables: Script Name and Script Paths
    [string]$scriptPath = $MyInvocation.MyCommand.Definition
    [string]$scriptName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
    [string]$scriptFileName = Split-Path -Path $scriptPath -Leaf
    [string]$scriptRoot = Split-Path -Path $scriptPath -Parent
    $LogDir=Get-LogDir
    [string]$LogName = "$ScriptName.log"
}

# ---------------------------------------------------------------------------
# Get-AppList:  Return the list of apps to be removed
# ---------------------------------------------------------------------------

function Get-AppList
{
  begin
  {
  	## Get the name of this function
	[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    # Look for a config file.
    
    $configFile = "$PSScriptRoot\RemoveApps.xml"
    if (Test-Path -Path $configFile)
    {
      # Read the list
      Write-Log "Reading list of apps from $configFile" -Source ${CmdletName}
      $list = get-content $configfile | where {!$_.contains("#")}
    }
    else
    {
      # No list? Build one with all apps.
      Write-Log "Building list of provisioned apps" -Source ${CmdletName}
      $list = @()
      if ($script:Offline)
      {
        Get-AppxProvisionedPackage -Path $script:OfflinePath | % { $list += $_.DisplayName }
      }
      else
      {
        Get-AppxProvisionedPackage -Online | % { $list += $_.DisplayName }
      }

      # Write the list to the log path
      $configFile = "$logDir\RemoveApps.xml"
      $list | Set-Content $configFile
      Write-Log "Wrote list of apps to $logDir\RemoveApps.xml, edit and place in the same folder as the script to use that list for future script executions" -Source ${CMDLetName}
    }

    Write-Log "Apps selected for removal: $list.Count" -Source $CmdletName
  }

  process
  {
    $list
  }

}

# ---------------------------------------------------------------------------
# Remove-App:  Remove the specified app (online or offline)
# ---------------------------------------------------------------------------

function Remove-App
{
  [CmdletBinding()]
  param (
        [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string] $appName
  )

  begin
  {
  	## Get the name of this function
	[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    # Determine offline or online
    
    if ($script:Offline)
    {
      Write-Log "Getting Apps provisioned in offline image." -Source $CmdletName
      $script:Provisioned = Get-AppxProvisionedPackage -Path $script:OfflinePath
    }
    else
    {
      Write-Log "Getting Apps provisioned in online OS." -Source $CmdletName
      $script:Provisioned = Get-AppxProvisionedPackage -Online
      $script:AppxPackages = Get-AppxPackage
    }
  }

  process
  {
    $app = $_

    # Remove the provisioned package
    Write-Log "Removing provisioned package $_" -Source $CmdletName
    $current = $script:Provisioned | ? { $_.DisplayName -eq $app }
    if ($current)
    {
      if ($script:Offline)
      {
        $a = Remove-AppxProvisionedPackage -Path $script:OfflinePath -PackageName $current.PackageName
      }
      else
      {
        $a = Remove-AppxProvisionedPackage -Online -PackageName $current.PackageName
      }
    }
    else
    {
      Write-Log "Unable to find provisioned package $_" -Source $CmdletName -Severity 2
    }

    # If online, remove installed apps too
    if (-not $script:Offline)
    {
      Write-Log "Removing installed package $_" -Source $CmdletName
      $current = $script:AppxPackages | ? {$_.Name -eq $app }
      if ($current)
      {
        $current | Remove-AppxPackage
      }
      else
      {
        Write-Log "Unable to find installed app $_" -Source $CmdletName -Severity 2
      }
    }

  }
  End
  {
  }
}

function Get-OnlineCapabilities
{
## Get the name of this function
[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

#New PSObject Template
$DismObjT = New-Object –TypeName PSObject -Property @{
    "Name" = ""
    "State" = ""
    }

#Creating Blank array for holding the result
$objResult = @()

#Read current values
$dismoutput = Dism /online /Get-Capabilities /limitaccess

#Counter for getting alternate values
$i = 1

#Parsing the data

$DismOutput | Select-String -pattern "Capability Identity :", "State :" |
    ForEach-Object{


        if($i%2)
        {

            #Creating new object\Resetting for every item using template
            $TempObj = $DismObjT | Select-Object *

            #Assigning Value1
            $TempObj.Name = ([string]$_).split(":")[1].trim() ;$i=0
        }
        else
        {
            #Assigning Value2
            $TempObj.State = ([string]$_).split(":")[1].trim() ;$i=1
            
            #Incrementing the object once both values filled
            $objResult+=$TempObj
        } 

    }

    Return $objResult
}

function Get-CapabilityList
{
  begin
  {
  	## Get the name of this function
	[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    
    # Look for a config file.
    $configFile = "$PSScriptRoot\RemoveCapabilities.xml"
    if (Test-Path -Path $configFile)
    {
      # Read the list
      Write-Log "Reading list of Capabilities from $configFile" -Source $CMdletname
      $list = get-content $configfile | where {!$_.contains("#")}
    }
    else
    {
      # No list? Build one with all Capabilities.
      Write-Log "Building list of Installed Capabilities" -Source $CMdletname
      $list = @()
      if ($script:Offline)
      {
        Get-WindowsCapability -Path $script:OfflinePath | % { If ($_.Name -like '*App*') { $list += $_.Name } }
      }
      else
      {
        Get-OnlineCapabilities | % { If ($_.Name -like '*App*') { $list += $_.Name } }
      }

      # Write the list to the log path
      $logDir = Get-LogDir
      $configFile = "$logDir\RemoveCapabilities.xml"
      $list | Set-Content $configFile
      write-Log "Wrote list of Apps in Windows Capabilities to $logDir\RemoveCapabilities.xml, edit and place in the same folder as the script to use that list for future script executions" -Source $CmdletName
    }

    write-Log "Capability Apps selected for removal: $list.Count" -Source $CmdletName
  }

  process
  {
    $list
  }
  End
  {

  }

}

function Remove-Capability
{
  [CmdletBinding()]
  param (
        [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string] $CapabilityName
  )

  begin
  {
  	## Get the name of this function
	[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    
    # Determine offline or online
    if ($script:Offline)
    {
      $script:Capability = Get-WindowsCapability -Path $script:OfflinePath
    }
    else
    {
      $script:Capability = Get-OnlineCapabilities
    }
  }

  process
  {
    $WindowsCapability = $_

    # Remove the provisioned package
    write-Log "Removing Windows Capability $_" -Source $CmdletName
    $current = $script:Capability | ? { $_.Name -eq $WindowsCapability -and $_.State -eq 'Installed' }
    if ($current)
    {
      if ($script:Offline)
      {
        $a = Remove-WindowsCapability -Path $script:OfflinePath -Name $current.Name
      }
      else
      {
        $a = Remove-WindowsCapability -Online -Name $current.Name
      }
    }
  }
  End
  {
  }
}

# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------


if ($env:SYSTEMDRIVE -eq "X:")
{
    $script:Offline = $true
    Write-Log "Script running in WinPE. Now searching for Offline Windows Drive." -Source "Remove-Apps"

    # Find Windows
    $drives = get-volume | ? {-not [String]::IsNullOrWhiteSpace($_.DriveLetter) } | ? {$_.DriveType -eq 'Fixed'} | ? {$_.DriveLetter -ne 'X'}
    $drives | ? { Test-Path "$($_.DriveLetter):\Windows\System32"} | % { $script:OfflinePath = "$($_.DriveLetter):\" }
    Write-Log "Eligible offline drive found: $script:OfflinePath" -Source "Remove-Apps"
    $dismout = dism /image:$script:offlinepath /get-currentedition
    $version = ($dismout | % { If ($_ -Like 'Image Version:*') {$_}}).Split(" ")[2]
    [int]$Build = $version.Split(".")[2] -as [int]
    Write-Log "Offline Image Build = $Build" -Source "Remove-Apps"
}
else
{
    Write-Log "Running in the full OS." -Source "Remove-Apps"
    $script:Offline = $false
    [int]$Build = [System.Environment]::OSVersion.Version.Build
    Write-Log "Online OS build = $Build" -Source "Remove-Apps"
}

Get-AppList | Remove-App

Get-CapabilityList | Remove-Capability
