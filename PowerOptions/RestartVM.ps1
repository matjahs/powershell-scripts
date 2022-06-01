<#
.SYNOPSIS
This script is used to automate the restart of servers.

.NOTES
Author       		: Emile Cox
Last Modified		: 2022-June-3
Used Modules 		: VMware.VimAutomation.Core / TopDesk
Requirements 		: VMware tools installed
Version      		: 1.0
Version info		: - Script creation

.EXAMPLE
PS 'S:\Build\VSTS\r14\a\AdjustVM\drop\Restartvm.ps1' -VmName INFRATST402 -vcusername *** -vcpassword *** -targetenvironment DEV

Description
-----------
This script will connect to vCenter to restart a VM. It will check if the OS is supported and uses VMware tools do perform a clean restart.
#>

[CmdletBinding()]

param(
    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[^*^?]+$')]
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
    [string]$requestor,

    [parameter(Mandatory = $true)]
    [string]$scheduled,

    [parameter(Mandatory = $false)]
    [string]$scheduledTime,

    [parameter(Mandatory = $false)]
    [string]$znumber
)

# Forcing TLS12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

# Import required modules
# $env:PSModulePath = "$(Resolve-Path '.\Modules');" + $env:PSModulePath

Import-Module VMware.VimAutomation.Core
Import-module ActiveDirectory
Import-Module Logging
# Import-Module Topdesk

# Define Logging Options, Please not that the logging to file is optional
Add-LoggingTarget -Name Console -Configuration @{Level = 'DEBUG' }

# Check if requester has permissions to restart this server
$Permissions = get-adgroupmember -identity "DLG.IM.Serverbeheer.$VMname"
if ("$permissions.SamAccountName" -match "$znumber") 
    {Write-Log -Message "Requester has administrator permissions on the server, continuing request"}
else 
    {throw "Requester doesn't have administrator permissions on this server, abonding request"}

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
    Write-Log -Message "Disabling alarms actions on {0}" -Arguments $Vm -Level INFO
    $AlarmMgr = get-view AlarmManager -Server $Server -ErrorAction Stop
    $AlarmMgr.EnableAlarmActions($Vm.Extensiondata.MoRef, $false) | Out-Null

    Write-Log -Message "Checking if VMtools is running on {0}" -Arguments $Vm -Level INFO

        if ( ($Vm = Get-VM -Name $VMname -Server $Server -ErrorAction Stop).PowerState -eq "PoweredOff" ) {
            throw  "VM is turned off, not able to perform or schedule a restart"
        }
        elseIf ( $Vm.ExtensionData.Guest.ToolsRunningStatus -eq "guestToolsRunning" ) {
            
                Write-Log -Message "Checking if Restart for {0} must be scheduled" -Arguments $Vm -Level INFO    
            if ($Scheduled -eq "true") {
                $RestartName = 'Automated Restart Guest OS of {0} for {1}' -f ($Vm,$ChangeNR)              
                Write-Log -Message "Scheduling Restart Guest OS for {0} on {1} UTC" -Arguments @($Vm, $scheduledTime) -Level INFO
                $si = get-view ServiceInstance -Server $Server
                $scheduledTaskManager = Get-View $si.Content.ScheduledTaskManager -Server $Server
                $spec = New-Object VMware.Vim.ScheduledTaskSpec
                $spec.Name = "$RestartName"
                $spec.Description = "Restart Guest OS $($vm.Name)"
                $spec.Enabled = $true
                $spec.Notification = $requestor
                $spec.Scheduler = New-Object VMware.Vim.OnceTaskScheduler
                $spec.Scheduler.runat = (Get-Date $scheduledTime)
                $spec.Action = New-Object VMware.Vim.MethodAction
                $spec.Action.Name = "RebootGuest"
                $scheduledTaskManager.CreateObjectScheduledTask($vm.ExtensionData.MoRef, $spec)
                Write-Log -Message "Scheduled Restart Guest OS for VM {0} successfully." -Arguments $Vm -Level INFO
            }       
                    
            elseif ($Scheduled -eq "false") { 
                Write-Log -Message "Shutdown {0}" -Arguments $Vm -Level INFO
                Stop-VMGuest -VM $Vm -Server $Server -Confirm:$false -ErrorAction Stop | Out-Null

                $Iteration = 0
                while ( ( ($Vm = Get-VM -Name $VMname -Server $Server -ErrorAction Stop).PowerState -ne "PoweredOff") -and ($Iteration -le 10) ) {
                    $Iteration++
                    Write-Log -Message "Shutdown Check iteration {0} on {1}" -Arguments @($Iteration, $VM) -Level INFO
                    start-sleep -Seconds 30
                }

                If ( $Iteration -eq 10 ) {
                    Write-Log -Message "{0} Didn't PoweredOff on time now forcing an PowerOff" -Arguments $VM -Level WARNING
                    Stop-VM -VM $Vm -Confirm:$false -ErrorAction Stop | Out-Null
                    If ( ($Vm = Get-VM -Name $VMname -Server $Server -ErrorAction Stop).PowerState -ne "PoweredOff" ) {
                        throw "Not able to shutdown the VM"
                    }
                }

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
            }
        }
        elseif ( $Vm.ExtensionData.Guest.ToolsRunningStatus -ne "guestToolsRunning" ) {
            throw  "VMware tools is not running, not able to perform or schedule a restart"
        }
    
    Write-Log -Message "Enabling alarms actions on {0}" -Arguments $Vm -Level INFO
    $AlarmMgr.EnableAlarmActions($Vm.Extensiondata.MoRef, $true) | Out-Null
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