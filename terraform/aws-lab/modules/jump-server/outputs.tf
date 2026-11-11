output "instance_id" {
  description = "EC2 jump server instance ID"
  value       = aws_instance.jump_server.id
}

output "public_ip" {
  description = "Public IP address of the jump server"
  value       = aws_instance.jump_server.public_ip
}

output "private_ip" {
  description = "Private IP address of the jump server"
  value       = aws_instance.jump_server.private_ip
}

output "security_group_id" {
  description = "Jump server security group ID"
  value       = aws_security_group.jump_server.id
}

output "ami_id" {
  description = "Ubuntu AMI ID used by the jump server"
  value       = data.aws_ami.ubuntu.id
}
