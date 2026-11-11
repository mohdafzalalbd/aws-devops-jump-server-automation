variable "aws_region" {
  description = "AWS region for infrastructure deployment"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = "default"
}

variable "project_name" {
  description = "Name of the DevOps learning project"
  type        = string
  default     = "my-devops-lab"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "learning"
}

variable "instance_type" {
  description = "EC2 instance type for jump server"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "EC2 root EBS volume size in GB"
  type        = number
  default     = 30
}
variable "vpc_cidr" {
  description = "CIDR block for the DevOps VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Optional Availability Zone. If null, Terraform selects an available zone in the selected region."
  type        = string
  default     = null
  nullable    = true
}

variable "owner_name" {
  description = "Owner or team responsible for the infrastructure"
  type        = string
  default     = "platform-team"
}

variable "ami_architecture" {
  description = "Ubuntu AMI architecture: amd64 or arm64"
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.ami_architecture)
    error_message = "AMI architecture must be either amd64 or arm64."
  }
}
