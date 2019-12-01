
variable "private_key_path" {
    type = string
    default = "~/.ssh/id_rsa"
}

variable "public_key_path" {
    type = string
    default = "~/.ssh/id_rsa.pub"
}

provider "azurerm" {
}

# Azure
resource "azurerm_resource_group" "awsazvpn_azrg" {
  name     = "awsazvpn_azrg"
  location = "East US"
}

resource "azurerm_virtual_network" "awsazvpn_azvnet" {
  name                = "awsazvpn_azvnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.awsazvpn_azrg.location
  resource_group_name = azurerm_resource_group.awsazvpn_azrg.name
}

resource "azurerm_subnet" "awsazvpn_azsubnet" {
  name                 = "awsazvpn_azsubnet"
  resource_group_name  = azurerm_resource_group.awsazvpn_azrg.name
  virtual_network_name = azurerm_virtual_network.awsazvpn_azvnet.name
  address_prefix       = "10.0.1.0/24"
}

resource "azurerm_route_table" "awsazvpn_azrt" {
  name                = "awsazvpn_azrt"
  location            = azurerm_resource_group.awsazvpn_azrg.location
  resource_group_name = azurerm_resource_group.awsazvpn_azrg.name

  route {
    name                   = "awsazvpn_azroute_1"
    address_prefix         = "172.31.64.0/24"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_network_interface.awsazvpn_azpublicnic.private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "awsazvpn_azrtassoc" {
  subnet_id      = azurerm_subnet.awsazvpn_azsubnet.id
  route_table_id = azurerm_route_table.awsazvpn_azrt.id
}

resource "azurerm_network_security_group" "awsazvpn_aznsg" {
  name                = "awsazvpn_aznsg"
  location            = azurerm_resource_group.awsazvpn_azrg.location
  resource_group_name = azurerm_resource_group.awsazvpn_azrg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "awsazvpn_azpublicip" {
  name                = "awsazvpn_azpublicip"
  location            = azurerm_resource_group.awsazvpn_azrg.location
  resource_group_name = azurerm_resource_group.awsazvpn_azrg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "awsazvpn_azpublicnic" {
  name                      = "awsazvpn_azpublicnic"
  location                  = azurerm_resource_group.awsazvpn_azrg.location
  resource_group_name       = azurerm_resource_group.awsazvpn_azrg.name
  network_security_group_id = azurerm_network_security_group.awsazvpn_aznsg.id
  enable_ip_forwarding      = "true"

  ip_configuration {
    name                          = "awsazvpn_azprivateip"
    subnet_id                     = azurerm_subnet.awsazvpn_azsubnet.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.awsazvpn_azpublicip.id
  }
}

resource "azurerm_virtual_machine" "awsazvpn_azvpnserver" {
  name                             = "awsazvpn_azvpnserver"
  location                         = azurerm_resource_group.awsazvpn_azrg.location
  resource_group_name              = azurerm_resource_group.awsazvpn_azrg.name
  network_interface_ids            = [azurerm_network_interface.awsazvpn_azpublicnic.id]
  vm_size                          = "Standard_DS1_v2"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "vpn-osdisk-1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "azvpnserver"
    admin_username = "ubuntu"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/ubuntu/.ssh/authorized_keys"
      key_data = file("${var.public_key_path}")
    }
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y -qq",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq software-properties-common",
      "sudo add-apt-repository ppa:ansible/ansible -y",
      "sudo apt-get update -y -qq",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ansible",
    ]
    connection {
      host        = azurerm_public_ip.awsazvpn_azpublicip.ip_address
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
    }
  }
  provisioner "file" {
    source      = "./${local_file.aws_ansible_vars.filename}"
    destination = "/home/ubuntu/${local_file.aws_ansible_vars.filename}"
    connection {
      host        = azurerm_public_ip.awsazvpn_azpublicip.ip_address
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
    }
  }
  provisioner "file" {
    source      = "./awsazvpn_az_ansible.yaml"
    destination = "/home/ubuntu/awsazvpn_az_ansible.yaml"
    connection {
      host        = azurerm_public_ip.awsazvpn_azpublicip.ip_address
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
    }
  }
  provisioner "file" {
    source      = var.private_key_path
    destination = "/home/ubuntu/.ssh/id_rsa"
    connection {
      host        = azurerm_public_ip.awsazvpn_azpublicip.ip_address
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
    }
  }
}

resource "local_file" "azure_ansible_vars" {
  content  = "azure_public_ip: ${azurerm_public_ip.awsazvpn_azpublicip.ip_address}\nazure_vpn_subnet: ${azurerm_subnet.awsazvpn_azsubnet.address_prefix}\nazure_private_ip: ${azurerm_network_interface.awsazvpn_azpublicnic.private_ip_address}"
  filename = "./azure_ansible_vars.yml"
}

resource "null_resource" "azure_exec" {
  triggers = {
    azurerm_virtual_machine_id = azurerm_virtual_machine.awsazvpn_azvpnserver.id # Needed this trigger because azurerm_public_ip is created before the VM is built.  So this would execute before the VM was ready.
  }
  provisioner "remote-exec" {
    inline = ["ansible-playbook awsazvpn_az_ansible.yaml"]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
      host        = azurerm_public_ip.awsazvpn_azpublicip.ip_address
    }
  }
}

resource "null_resource" "azure_restart_ipsec" {
  depends_on = [
    null_resource.azure_exec,
    null_resource.aws_exec,
  ]

  provisioner "remote-exec" {
    inline = ["sudo systemctl restart strongswan"]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
      host        = azurerm_public_ip.awsazvpn_azpublicip.ip_address
    }
  }
}

/*
/* THIS BLOCK SHOULD BE MOVED
resource "azurerm_network_interface" "testVMNIC" {
  name                      = "testvm_NIC"
  location                  = azurerm_resource_group.awsazvpn_azrg.location
  resource_group_name       = azurerm_resource_group.awsazvpn_azrg.name
  network_security_group_id = azurerm_network_security_group.nsg.id

  ip_configuration {
    name                          = "testVM_privateIP"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "dynamic"
  }

  tags = {
    environment = "Test VM"
  }
}

resource "azurerm_virtual_machine" "test_vm" {
  name                             = "test_vm"
  location                         = "${azurerm_resource_group.awsazvpn_azrg.location}"
  resource_group_name              = "${azurerm_resource_group.awsazvpn_azrg.name}"
  network_interface_ids            = ["${azurerm_network_interface.testVMNIC.id}"]
  vm_size                          = "Standard_DS1_v2"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "testvm-osdisk-1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "azuretestvm"
    admin_username = "ubuntu"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/ubuntu/.ssh/authorized_keys"
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCzyQehHEk01+XCMwdTIUHZCu7LIW5Ewx8PnBxw6y7/hKw9qKun1wfn5+NJgc5Dzj8JLBY51TGNdWxOr13e3dz2uizVw6j3tFSgHBT2ifGB/+ET7K8MCY/OUmjqbzukoYswGLQP+03VvwIySeFPfOcDy7i2HfOHYBMFPLA/5glHqDca0pY4+8AHNbrtXOPBMuNBkb05jhL9WcMdOeTq1vErhK04E6aj6Ky+o0oxUEHRgQHyCchkUsvbEexzK4hMMicwnURcMtdyiLab+cJ33//V7ByKvogkEq3RJDDLePNiZSSDldSEWsrQJePRGmcGsQ1jsFjI1JKW0A07PxU98tCT"
    }
  }
}
*/

output "azure_vpn_subnet" {
  value = azurerm_subnet.awsazvpn_azsubnet.address_prefix
}

output "azure_public_ip" {
  value = azurerm_public_ip.awsazvpn_azpublicip.ip_address
}

output "azure_private_ip" {
  value = azurerm_network_interface.awsazvpn_azpublicnic.private_ip_address
}

/*
output "azure_testvm_private_ip" {
  value = "${azurerm_network_interface.testVMNIC.private_ip_address}"
}
*/
