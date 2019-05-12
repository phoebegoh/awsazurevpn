provider "aws" {
  region = "us-east-1"
}

# AWS
resource "aws_key_pair" "phoebevpn" {
  key_name   = "phoebevpn"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCzyQehHEk01+XCMwdTIUHZCu7LIW5Ewx8PnBxw6y7/hKw9qKun1wfn5+NJgc5Dzj8JLBY51TGNdWxOr13e3dz2uizVw6j3tFSgHBT2ifGB/+ET7K8MCY/OUmjqbzukoYswGLQP+03VvwIySeFPfOcDy7i2HfOHYBMFPLA/5glHqDca0pY4+8AHNbrtXOPBMuNBkb05jhL9WcMdOeTq1vErhK04E6aj6Ky+o0oxUEHRgQHyCchkUsvbEexzK4hMMicwnURcMtdyiLab+cJ33//V7ByKvogkEq3RJDDLePNiZSSDldSEWsrQJePRGmcGsQ1jsFjI1JKW0A07PxU98tCT"
}

resource "aws_vpc" "main" {
  cidr_block = "172.31.0.0/16"
  tags = {
    Name = "phoebe_vpc"
  }
}

resource "aws_subnet" "backend" {
  vpc_id     = "${aws_vpc.main.id}"
  cidr_block = "172.31.64.0/24"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.main.id}"
}

resource "aws_route" "default" {
  route_table_id         = "${aws_vpc.main.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.gw.id}"
}

resource "aws_security_group" "sshworld" {
  vpc_id      = "${aws_vpc.main.id}"
  name        = "sshworld"
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

resource "aws_instance" "aws_vpn_server" {
  subnet_id                   = "${aws_subnet.backend.id}"
  ami                         = "ami-0ac019f4fcb7cb7e6"
  associate_public_ip_address = 1
  instance_type               = "t2.micro"
  key_name                    = "phoebevpn"
  vpc_security_group_ids      = ["${aws_security_group.sshworld.id}"]

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
   source = "./${local_file.azure_ansible_vars.filename}"
   destination = "/home/ubuntu/${local_file.azure_ansible_vars.filename}"  
   connection {
    type = "ssh"
    user = "ubuntu"
    private_key = "${file("vpn.pem")}"
    }
  }
  provisioner "file" {
   source = "./phoebe_vpn_aws.yaml"
   destination = "/home/ubuntu/phoebe_vpn_aws.yaml"  
   connection {
    type = "ssh"
    user = "ubuntu"
    private_key = "${file("vpn.pem")}"
    }
  }
}

resource "local_file" "aws_ansible_vars" {
    content     = "aws_public_ip: ${aws_instance.aws_vpn_server.public_ip}\naws_private_ip: ${aws_instance.aws_vpn_server.private_ip}\naws_vpn_subnet: ${aws_subnet.backend.cidr_block}"
    filename = "./aws_ansible_vars.yml"
}

resource "null_resource" "aws_exec" {
  provisioner "remote-exec" {
        inline = ["ansible-playbook phoebe_vpn_aws.yaml"]
        connection {
          type = "ssh"
          user = "ubuntu"
          private_key = "${file("vpn.pem")}"
          host = "${aws_instance.aws_vpn_server.public_ip}"
        }
  }
}


output "aws_vpn_subnet" {
  value = "${aws_subnet.backend.cidr_block}"
}
output "aws_private_ip" {
  value = "${aws_instance.aws_vpn_server.private_ip}"
}
output "aws_public_ip" {
  value = "${aws_instance.aws_vpn_server.public_ip}"
}

