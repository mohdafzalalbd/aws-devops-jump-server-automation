variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "ID of the existing VPC"
  type        = string
}

variable "subnet_id" {
  description = "ID of the public subnet"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile attached to EC2"
  type        = string
}

variable "root_volume_size" {
  description = "EC2 root EBS volume size in GB"
  type        = number
}

variable "common_tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}

variable "ami_architecture" {
  description = "Ubuntu AMI architecture: amd64 or arm64"
  type        = string

  validation {
    condition     = contains(["amd64", "arm64"], var.ami_architecture)
    error_message = "AMI architecture must be either amd64 or arm64."
  }
}
