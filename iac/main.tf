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

# Política IAM para pull a ECR

resource "aws_iam_role" "ec2_role" {
  name = "lab1-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "lab1-ec2-profile"
  role = aws_iam_role.ec2_role.name
}


# Crear repositorio ECR 

resource "aws_ecr_repository" "python_api" {
  name = "python-api"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# SSH Key
resource "aws_key_pair" "deploy" {
  key_name   = "lab1-deploy-key"
  public_key = var.ssh_public_key
}

# Security Group
resource "aws_security_group" "web_sg" {
  name = "lab1-web-sg"

  ingress {
    description = "FastAPI"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "lab1-web-sg"
    ManagedBy  = "terraform"
    Environment = "lab"
  }
}


resource "aws_security_group_rule" "app_http" {
  type              = "ingress"
  description       = "FastAPI"
  from_port         = 8000
  to_port           = 8000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web_sg.id
}

# Así Terraform sí detecta cambios de IPs
resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  description       = "SSH access"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.allowed_ssh_ips
  security_group_id = aws_security_group.web_sg.id
}

# EC2
resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deploy.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
#!/bin/bash
set -eux

apt-get update -y
apt-get install -y docker.io awscli curl

systemctl enable docker
systemctl start docker

REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr get-login-password --region $REGION \
 | docker login --username AWS --password-stdin \
   $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

docker pull $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/python-api:latest

docker stop python_api || true
docker rm python_api || true
docker logs python_api || true

docker run -d \
  --name python_api \
  -p 8000:8000 \
  --restart always \
  $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/python-api:latest
EOF

  tags = {
    Name        = "lab1-secure-server"
  }
  user_data_replace_on_change = false
}