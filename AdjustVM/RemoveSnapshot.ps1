<#
.SYNOPSIS
This script is used to automate the creation of Snapshot of servers.

.NOTES
Author       		: Emile Cox
Last Modified		: 2022-june-9
Used Modules 		: VMware.VimAutomation.Core / Topdesk
Requirements 		: 
Version      		: 0.9
Version info		: - Script creation

.EXAMPLE
PS 'S:\Build\VSTS\r14\a\AdjustVM\drop\RemoveSnapshot.ps1' -VMname INFRATST402 -vcusername *** -vcpassword *** -targetenvironment DEV -ChangeNR CR01234567 -Scheduled true

Description
-----------
This script will connect to vCenter to remove a snapshot based on the description and provided changeNR of the "create snapshot request".
#>

[CmdletBinding()]

param(
    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('(?=.*\S)(?=^[^*^?]+$)')]
    [string]$VMname,

    [parameter(Mandatory = $true)]
    [string]$vcusername,

    [parameter(Mandatory = $true)]
    [string]$vcpassword,

    [parameter(Mandatory = $true)]
    [ValidateSet('DEV', 'PRD')]
    [string]$targetenvironment = 'DEV',

    [parameter(Mandatory = $true)]
    [string]$ChangeNR,

    [parameter(Mandatory = $true)]
    [string]$scheduled
)

# Forcing TLS12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

# Import required modules
# $env:PSModulePath = "$(Resolve-Path '.\Modules');" + $env:PSModulePath

Import-Module VMware.VimAutomation.Core
Import-Module Logging
# Import-Module Topdesk

# Define Logging Options, Please not that the logging to file is optional
Add-LoggingTarget -Name Console -Configuration @{Level = 'DEBUG' }

# Define target environment
switch ( $targetenvironment ) {
    "DEV" {
        $Vcenters = @("umcvct01.umcn.nl", "umcvct02.umcn.nl")
        Write-Log -Message "The following vCenter servers have been filtered {0}" -Arguments ( $Vcenters -join ", " )  -Level DEBUG
    }
    "PRD" {
        $Vcenters = @("umcvcp01.umcn.nl", "umcvcp02.umcn.nl")
        Write-Log -Message "The following vCenter servers have been filtered {0}" -Arguments ( $Vcenters -join ", " )  -Level DEBUG
    }
}

# Build vCenter-credential
$secpasswd = ConvertTo-SecureString -String $vcpassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($vcusername, $secpasswd)

# Perform Actions
try {
    Write-Log -Message "Connecting to vCenters {0}" -Arguments ($Vcenters -join " ") -Level INFO
    Connect-VIServer -Server $Vcenters -Credential $credential -Force -ErrorAction Stop
    Write-Log -Message "Finding non placeholder vm object with name {0}" -Arguments $VMname -Level INFO
    $Vm = Get-VM -Name $VMname -ErrorAction Stop | Where-Object { !$_.ExtensionData.Summary.Config.ManagedBy.Type }

    if ($vm.count -gt 1) {
        throw  'Multiple VMs selected, exiting...'
    }
    Write-Log -Message "Defining connected vCenter using regex" -Level DEBUG
    $Regex = 'https?://([a-zA-Z0-9.]+)/sdk'
    $Vm.ExtensionData.Client.ServiceUrl -match $Regex | Out-Null
    $Server = $global:DefaultVIServers | where-object { $_.Name -eq $Matches[1] }
    Write-Log -Message "Connected vCenter is {0}" -Arguments $Server -Level INFO
    
    Write-Log -Message "Checking if snapshot for {0} was scheduled" -Arguments $Vm -Level INFO    
    if ($Scheduled -eq "true") {
        $SnapshotName = 'automated scheduled snapshot for {0}' -f $ChangeNR
        $PoweronName = 'Power on {0} for {1}' -f ($Vm,$ChangeNR)
        Write-Log -Message "Removing automated scheduled snapshot for {0} related to {1}" -Arguments @($VMname, $ChangeNR) -Level INFO
              if (get-vm $Vm | Get-Snapshot) {
                Get-Snapshot -VM $Vm -Name $SnapshotName | Remove-Snapshot -Confirm:$false
                Write-Log -Message "Removed {0} successful." -Arguments $SnapshotName -Level INFO
              }
              else {
                  Write-Log -Message "No shapshot found for {0}, continuing removing Scheduled task." -Arguments $VMname -level Warning              
              }
        Write-Log -Message "Removing scheduled task for {0} related to {1}" -Arguments @($VMname, $ChangeNR) -Level INFO
        $si = Get-View ServiceInstance -Server $Server
        $scheduledTaskManager = Get-View $si.Content.ScheduledTaskManager -Server $Server
        Get-View -Id $scheduledTaskManager.ScheduledTask | where{$_.Info.Name -match $SnapshotName -or $_.Info.Name -match $PoweronName} |%{$_.RemoveScheduledTask()}
        Write-Log -Message "Removed scheduled task for {0} successful." -Arguments $VMName -Level INFO
    }

    elseif ($Scheduled -eq "false") {   
        $SnapshotName = 'automated snapshot for {0}' -f $ChangeNR
        Write-Log -Message "Removing automated snapshot for {0} related to {1}" -Arguments @($VMname, $ChangeNR) -Level INFO
        Get-Snapshot -VM $Vm -Name $SnapshotName | Remove-Snapshot -Confirm:$false
        Write-Log -Message "Removed {0} successful." -Arguments $SnapshotName -Level INFO 
    }

    Disconnect-Viserver -Server * -Confirm:$false
}
catch {
    Throw $error
    Disconnect-Viserver -Server * -Confirm:$false
}
finally {
    # Wait for async logging is complete so no log messages are missed
    Wait-Logging
}