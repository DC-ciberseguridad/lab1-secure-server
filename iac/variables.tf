variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ssh_public_key" {
  description = "Public SSH key for EC2 access"
  type        = string
}

variable "allowed_ssh_ip" {
  description = "IP allowed to SSH (x.x.x.x/32)"
  type        = string
}
