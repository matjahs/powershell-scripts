<#
.SYNOPSIS
This script is used to automate the creation of Snapshot of servers.

.NOTES
Author       		: Emile Cox
Last Modified		: 2021-November-18
Used Modules 		: VMware.VimAutomation.Core / RemedyForce
Requirements 		: 
Version      		: 0.1
Version info		: - Script creation

.EXAMPLE
PS 'S:\Build\VSTS\r14\a\AdjustVM\drop\CreateSnapshot.ps1' -VMname INFRATST402 -vcusername *** -vcpassword *** -targetenvironment DEV -ChangeNR CR01234567 -requestor emile.cox@radboudumc.nl -scheduled True -snapshotTime "2021-03-16 14:30:00"

Description
----------
This script will connect to vCenter to create or schedule a snapshot.
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
    [string]$requestor,

    [parameter(Mandatory = $true)]
    [string]$scheduled,

    [parameter(Mandatory = $false)]
    [string]$snapshotTime
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
    
    Write-Log -Message "Checking for existing snapshots for {0}" -Arguments $Vm -Level INFO    
    if  (get-vm $Vm | Get-Snapshot) {
        throw  'Found existing snapshot, please remove first'
    }

    Write-Log -Message "Checking if snapshot for {0} must be scheduled" -Arguments $Vm -Level INFO    
    if ($Scheduled -eq "true") {
        $SnapshotName = 'automated scheduled snapshot for {0}' -f $ChangeNR
        $PoweronName = 'Power on {0} for {1}' -f ($Vm,$ChangeNR)
        $SnapshotDescription = 'automated scheduled snapshot of {0} for {1} created on {2} UTC' -f ($Vm, $requestor, $SnapshotTime)
        $snapMemory = $false
        $snapQuiesce = $false
        Write-Log -Message "Scheduling snapshot for {0} on {1} UTC" -Arguments @($Vm, $SnapshotTime) -Level INFO
        $si = get-view ServiceInstance -Server $Server
        $scheduledTaskManager = Get-View $si.Content.ScheduledTaskManager -Server $Server
        $spec = New-Object VMware.Vim.ScheduledTaskSpec
        $spec.Name = "$SnapshotName"
        $spec.Description = "Take a snapshot of $($vm.Name)"
        $spec.Enabled = $true
        $spec.Notification = $requestor
        $spec.Scheduler = New-Object VMware.Vim.OnceTaskScheduler
        $spec.Scheduler.runat = (Get-Date $snapshotTime)
        $spec.Action = New-Object VMware.Vim.MethodAction
        $spec.Action.Name = "CreateSnapshot_Task"

        @($snapshotName, $snapshotDescription, $snapMemory, $snapQuiesce) | % {
            $arg = New-Object VMware.Vim.MethodActionArgument
            $arg.Value = $_
            $spec.Action.Argument += $arg
        }
        $scheduledTaskManager.CreateObjectScheduledTask($vm.ExtensionData.MoRef, $spec)
        Write-Log -Message "Scheduled snapshot for VM {0} successfully." -Arguments $Vm -Level INFO
        $spec = New-Object VMware.Vim.ScheduledTaskSpec
        $spec.Name = "$PoweronName"
        $spec.Description = "Power on $($vm.Name)"        
        $spec.Enabled = $true
        $spec.Scheduler = New-Object VMware.Vim.OnceTaskScheduler
        $spec.Scheduler.runat = (Get-Date $snapshotTime).AddMinutes(5)
        $spec.Action = New-Object VMware.Vim.MethodAction
        $spec.Action.Name = "PowerOnVM_Task"
        $scheduledTaskManager.CreateObjectScheduledTask($vm.ExtensionData.MoRef, $spec)
        Write-Log -Message "Scheduled Power on for VM {0} successfully." -Arguments $Vm -Level INFO
    }    
 
   elseif ($Scheduled -eq "false") {    
        $SnapshotName = 'automated snapshot for {0}' -f $ChangeNR
        $SnapshotDescription = 'automated snapshot of {0} for {1} created on {2}' -f $Vm, $requestor, ($(Get-Date))
        Write-Log -Message "Creating snapshot for {0}" -Arguments $Vm -Level INFO
        New-Snapshot -VM $Vm -Name $SnapshotName -Description $SnapshotDescription -ErrorAction Stop
        Write-Log -Message "Created snapshot for VM {0} successfully." -Arguments $Vm -Level INFO
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
    }
    
    Disconnect-Viserver -Server * -Confirm:$false

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($TopdeskUser):$($TopdeskToken)"))
    $Header = @{
        "authorization" = "Basic $base64AuthInfo"
    }

    $BodyJson = @( 
                    @{
                    "op": "replace",
                    "path": "/status",
                    "value": "Afgerond"
                    }
                )
    #send change update
    $Parameters = @{
        Method      = "PATCH"
        Uri         = "https://radboudumc-acceptatie.topdesk.net/tas/api/operatorChangeActivities/$ChangeNR"
        Headers     = $Header
        ContentType = "application/json"
        Body        = $BodyJson|ConverTo-Json  
    }
    Invoke-RestMethod @Parameters

}
catch {
    Throw $error
    Disconnect-Viserver -Server * -Confirm:$false

        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($TopdeskUser):$($TopdeskToken)"))
    $Header = @{
        "authorization" = "Basic $base64AuthInfo"
    }

    $BodyJson = @(
        @{
    "op": "replace",
    "path": "/status",
    "value": "Heropenen"
        }
    )
    #send change update
    $Parameters = @{
        Method      = "PATCH"
        Uri         = "https://radboudumc-acceptatie.topdesk.net/tas/api/operatorChangeActivities/$ChangeNR"
        Headers     = $Header
        ContentType = "application/json"
        Body        = $BodyJson
    }
    Invoke-RestMethod @Parameters

}
finally {
    # Wait for async logging is complete so no log messages are missed
    Wait-Logging
}