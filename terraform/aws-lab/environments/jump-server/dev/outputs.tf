output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Deployment region"
  value       = var.aws_region
}

output "jump_server_name" {
  description = "Planned jump server name"
  value       = local.jump_server_name
}
output "vpc_id" {
  description = "Created VPC ID"
  value       = module.network.vpc_id
}

output "public_subnet_id" {
  description = "Created public subnet ID"
  value       = module.network.public_subnet_id
}

output "internet_gateway_id" {
  description = "Created Internet Gateway ID"
  value       = module.network.internet_gateway_id
}

output "public_route_table_id" {
  description = "Created public route table ID"
  value       = module.network.public_route_table_id
}
output "jump_server_instance_id" {
  description = "EC2 jump server instance ID"
  value       = module.jump_server.instance_id
}

output "jump_server_public_ip" {
  description = "EC2 jump server public IP"
  value       = module.jump_server.public_ip
}

output "jump_server_private_ip" {
  description = "EC2 jump server private IP"
  value       = module.jump_server.private_ip
}

output "jump_server_security_group_id" {
  description = "EC2 jump server security group ID"
  value       = module.jump_server.security_group_id
}

output "jump_server_ami_id" {
  description = "Ubuntu AMI ID used by the jump server"
  value       = module.jump_server.ami_id
}

output "jump_server_iam_role_name" {
  description = "IAM role used by the jump server"
  value       = module.iam_ssm.iam_role_name
}
