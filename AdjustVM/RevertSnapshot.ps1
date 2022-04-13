<#
.SYNOPSIS
This script is used to automate the revert of a Snapshot of server.

.NOTES
Author       		: Emile Cox
Last Modified		: 2021-November-18
Used Modules 		: VMware.VimAutomation.Core / Topdesk
Requirements 		: 
Version      		: 0.1
Version info		: - Script creation

.EXAMPLE
PS 'S:\Build\VSTS\r14\a\AdjustVM\drop\ReverSnapshot.ps1' -VMname INFRATST402 -vcusername *** -vcpassword *** -targetenvironment DEV -ChangeNR CR01234567 -CreateSnapshotChangeNR CR01234566

Description
----------
This script will connect to vCenter to revert a snapshot created by the automated create snapshot request. You need to provide the ChangeNR of the original create snpashot request.
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
    [string]$CreateSnapshotChangeNR
)
# Forcing TLS12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

# Import required modules
$env:PSModulePath = "$(Resolve-Path '.\Modules');" + $env:PSModulePath

Import-Module VMware.VimAutomation.Core
Import-Module RemedyForce

# Define Logging Options, Please not that the logging to file is optional
Add-LoggingTarget -Name AzureDevOpsConsole -Configuration @{Level = 'DEBUG' }

# Define target environment
switch ( $targetenvironment ) {
    "DEV" {
        $Vcenters = @("umcvct01.umcn.nl")
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
    
    # Revert Snapshot
    Write-Log -Message "Checking for multiple snapshots for {0}" -Arguments $Vm -Level INFO    
    if ((get-vm $Vm | Get-Snapshot).length -gt 1) {
        throw  'Found multiple snapshots, please cleanup first'
    }

    Write-Log -Message "Reverting automated snapshot for {0} related to {1}" -Arguments @($VMname, $CreateSnapshotChangeNR) -Level INFO
    $SnapshotName = Get-Snapshot -VM $Vm -Name *$CreateSnapshotChangeNR*
    if ($SnapshotName -eq $null) {
        throw  'Snapshot not found, please check original ChangeNR'
    }
    else {
        Set-VM $Vm -Snapshot $SnapshotName -Confirm:$false
        Write-Log -Message "Reverted automated snapshot for {0} related to {1}" -Arguments @($VMname, $CreateSnapshotChangeNR) -Level INFO
    }

    Write-Log -Message "Checking if VM {0} is powered off." -Arguments $Vm -Level INFO
        If ( ($Vm = Get-VM -Name $VMname -Server $Server -ErrorAction Stop).PowerState -eq "PoweredOff" ) {
            Write-Log -Message "Powering On {0}" -Arguments $Vm -Level INFO
            Start-VM -VM $Vm -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Log -Message "Checking if VMtools is running to confirm succesfull startup of {0}" -Arguments $Vm -Level INFO
            If ( ($Vm = Get-VM -Name $VMname -Server $Server -ErrorAction Stop).ExtensionData.Guest.ToolsRunningStatus -eq "guestToolsRunning" ) {
                Write-Log -Message "VMtools is running. {0} Started succesfully" -Arguments $Vm -Level INFO
            }
            else {
                $Iteration = 0
                while ( ( ($Vm = Get-VM -Name $VMname -Server $Server -ErrorAction Stop).ExtensionData.Guest.ToolsRunningStatus -ne "guestToolsRunning") -and ($Iteration -le 15) ) {
                    $Iteration++
                    Write-Log -Message "Startup Check iteration {0} on {1}" -Arguments @($Iteration, $VM) -Level INFO
                    start-sleep -Seconds 10
            
                    If ( $Iteration -eq 15 ) {
                        throw "Didn't start on time, please troubleshoot"
                    }
                
                    elseIf ( ($Vm = Get-VM -Name $VMname -Server $Server -ErrorAction Stop).ExtensionData.Guest.ToolsRunningStatus -eq "guestToolsRunning") {
                        Write-Log -Message "VMtools is running. {0} Started succesfully" -Arguments $Vm -Level INFO
                    }
         
                }
            }
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