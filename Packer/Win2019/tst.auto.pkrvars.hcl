vsphere_user = "Administrator@vsphere.local"
vsphere_password = "VMware1!"

vsphere_datacenter = "Datacenter Test01"
vsphere_cluster = "Test Cluster"
vsphere_network = "VM Network"
vsphere_datastore = "local_vmhost-r51"
vsphere_folder = "Templates"

vm_name = "Unnamed-VM"
vm_cpu_num = 2
vm_mem_size = 4096
vm_communicator = "winrm"
vm_os_disk_size = 40960
vm_disk_thin_provision = true
vm_disk_controller_type = "lsilogic"
vm_firmware = "bios" # "bios" or "uefi"
vm_nic = "vmxnet3"

# Windows 2019 Server
# for a list of possible value run this command in Powershell:
# `[VMware.Vim.VirtualMachineGuestOsIdentifier].GetEnumValues()`
vm_guest_os_type = "windows2019srv_64Guest"

iso_datastore = "local_vmhost-r51"
iso_filename = "SW_DVD9_Win_Server_STD_CORE_2019_1909.4_64Bit_English_DC_STD_MLF_X22-29333.ISO"

winrm_username = "Administrator"
winrm_password = "fkBg93j2AJyrRIRDdo6y!"
winrm_timeout = "1h30m"

#vmware_tools_url = "https://packages.vmware.com/tools/releases/latest/windows"