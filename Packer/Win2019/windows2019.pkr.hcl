packer {
  required_plugins {
    vmware = {
      version = ">= 1.0.7"
      source  = "github.com/hashicorp/vmware"
    }
  }
}

source "vsphere-iso" "win_2019" {
  vm_name = var.vm_name

  CPUs                 = var.vm_cpu_num
  RAM                  = var.vm_mem_size
  RAM_reserve_all      = true
  cluster              = var.vsphere_cluster
  communicator         = var.vm_communicator
  convert_to_template  = true
  datacenter           = var.vsphere_datacenter
  datastore            = var.vsphere_datastore
  disk_controller_type = [var.vm_disk_controller_type]
  firmware             = var.vm_firmware

  floppy_files = [
    "Win2019/autounattend.xml",
    "Win2019/scripts/disable_network_discovery.cmd",
    "Win2019/scripts/disable_server_manager.ps1",
    "Win2019/scripts/enable_rdp.cmd",
    "Win2019/scripts/enable_winrm.ps1",
    "Win2019/scripts/install_vm_tools.cmd",
    "Win2019/scripts/set_temp.ps1"
  ]

  folder              = var.vsphere_folder
  guest_os_type       = var.vm_guest_os_type
  insecure_connection = "true"
  iso_paths           = [
    local.iso_path,
    "[] /vmimages/tools_isoimages/windows.iso"
  ]

  network_adapters {
    network      = var.vsphere_network
    network_card = var.vm_nic
  }

  password         = var.vsphere_password
  shutdown_command = "shutdown /s /t 5"

  storage {
    disk_size             = 40960
    disk_thin_provisioned = var.vm_disk_thin_provision
  }

  username       = var.vsphere_user
  vcenter_server = var.vsphere_server

  winrm_password = var.winrm_password
  winrm_timeout  = var.winrm_timeout
  winrm_username = var.winrm_username
}

build {
  sources = [
    "source.vsphere-iso.win_2019"
  ]

  provisioner "powershell" {
    inline = ["ipconfig /all"]
  }

  provisioner "ansible-local" {
    playbook_file = "../../Ansible/site.yml"
    role_paths = [
      "../../Ansible/roles/iis"
    ]
    group_vars = "../../Ansible/group_vars"
  }
}
