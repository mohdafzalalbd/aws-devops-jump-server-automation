output "instance_profile_name" {
  description = "IAM instance profile name for the EC2 jump server"
  value       = aws_iam_instance_profile.ec2_ssm.name
}

output "iam_role_name" {
  description = "IAM role name attached to the EC2 jump server"
  value       = aws_iam_role.ec2_ssm.name
}
