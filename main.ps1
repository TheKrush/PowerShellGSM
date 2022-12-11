# August 2021
# Created by and Patrix87 of https://bucherons.ca
# Run this script to Stop->Backup->Update->Start your server.

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$ServerCfg,
    [Parameter(Mandatory=$false)]
    [switch]$Task
)

#---------------------------------------------------------
# Importing functions and variables.
#---------------------------------------------------------

# import global config, all functions. Exit if fails.
try {
    Import-Module -Name ".\global.psm1"
    Get-ChildItem -Path ".\functions" -Include "*.psm1" -Recurse | Import-Module
}
catch {
    Exit-WithError -ErrorMsg "Unable to import modules."
    exit
}

#---------------------------------------------------------
# Start Logging
#---------------------------------------------------------

#Define Logfile by TimeStamp-ServerCfg.
$LogFile = "$(Get-TimeStamp)-$($ServerCfg).txt"
# Start Logging
Start-Transcript -Path "$($Global.LogFolder)\$LogFile" -IncludeInvocationHeader

#---------------------------------------------------------
# Set Script Directory as Working Directory
#---------------------------------------------------------

#Find the location of the current invocation of main.ps1, remove the filename, set the working directory to that path.
Write-ScriptMsg "Setting Script Directory as Working Directory..."
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path -Path $scriptpath
$dir = Resolve-Path -Path $dir
$null = Set-Location -Path $dir
Write-ScriptMsg "Working Directory : $(Get-Location)"

#---------------------------------------------------------
# Get server IPs
#---------------------------------------------------------

Set-IP

#---------------------------------------------------------
# Install Dependencies
#---------------------------------------------------------

Install-Dependency

#---------------------------------------------------------
# Importing server configuration.
#---------------------------------------------------------

Write-ScriptMsg "Importing Server Configuration..."
#Check if requested config exist in the config folder, if not, copy it from the templates. Exit if fails.
#In the case of an update check or alive check, remove the check if the configuration is deleted.
if (-not (Test-Path -Path ".\configs\$ServerCfg.psm1" -PathType "Leaf" -ErrorAction SilentlyContinue)) {
	if($Task){
		Unregister-Task
		Exit
	}
    if (Test-Path -Path ".\templates\$ServerCfg.psm1" -PathType "Leaf" -ErrorAction SilentlyContinue){
        $null = Copy-Item -Path ".\templates\$ServerCfg.psm1" -Destination ".\configs\$ServerCfg.psm1" -ErrorAction SilentlyContinue
    } else {
        Exit-WithError -ErrorMsg "Unable to find configuration file."
    }
}

# import the current server config file. Exit if fails.
try {
    Import-Module -Name ".\configs\$ServerCfg.psm1"
}
catch {
    Exit-WithError -ErrorMsg "Unable to import server configuration."
}

#Parse configuration
Read-Config

#Check if script is already running
if(Get-Lock){
	exit
}

#Locking Script to avoid double run
Lock-Process

#---------------------------------------------------------
# Checking Scheduled Task
#---------------------------------------------------------
if ($Task) {
	$FullRunRequired = $false
    Write-ScriptMsg "Running Tasks for $($Server.UID) ..."
	$TasksSchedule = Get-TaskConfig

	if(($Server.AutoRestartOnCrash) -and (($TasksSchedule.NextAlive) -lt (Get-Date))){
		Write-ScriptMsg "Checking Alive State"
		if(-not (Get-ServerProcess)) {
			Write-ScriptMsg "Server is Dead, Restarting..."
			Update-TaskConfig -Alive
			$FullRunRequired = $true
		} else {
			Write-ScriptMsg "Server is Alive"
		}
	}

	if(($Server.AutoUpdates) -and (($TasksSchedule.NextUpdate) -lt (Get-Date))){
		Write-ScriptMsg "Checking on steamCMD if updates are avaiable for $($Server.UID)..."
		if (Request-Update){
			Write-ScriptMsg "Updates are available for $($Server.UID), Proceeding with update process..."
			$FullRunRequired = $true
			Update-TaskConfig -Update
		} else {
			Write-ScriptMsg "No updates are available for $($Server.UID)"
		}
	}

	Write-ScriptMsg "Checking if server $($Server.UID) is due for restart"
	if(($Server.AutoRestart) -and (($TasksSchedule.NextRestart) -lt (Get-Date))){
		$FullRunRequired = $true
		Update-TaskConfig -Restart
	}

	if(-not $FullRunRequired) {
		exit
	}
    #Run Launcher as usual
}

#---------------------------------------------------------
# Install Server
#---------------------------------------------------------

Write-ScriptMsg "Verifying Server installation..."
#Flag of a fresh installation in the current instance.
$FreshInstall = $false
#If the server executable is missing, run SteamCMD and install the server.
if (-not (Test-Path -Path $Server.Exec -ErrorAction SilentlyContinue)){
    Write-ServerMsg "Server is not installed : Installing $($Server.Name) Server."
    Update-Server -UpdateType "Installing"
    Write-ServerMsg "Server successfully installed."
    $FreshInstall = $true
}

#---------------------------------------------------------
# If Server is running warn players then stop server
#---------------------------------------------------------
Write-ScriptMsg "Verifying Server State..."
#If the server is not freshly installed.
if (-not $FreshInstall) {
    Stop-Server
}

#---------------------------------------------------------
# Backup
#---------------------------------------------------------

#If not a fresh install and Backups are enabled, run backups.
if ($Backups.Use -and -not $FreshInstall) {
    Write-ScriptMsg "Verifying Backups..."
    Backup-Server
}

#---------------------------------------------------------
# Update
#---------------------------------------------------------

#If not a fresh install, update and/or validate server.
if (-not $FreshInstall -and $Server.AutoUpdates) {
    Write-ScriptMsg "Updating Server..."
    Update-Server -UpdateType "Updating"
    Write-ServerMsg "Server successfully updated and/or validated."
}

#---------------------------------------------------------
# Register Scheduled Task
#---------------------------------------------------------

if ($Server.AutoUpdates -and -not (Get-ScheduledTask -TaskName "Tasks-$($server.UID)" -ErrorAction SilentlyContinue)) {
    Write-ScriptMsg "Registering Scheduled Tasks Check for $($Server.UID)..."
    Register-Task
}

#---------------------------------------------------------
# Start Server
#---------------------------------------------------------

#Try to start the server, then if it's stable, set the priority and affinity then register the PID. Exit with Error if it fails.
Start-Server

#---------------------------------------------------------
# Open FreshInstall Configuration folder
#---------------------------------------------------------

if ($FreshInstall -and (Test-Path -Path $Server.ConfigFolder -PathType "Container" -ErrorAction SilentlyContinue)) {
    Write-Warning -Message "Stopping the Server to let you edit the configurations files."
    #Stop Server because configuration is probably bad anyway
    Stop-Server
    & explorer.exe $Server.ConfigFolder
    Write-Warning -Message "Launch again when the server configurations files are edited."
    Read-Host "Press Enter to close this windows."
}

#---------------------------------------------------------
# Cleanup
#---------------------------------------------------------

#Remove old log files.
try {
    Write-ScriptMsg "Deleting logs older than $($Global.Days) days."
    Remove-OldLog
}
catch {
    Exit-WithError -ErrorMsg "Unable clean old logs."
}


#---------------------------------------------------------
# Unlock Process
#---------------------------------------------------------

Unlock-Process

Write-ServerMsg "Script successfully completed."

#---------------------------------------------------------
# Stop Logging
#---------------------------------------------------------

Stop-Transcript