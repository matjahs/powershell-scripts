[CmdletBinding()]

param(
    [parameter(Mandatory = $true)]
    [string]$vsphere_user,

    [parameter(Mandatory = $true)]
    [string]$vsphere_password,

    [parameter(Mandatory = $true)]
    [ValidateSet('DEV', 'PRD')]
    [string]$targetenvironment = 'DEV',

    [parameter(Mandatory = $true)]
    [string]$vmname

)

# Define target environment
switch ( $targetenvironment ) {
    "DEV" {
        $Vcenters = @("umcvct01.umcn.nl")
        $varfile = 'vars_tst.json'
        Write-Log -Message "The following vCenter servers have been filtered {0}" -Arguments ( $Vcenters -join ", " )  -Level DEBUG
    }
    "PRD" {
        $Vcenters = @("umcvcp01.umcn.nl")
        $varfile = 'vars_prd.json'
        Write-Log -Message "The following vCenter servers have been filtered {0}" -Arguments ( $Vcenters -join ", " )  -Level DEBUG
    }
}

.\packer.exe build "-var-file=Win2019\vars_tst.json" -var "vsphere-server=$Vcenters" -var "vsphere-user=$vsphere_user" -var "vsphere-password=$vsphere_password" -var "vm-name=$vmname" 'Win2019\windows2019.json'