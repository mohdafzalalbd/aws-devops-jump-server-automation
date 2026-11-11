# Read current AWS account identity

data "aws_caller_identity" "current" {
}

# Discover Availability Zones available in the selected AWS region.
data "aws_availability_zones" "available" {
  state = "available"
}


# Call reusable Network Module

module "network" {
  source = "../../../modules/network"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  availability_zone  = local.selected_availability_zone
  common_tags        = local.common_tags
}
# Create the IAM role and instance profile for SSM access.
module "iam_ssm" {
  source = "../../../modules/iam-ssm"

  project_name = var.project_name
  environment  = var.environment
}

# Create the EC2 jump server and its security group.
module "jump_server" {
  source = "../../../modules/jump-server"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  subnet_id             = module.network.public_subnet_id
  instance_type         = var.instance_type
  instance_profile_name = module.iam_ssm.instance_profile_name
  root_volume_size      = var.root_volume_size
  ami_architecture      = var.ami_architecture
  common_tags           = local.common_tags
}
