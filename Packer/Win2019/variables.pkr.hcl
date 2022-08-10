variable "vsphere_user" {
  type = string
  default = ""
}

variable "vsphere_server" {
  type = string
  default = ""
}

variable "vsphere_password" {
  type = string
  default = ""
  sensitive = true
}

variable "vsphere_datacenter" {
  type = string
  default = ""
}

variable "vsphere_cluster" {
  type = string
  default = ""
}

variable "vsphere_network" {
  type = string
  default = "VM Network"
}

variable "vsphere_datastore" {
  type = string
}

variable "vsphere_folder" {
  type = string
  default = "Templates"
}

variable "vm_name" {
  type = string
}

variable "vm_cpu_num" {
  type = number
  default = 2
}

variable "vm_mem_size" {
  type = number
  default = 4096
}

variable "vm_communicator" {
  type = string
  default = "bios"
}

variable "vm_nic" {
  type = string
  default = "vmxnet3"
}

variable "vm_os_disk_size" {
  type = number
  default = 40960
}

variable "vm_disk_controller_type" {
  type = string
  default = "lsilogic"

  validation {
    # @see https://www.packer.io/plugins/builders/vsphere/vsphere-iso#create-configuration
    condition = contains(["lsilogic", "lsilogic-sas", "pvscsi", "nvme", "scsi"], var.vm_disk_controller_type)
    error_message = "The vm_firmware value must be one of the following: 'bios', 'uefi'."
  }
}

variable "vm_disk_thin_provision" {
  type = bool
  default = true
}

variable "vm_guest_os_type" {
  # for a list of possible value run this command in Powershell:
  # `[VMware.Vim.VirtualMachineGuestOsIdentifier].GetEnumValues()`
  type = string
  default = "windows2019srv_64Guest"
}

variable "vm_os_iso_path" {
  type = string
  description = "Guest OS type. For a complete list of possible values, run [VMware.Vim.VirtualMachineGuestOsIdentifier].GetEnumValues()."
  default = "windows2019srv_64Guest"
}

variable "vm_firmware" {
  type = string
  default = "bios"

  validation {
    condition = contains(["bios", "uefi"], var.vm_firmware)
    error_message = "The vm_firmware value must be one of the following: 'bios', 'uefi'."
  }
}

variable "winadmin_password" {
  type = string
  sensitive = true
  default = ""
}

variable "winrm_username" {
  type = string
  default = "Administrator"
}

variable "winrm_password" {
  type = string
  sensitive = true
  default = "S3cr3t!@"
}

variable "winrm_timeout" {
  type = string
  default = "1h30m"

  validation {
    condition = can(regex("^[0-9]+h[0-9]{1,2}m$", var.winrm_timeout))
    error_message = "The winrm_timeout value must match pattern XXhXXm (example: 1h30m)."
  }
}

variable "iso_datastore" {
  type = string
}

variable "iso_filename" {
  type = string
}

locals {
  iso_path       = "[${var.iso_datastore}] ISO/${var.iso_filename}"
}
