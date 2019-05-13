provider "azurerm" {
}

# Azure
resource "azurerm_resource_group" "rg" {
  name     = "phoebe_vpn_rg"
  location = "East US"
}

resource "azurerm_virtual_network" "network" {
  name                = "phoebe_vpn_vnet"
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
}

resource "azurerm_subnet" "subnet" {
  name                 = "phoebe_vpn_subnet"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  virtual_network_name = "${azurerm_virtual_network.network.name}"
  address_prefix       = "10.0.1.0/24"
}
resource "azurerm_route_table" "azureroutetable" {
  name                   = "phoebe_vpn_route_table"
  location               = "{$azurerm_resource_group.rg.location}"
  resource_group_name    = "${azurerm_resource_group.rg.name}"

  route {
    name                 = "phoebe_vpn_route_1"
    address_prefix         = "172.31.64.0/24"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "{$azurerm_network_interface.publicNIC.private_ip_address}"
  }
}
resource "azurerm_subnet_route_table_association" "azureroutetableassociation" {
  subnet_id      = "${azurerm_subnet.subnet.id}"
  route_table_id = "${azurerm_route_table.azureroutetable.id}"
}
resource "azurerm_network_security_group" "nsg" {
  name                = "TerraformSG"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"

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

resource "azurerm_public_ip" "publicip" {
  name                         = "phoebe_vpn_public_ip"
  location                     = "${azurerm_resource_group.rg.location}"
  resource_group_name          = "${azurerm_resource_group.rg.name}"
  allocation_method            = "Static"
}
resource "azurerm_network_interface" "publicNIC" {
  name                      = "phoebe_vpn_public_NIC"
  location                  = "${azurerm_resource_group.rg.location}"
  resource_group_name       = "${azurerm_resource_group.rg.name}"
  network_security_group_id = "${azurerm_network_security_group.nsg.id}"

  ip_configuration {
    name                          = "phoebe_vpn_privateIP"
    subnet_id                     = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.publicip.id}"
  }
}
resource "azurerm_network_interface" "testVMNIC" {
  name                      = "testvm_NIC"
  location                  = "${azurerm_resource_group.rg.location}"
  resource_group_name       = "${azurerm_resource_group.rg.name}"
  network_security_group_id = "${azurerm_network_security_group.nsg.id}"

  ip_configuration {
    name                          = "testVM_privateIP"
    subnet_id                     = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "dynamic"
  }

  tags {
    environment = "Test VM"
  }
}
resource "azurerm_virtual_machine" "terraform_vm" {
  name                             = "terraform_vm"
  location                         = "${azurerm_resource_group.rg.location}"
  resource_group_name              = "${azurerm_resource_group.rg.name}"
  network_interface_ids            = ["${azurerm_network_interface.publicNIC.id}"]
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
    name              = "osdisk-1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "strongsean"
    admin_username = "ubuntu"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/ubuntu/.ssh/authorized_keys"
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCzyQehHEk01+XCMwdTIUHZCu7LIW5Ewx8PnBxw6y7/hKw9qKun1wfn5+NJgc5Dzj8JLBY51TGNdWxOr13e3dz2uizVw6j3tFSgHBT2ifGB/+ET7K8MCY/OUmjqbzukoYswGLQP+03VvwIySeFPfOcDy7i2HfOHYBMFPLA/5glHqDca0pY4+8AHNbrtXOPBMuNBkb05jhL9WcMdOeTq1vErhK04E6aj6Ky+o0oxUEHRgQHyCchkUsvbEexzK4hMMicwnURcMtdyiLab+cJ33//V7ByKvogkEq3RJDDLePNiZSSDldSEWsrQJePRGmcGsQ1jsFjI1JKW0A07PxU98tCT"
    }
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "sudo apt-get -y install software-properties-common",
      "sudo apt-add-repository --yes --update ppa:ansible/ansible",
      "sudo apt-get -y install ansible"
    ]
    connection {
      type = "ssh"
      user = "ubuntu"
      private_key = "${file("vpn.pem")}"
      }
  }
  provisioner "file" {
   source = "./${local_file.aws_ansible_vars.filename}"
   destination = "/home/ubuntu/${local_file.aws_ansible_vars.filename}"  
   connection {
    type = "ssh"
    user = "ubuntu"
    private_key = "${file("vpn.pem")}"
    }
  }
  provisioner "file" {
   source = "./phoebe_vpn_azure.yaml"
   destination = "/home/ubuntu/phoebe_vpn_azure.yaml"  
   connection {
    type = "ssh"
    user = "ubuntu"
    private_key = "${file("vpn.pem")}"
    }
  }
}

resource "local_file" "azure_ansible_vars" {
    content     = "azure_public_ip: ${azurerm_public_ip.publicip.ip_address}\nazure_vpn_subnet: ${azurerm_subnet.subnet.address_prefix}\nazure_private_ip: ${azurerm_network_interface.publicNIC.private_ip_address}"
    filename = "./azure_ansible_vars.yml"
}

resource "null_resource" "azure_exec" {
  triggers = {
    azurerm_virtual_machine_id = "${azurerm_virtual_machine.terraform_vm.id}" # Needed this trigger because azurerm_public_ip is created before the VM is built.  So this would execute before the VM was ready.
  }
  provisioner "remote-exec" {
        inline = ["ansible-playbook phoebe_vpn_azure.yaml"]
        connection {
          type = "ssh"
          user = "ubuntu"
          private_key = "${file("vpn.pem")}"
          host = "${azurerm_public_ip.publicip.ip_address}"
        }
  }
}

resource "null_resource" "aws_restart_ipsec" {
  triggers = {
    azurerm_virtual_machine_id = "${azurerm_virtual_machine.terraform_vm.id}" # Needed this to restart the AWS IPSEC service as it finishes too far ahead of the azure service.
  }
  provisioner "remote-exec" {
        inline = ["sudo service ipsec restart"]
        connection {
          type = "ssh"
          user = "ubuntu"
          private_key = "${file("vpn.pem")}"
          host = "${aws_instance.aws_vpn_server.public_ip}"
        }
  }
}

resource "azurerm_virtual_machine" "test_vm" {
  name                             = "test_vm"
  location                         = "${azurerm_resource_group.rg.location}"
  resource_group_name              = "${azurerm_resource_group.rg.name}"
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


output "azure_vpn_subnet" {
  value = "${azurerm_subnet.subnet.address_prefix}"
}
output "azure_public_ip" {
  value = "${azurerm_public_ip.publicip.ip_address}"
}
output "azure_private_ip" {
  value = "${azurerm_network_interface.publicNIC.private_ip_address}"
}
output "testvm_private_ip" {
  value = "${azurerm_network_interface.testVMNIC.private_ip_address}"
}