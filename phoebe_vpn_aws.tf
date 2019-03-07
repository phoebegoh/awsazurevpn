provider "aws" {
  region = "us-east-1"
}

# AWS
resource "aws_key_pair" "phoebevpn" {
  key_name   = "phoebevpn"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCEjKH2cGPmPM5WahGAnElHEzE2tLyaQVlZbyuRtJVo4wVCX8vkZSa4FUam5unlznAkcB27H9UBNmwQtEZbN0i5EQTHXA7AxTGcSVVQxuAoj0GInH0nWcQyjhxHrAmLR8J71KG4oUFx1lDwkUYQdoDI8gMH9pTToO6thyY2BYXFWJBB//XMMC9aaTcnSdpRHFURQqSiwfH2KVwyGi9fAVXvgyLb7ZS9ZVCmVzvFMXk+ojFoN2/3mdt+zb5KYPvEj+HnkDfHXMVo7TwVo9/xw1eCSnA0EjSoeq7YqhtjWxzT/4jOer2gGBxjXrTM6hWb95NspVAJh08tXpwnyHVEklWv"
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

resource "aws_route" "r" {
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
}

resource "local_file" "ansible_vars" {
    content     = "aws_public_ip: ${aws_instance.aws_vpn_server.public_ip}\nazure_public_ip: ${aws_instance.aws_vpn_server.public_ip}"
    filename = "./ansible_vars.yml"
}
resource "null_resource" "local_exec" {
  provisioner "local-exec" {
        command = "sleep 120; export ANSIBLE_HOST_KEY_CHECKING=False; ansible-playbook -u ubuntu --private-key ./phoebevpn.pem -i '${aws_instance.aws_vpn_server.public_ip},' phoebe_vpn_aws.yaml -e ansible_python_interpreter=/usr/bin/python3"
      }
}

output "aws_private_ip" {
  value = "${aws_instance.aws_vpn_server.private_ip}"
}
output "aws_public_ip" {
  value = "${aws_instance.aws_vpn_server.public_ip}"
}

