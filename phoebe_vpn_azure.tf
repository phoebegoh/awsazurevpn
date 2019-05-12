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

resource "azurerm_managed_disk" "mydisk" {
  name                 = "datadisk_existing"
  location             = "${azurerm_resource_group.rg.location}"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "1023"
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
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCEjKH2cGPmPM5WahGAnElHEzE2tLyaQVlZbyuRtJVo4wVCX8vkZSa4FUam5unlznAkcB27H9UBNmwQtEZbN0i5EQTHXA7AxTGcSVVQxuAoj0GInH0nWcQyjhxHrAmLR8J71KG4oUFx1lDwkUYQdoDI8gMH9pTToO6thyY2BYXFWJBB//XMMC9aaTcnSdpRHFURQqSiwfH2KVwyGi9fAVXvgyLb7ZS9ZVCmVzvFMXk+ojFoN2/3mdt+zb5KYPvEj+HnkDfHXMVo7TwVo9/xw1eCSnA0EjSoeq7YqhtjWxzT/4jOer2gGBxjXrTM6hWb95NspVAJh08tXpwnyHVEklWv"
    }
  }
}

resource "null_resource" "local_exec" {
  provisioner "local-exec" {
    command = "sleep 120; export ANSIBLE_HOST_KEY_CHECKING=False; ansible-playbook -u ubuntu --private-key ./phoebevpn.pem -i '168.62.188.182,' phoebe_vpn_azure.yaml -e ansible_python_interpreter=/usr/bin/python3 --extra-vars 'azure_private_ip=10.0.1.4 azure_private_subnet=10.0.1.0/24 aws_public_ip=52.72.32.135 aws_private_subnet=172.31.64.0/24'"
  }
}

output "azure_vpn_subnet" {
  value = "${azurerm_subnet.subnet.address_prefix}"
}

output "public_ip_address" {
  value = "${azurerm_public_ip.publicip.ip_address}"
}

output "azure_private_ip" {
  value = "${azurerm_network_interface.publicNIC.private_ip_address}"
}