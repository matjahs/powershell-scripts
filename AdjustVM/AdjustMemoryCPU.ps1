<#
.SYNOPSIS
This script is used to automate the adjustment of CPU and/or Memory of servers.

.NOTES
Author       		: Emile Cox
Last Modified		: 2021-November-17
Used Modules 		: VMware.VimAutomation.Core / Topdesk
Requirements 		: HotAdd CPU and Memory enabled
Version      		: 0.1
Version info		: - Script creation

.EXAMPLE
PS 'S:\Build\VSTS\r14\a\AdjustVM\drop\AdjustMemoryCPU.ps1' -VmName INFRATST402 -vcusername *** -vcpassword *** -targetenvironment DEV -CPU 2 -Memory 8

Description
-----------
This script will connect to vCenter to adjust CPU or Memory. It will check if the OS is supported and if HotAdd is enabled. If CPU or Memory will be decreased VM will be turned off temporary.
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
    [ValidateSet(0,1,2,4,6,8,10,12,16)]
    [int]$CPU,
    
    [parameter(Mandatory = $true)]
    [ValidateSet(0,4,8,16,20,24,28,32,40,48,56,64)]
    [int]$Memory
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
    $VcenterConnections = Connect-VIServer -Server $Vcenters -Credential $credential -Force -ErrorAction Stop
    Write-Log -Message "Finding non placeholder vm object with name {0}" -Arguments $VMname -Level INFO
    $Vm = Get-VM -Name $VMname -ErrorAction Stop | Where-Object { !$_.ExtensionData.Summary.Config.ManagedBy.Type }

    if ($vm.count -gt 1) {
        throw  'Multiple VMs selected, exiting...'
    }
    Write-Log -Message "Defining connected vCenter using regex" -Level DEBUG
    $Regex = 'https?://([a-zA-Z0-9.]+)/sdk'
    $Vm.ExtensionData.Client.ServiceUrl -match $Regex | Out-Null
    $Server = $VcenterConnections | where-object { $_.Name -eq $Matches[1] }
    Write-Log -Message "Connected vCenter is {0}" -Arguments $Server -Level INFO
    Write-Log -Message "Disabling alarms actions on {0}" -Arguments $Vm -Level INFO
    $AlarmMgr = get-view AlarmManager -Server $Server -ErrorAction Stop
    $AlarmMgr.EnableAlarmActions($Vm.Extensiondata.MoRef, $false) | Out-Null

    Write-Log -Message "Checking if CPU or Memory field is not filled in for {0}" -Arguments $Vm -Level INFO

    if ($CPU -eq 0) {
        $CPU = $Vm.NumCPU
        Write-Log -Message "CPU not filled in, number of CPU's is {0}" -Arguments $CPU -Level INFO
    }
    
    if ($Memory -eq 0) {
        $Memory = $Vm.MemoryGB
        Write-Log -Message "Memory not filled in, Memory is {0}" -Arguments $Memory -Level INFO
    }
       
    Write-Log -Message "Checking if Hot Add CPU is disabled for {0}" -Arguments $Vm -Level INFO

    if ($Vm.ExtensionData.Config.CpuHotAddEnabled -eq $False) {   
        throw  "Hot Add CPU is disabled, please perform change manually as the vm needs to be turned off to adjust CPU"
    }
    Write-Log -Message "Checking if Hot Add Memory is disabled for {0}" -Arguments $Vm -Level INFO

    if ($Vm.ExtensionData.Config.MemoryHotAddEnabled -eq $False) {   
        throw  "Hot Add Memory is disabled, please perform change manually as the vm needs to be turned off to adjust Memory"
    }

    Write-Log -Message "Checking if CPU's or Memory should be decreased on {0}" -Arguments $Vm -Level INFO

    if ($Vm.NumCPU -gt $CPU -Or $Vm.MemoryGB -gt $Memory) {
        throw  "CPU's or Memory should be decreased, please perform change manually as the vm needs to be turned off to decrease"
        <# Write-Log -Message "VM {0} shutting down to make CPU or Memory decrease possible" -Arguments $Vm -Level INFO 
        Write-Log -Message "Checking if VMtools is running on {0}" -Arguments $Vm -Level INFO

        if ( ($Vm = Get-VM -Name $VMname -Server $Server -ErrorAction Stop).PowerState -eq "PoweredOff" ) {
            Write-Log -Message "{0} already PoweredOff " -Arguments $VM -Level WARNING
        }
        elseIf ( $Vm.ExtensionData.Guest.ToolsRunningStatus -eq "guestToolsRunning" ) {
            Write-Log -Message "Shutdown {0}" -Arguments $Vm -Level INFO
            Stop-VMGuest -VM $Vm -Server $Server -Confirm:$false -ErrorAction Stop | Out-Null

            $Iteration = 0
            while ( ( ($Vm = Get-VM -Name $VMname -Server $Server -ErrorAction Stop).PowerState -ne "PoweredOff") -and ($Iteration -le 10) ) {
                $Iteration++
                Write-Log -Message "Shutdown Check iteration {0} on {1}" -Arguments @($Iteration, $VM) -Level INFO
                start-sleep -Seconds 10
            }

            If ( $Iteration -eq 10 ) {
                Write-Log -Message "{0} Didn't PoweredOff on time now forcing an PowerOff" -Arguments $VM -Level WARNING
                Stop-VM -VM $Vm -Confirm:$false -ErrorAction Stop | Out-Null
                If ( ($Vm = Get-VM -Name $VMname -Server $Server -ErrorAction Stop).PowerState -ne "PoweredOff" ) {
                    throw "Not able to shutdown the VM"
                }

            }

        }
        elseif ( $Vm.ExtensionData.Guest.ToolsRunningStatus -ne "guestToolsRunning" ) {
            Write-Log -Message "Powering Off {0} since VMtools are not running" -Arguments $Vm -Level WARNING
            Stop-VM -VM $Vm -Confirm:$false -ErrorAction Stop | Out-Null
        }#>
    }

    Write-Log -Message "Adjusting CPU to {0} and Memory to {1} for {2}" -Arguments @($CPU, $Memory, $Vm) -Level INFO
    Set-VM -VM $Vm -NumCpu $CPU -MemoryGB $Memory -Confirm:$false -ErrorAction Stop | Out-Null
    
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