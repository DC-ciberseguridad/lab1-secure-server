terraform {
  backend "s3" {
    bucket         = "lab1-terraform-state-dani"
    key            = "lab1/infra.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Ubuntu 22.04 AMI (oficial Canonical)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# SSH Key
resource "aws_key_pair" "deploy" {
  key_name   = "lab1-deploy-key"
  public_key = var.ssh_public_key
}

# Security Group (mínimo)
resource "aws_security_group" "web_sg" {
  name = "lab1-web-sg"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_ip]
  }

  ingress {
    description = "HTTP"
    from_port   = 8000
    to_port     = 8000
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

# EC2
resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.deploy.key_name
  vpc_security_group_ids      = [aws_security_group.web_sg.id]

  user_data = <<-EOF
#!/bin/bash
set -eux

# =========================
# Actualizar sistema
# =========================
apt-get update -y
apt-get upgrade -y

# =========================
# Crear usuarios
# =========================
useradd -m -s /bin/bash admin
useradd -m -s /bin/bash deploy

# Copiar llaves SSH del usuario ubuntu
mkdir -p /home/admin/.ssh /home/deploy/.ssh
cp /home/ubuntu/.ssh/authorized_keys /home/admin/.ssh/
cp /home/ubuntu/.ssh/authorized_keys /home/deploy/.ssh/

chown -R admin:admin /home/admin/.ssh
chown -R deploy:deploy /home/deploy/.ssh

chmod 700 /home/*/.ssh
chmod 600 /home/*/.ssh/authorized_keys

# =========================
# Sudo limitado
# =========================
echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin
chmod 440 /etc/sudoers.d/*

# =========================
# Instalar Docker
# =========================
apt-get install -y ca-certificates curl gnupg lsb-release ufw
curl -fsSL https://get.docker.com | sh

usermod -aG docker deploy

systemctl enable docker
systemctl start docker

# =========================
# Hardening SSH
# =========================
echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
echo "X11Forwarding no" >> /etc/ssh/sshd_config

systemctl reload sshd

# =========================
# Firewall (UFW)
# =========================
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp
ufw allow 8000/tcp

ufw --force enable

EOF


  tags = {
    Name = "lab1-secure-server"
  }
}
