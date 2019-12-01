provider "aws" {
  region = "us-east-1"
}

# AWS
resource "aws_key_pair" "awsazvpn_awspublickey" { ## TODO change to variable
  key_name   = "awsazvpn_awspublickey"
  public_key = file("${var.public_key_path}")
}

resource "aws_vpc" "awsazvpn_awsvpc" {
  cidr_block = "172.31.0.0/16"
  tags = {
    Name = "awsazvpn_awsvpc"
  }
}

resource "aws_subnet" "awsazvpn_awssubnet" {
  vpc_id                  = aws_vpc.awsazvpn_awsvpc.id
  cidr_block              = "172.31.64.0/24"
  map_public_ip_on_launch = "false"
}

resource "aws_internet_gateway" "awsazvpn_awsgw" {
  vpc_id = aws_vpc.awsazvpn_awsvpc.id
}

resource "aws_route" "awsazvpn_awsroute_1" {
  route_table_id         = aws_vpc.awsazvpn_awsvpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.awsazvpn_awsgw.id
}

resource "aws_route" "awsazvpn_awsroute_2" {
  route_table_id         = aws_vpc.awsazvpn_awsvpc.main_route_table_id
  destination_cidr_block = "10.0.1.0/24"
  instance_id            = aws_instance.awsazvpn_awsvpnserver.id
}

resource "aws_security_group" "awsazvpn_awssg" {
  vpc_id      = aws_vpc.awsazvpn_awsvpc.id
  name        = "awsazvpn_awssg"
  description = "Allow SSH from the world"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "awsazvpn_awsvpnserver" {
  subnet_id                   = aws_subnet.awsazvpn_awssubnet.id
  ami                         = "ami-0ac019f4fcb7cb7e6"
  associate_public_ip_address = true
  instance_type               = "t2.micro"
  key_name                    = "awsazvpn_awspublickey"
  vpc_security_group_ids      = [aws_security_group.awsazvpn_awssg.id]
  source_dest_check           = "false"
  tags = {
    Name = "awsvpnserver"
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
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
    }
  }
  provisioner "file" {
    source      = "./${local_file.azure_ansible_vars.filename}"
    destination = "/home/ubuntu/${local_file.azure_ansible_vars.filename}"
    connection {
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
    }
  }
  provisioner "file" {
    source      = "./awsazvpn_aws_ansible.yaml"
    destination = "/home/ubuntu/awsazvpn_aws_ansible.yaml"
    connection {
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
    }
  }
  provisioner "file" {
    source      = var.private_key_path
    destination = "/home/ubuntu/.ssh/id_rsa"
    connection {
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
    }
  }
}

resource "local_file" "aws_ansible_vars" {
  content  = "aws_public_ip: ${aws_instance.awsazvpn_awsvpnserver.public_ip}\naws_private_ip: ${aws_instance.awsazvpn_awsvpnserver.private_ip}\naws_vpn_subnet: ${aws_subnet.awsazvpn_awssubnet.cidr_block}"
  filename = "./aws_ansible_vars.yml"
}

resource "null_resource" "aws_exec" {
  provisioner "remote-exec" {
    inline = ["ansible-playbook awsazvpn_aws_ansible.yaml"]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${var.private_key_path}")
      host        = aws_instance.awsazvpn_awsvpnserver.public_ip
    }
  }
}

resource "null_resource" "aws_restart_ipsec" {
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
      host        = aws_instance.awsazvpn_awsvpnserver.public_ip
    }
  }
}

/*
resource "aws_instance" "aws_testvm" {
  subnet_id                   = "${aws_subnet.awsazvpn_awssubnet.id}"
  ami                         = "ami-0ac019f4fcb7cb7e6"
  instance_type               = "t2.micro"
  key_name                    = "awsazvpn_awspublickey"
  vpc_security_group_ids      = ["${aws_security_group.awsazvpn_awssg.id}"]

  tags = {
    Name = "phoebe_vpn_test_vm"
  }

  provisioner "remote-exec" {}
}
*/

output "aws_vpn_subnet" {
  value = aws_subnet.awsazvpn_awssubnet.cidr_block
}

output "aws_private_ip" {
  value = aws_instance.awsazvpn_awsvpnserver.private_ip
}

output "aws_public_ip" {
  value = aws_instance.awsazvpn_awsvpnserver.public_ip
}

/*
output "aws_testvm_private_ip" {
  value = "${aws_instance.aws_testvm.private_ip}"
}
*/
