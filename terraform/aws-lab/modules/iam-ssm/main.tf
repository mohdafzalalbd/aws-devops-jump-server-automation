# Create an IAM role that EC2 instances are allowed to assume.
resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-${var.environment}-ec2-ssm-role"

  # Defines EC2 as the trusted service that can assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach AWS's managed policy for Systems Manager access.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role = aws_iam_role.ec2_ssm.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create an instance profile so EC2 can receive the IAM role.
resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-${var.environment}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}
