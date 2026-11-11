# Find the latest official Ubuntu 24.04 LTS AMI for the selected architecture.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${var.ami_architecture}-server-*"]
  }

  filter {
    name   = "architecture"
    values = [var.ami_architecture == "amd64" ? "x86_64" : "arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Discover the architectures supported by the selected EC2 instance type.
data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}

# Create a security group for the jump server.
resource "aws_security_group" "jump_server" {
  name        = "${var.project_name}-${var.environment}-jump-sg"
  description = "Security group for the DevOps jump server"
  vpc_id      = var.vpc_id

  # No ingress block: no inbound connections are allowed.
  # Outbound traffic is allowed for SSM and software downloads.
  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-jump-sg"
  })
}

# Create the Ubuntu EC2 jump server.
resource "aws_instance" "jump_server" {
  lifecycle {
    precondition {
      condition = contains(
        data.aws_ec2_instance_type.selected.supported_architectures,
        var.ami_architecture == "amd64" ? "x86_64" : "arm64"
      )

      error_message = "The selected EC2 instance type does not support the requested AMI architecture. Choose a compatible instance type."
    }
  }

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.jump_server.id]

  # Attach the IAM instance profile for Systems Manager access.
  iam_instance_profile = var.instance_profile_name

  # Assign a public IP for outbound internet connectivity to SSM.
  associate_public_ip_address = true

  # Configure the root EBS volume.
  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # Require IMDSv2 for safer instance metadata access.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-jump-server"
  })
}
