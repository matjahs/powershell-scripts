[CmdletBinding()]

param(
    [parameter(Mandatory = $true)]
    [string]$vsphere_server,

    [parameter(Mandatory = $true)]
    [string]$vsphere_user,

    [parameter(Mandatory = $true)]
    [string]$vsphere_password,

    [parameter(Mandatory = $true)]
    [ValidateSet('DEV', 'PRD')]
    [string]$targetenvironment = 'DEV',

    [parameter(Mandatory = $true)]
    [string]$vmname,

    [parameter(Mandatory = $true)]
    [string]$cluster,

    [parameter(Mandatory = $true)]
    [string]$disksize
)

.\packer.exe build -var 'vsphere-server=$vsphere_server' -var 'vsphere-user=$vsphere_user' -var 'vsphere-password=$vsphere_password' -var 'vm-name=$vmname' -var 'vsphere-cluster=$cluster' -var 'os-disk-size=$disksize' 'Win2019\windows2019.json'