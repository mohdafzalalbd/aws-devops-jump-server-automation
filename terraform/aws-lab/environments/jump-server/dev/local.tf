locals {
  jump_server_name = "${var.project_name}-${var.environment}-jump-server"

  selected_availability_zone = var.availability_zone != null ? var.availability_zone : data.aws_availability_zones.available.names[0]

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner_name
    ManagedBy   = "Terraform"
  }
}
