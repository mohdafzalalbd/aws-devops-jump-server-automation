# AWS DevOps Jump Server Automation

A reusable, beginner-friendly Infrastructure as Code (IaC) project that
provisions **one AWS DevOps Jump Server** with Terraform and configures
it with Ansible through AWS Systems Manager (SSM).

The project is designed so a new user can start from a fresh Ubuntu/WSL
machine, prepare local tools, configure their own AWS account, deploy
the infrastructure, configure the EC2 instance, verify the result, and
safely clean up when finished.

> **Repository scope:** This repository supports one Jump Server per
> deployment. Multiple Jump Servers, multiple independently managed
> environments, and multi-server orchestration are intentionally
> reserved for a separate future project.

------------------------------------------------------------------------

## 1. What This Project Does

The project automates two distinct stages:

1.  **Terraform --- infrastructure provisioning:** creates the AWS
    network, IAM permissions for Systems Manager, security group, and
    one Ubuntu EC2 Jump Server.
2.  **Ansible --- server configuration:** connects to the instance
    through AWS Systems Manager and installs the DevOps tools listed
    below.

### AWS infrastructure created

-   One VPC (default CIDR: `10.0.0.0/16`)
-   One public subnet (default CIDR: `10.0.1.0/24`)
-   One Internet Gateway
-   One public route table and route association
-   One IAM role and EC2 instance profile for Systems Manager
-   One security group with **no inbound rules** and outbound IPv4
    access
-   One Ubuntu 24.04 LTS EC2 instance
-   One encrypted gp3 root EBS volume
-   IMDSv2 required on the EC2 instance
-   A public IPv4 address for outbound internet connectivity

The EC2 AMI is selected from Canonical's official Ubuntu images.
Terraform checks that the selected EC2 instance type supports the
requested CPU architecture before creating the instance.

### DevOps tools installed by Ansible

  Tool            Purpose
  --------------- -------------------------------
  AWS CLI v2      AWS resource management
  Terraform       Infrastructure as Code
  Docker Engine   Container management
  kubectl         Kubernetes administration
  Helm            Kubernetes package management
  eksctl          Amazon EKS cluster management

**Important scope clarification:** this project installs the listed
tools on the Jump Server. It does not deploy an EKS cluster, Kubernetes
applications, Jenkins, ELK Stack, or a production application.

------------------------------------------------------------------------

## 2. Architecture

``` text
LOCAL WORKSTATION (Ubuntu / WSL)
|
|-- AWS CLI profile and credentials
|-- Terraform CLI
|-- Session Manager plugin
|-- Project .env configuration
|-- Ansible virtual environment
|
|       Terraform
|           |
|           v
|       AWS ACCOUNT
|           |
|           +-- VPC
|           |    |
|           |    +-- Public subnet
|           |         |
|           |         +-- Internet Gateway
|           |         +-- Public route table
|           |
|           +-- IAM role / instance profile
|           |       |
|           |       +-- AmazonSSMManagedInstanceCore
|           |
|           +-- Security group (no inbound rules)
|           |
|           +-- Ubuntu 24.04 EC2 Jump Server
|                   |
|                   +-- Encrypted gp3 root volume
|                   +-- IMDSv2 required
|                   +-- Public IPv4 for outbound access
|
|       ANSIBLE CONTROLLER
|           |
|           +-- AWS EC2 dynamic inventory (tag filters)
|           +-- Local AWS identity / selected AWS profile
|           +-- AWS Systems Manager session
|           +-- Private S3 transfer bucket
|                   |
|                   +-- Upload/download Ansible modules and files
|
|       ANSIBLE CONFIGURATION
|           |
|           +-- common
|           +-- aws_cli
|           +-- terraform
|           +-- docker
|           +-- kubectl
|           +-- helm
|           +-- eksctl
```

### How remote access works

-   Ansible discovers the running EC2 instance using the
    `amazon.aws.aws_ec2` dynamic inventory plugin and its Name, Project
    and Environment tags.
-   Ansible connects with `amazon.aws.aws_ssm`, not SSH.
-   The local workstation's AWS identity is used to discover the
    instance, start SSM sessions and access the S3 transfer bucket.
-   The EC2 instance has a separate IAM instance profile with
    `AmazonSSMManagedInstanceCore`.
-   The S3 bucket is used by the Ansible SSM connection plugin to
    transfer modules and files. It is **not** the Terraform state
    backend.

The security group has no inbound SSH rule. The instance is in a public
subnet and receives a public IP for outbound connectivity to AWS Systems
Manager and software repositories.

------------------------------------------------------------------------

## 3. Repository Structure

``` text
aws-devops-jump-server-automation/
|
+-- .env.example
+-- .gitignore
+-- README.md
|
+-- ansible/
|   +-- ansible.cfg
|   +-- requirements.txt
|   +-- requirements.yml
|   +-- inventory/
|   |   +-- jump-server.aws_ec2.yml
|   |   +-- jump-server.ini
|   |   +-- group_vars/
|   |       +-- jump_servers.yml
|   +-- playbooks/
|   |   +-- site.yml
|   |   +-- connectivity.yml
|   |   +-- common.yml
|   |   +-- aws-cli.yml
|   |   +-- terraform.yml
|   |   +-- docker.yml
|   |   +-- kubectl.yml
|   |   +-- helm.yml
|   |   +-- eksctl.yml
|   +-- roles/
|       +-- common/
|       +-- aws_cli/
|       +-- terraform/
|       +-- docker/
|       +-- kubectl/
|       +-- helm/
|       +-- eksctl/
|
+-- scripts/
|   +-- setup.sh
|   +-- rebuild-jump-server.sh
|   +-- lib/
|       +-- config.sh
|
+-- terraform/
    +-- aws-lab/
        +-- environments/
        |   +-- jump-server/
        |       +-- dev/
        |           +-- main.tf
        |           +-- variables.tf
        |           +-- terraform.tfvars.example
        |           +-- outputs.tf
        |           +-- providers.tf
        |           +-- versions.tf
        |           +-- locals.tf
        |
        +-- modules/
            +-- network/
            +-- iam-ssm/
            +-- jump-server/
```

The Terraform environment directory is the root module for this
deployment. The three Terraform modules keep networking, IAM/SSM, and
EC2 Jump Server resources reusable and separated.

------------------------------------------------------------------------

## 4. Fresh-Machine Prerequisites

These instructions target **Ubuntu 22.04/24.04 or Ubuntu on WSL2**. Run
all local setup commands on your workstation, not on the EC2 instance.

### 4.1 Update Ubuntu and install base packages

``` bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl unzip jq python3 python3-venv python3-pip
```

Verify:

``` bash
git --version
python3 --version
```

Python 3.11 or newer is required by the pinned Ansible version.

### 4.2 Install AWS CLI v2

Install AWS CLI version 2 using the official AWS instructions for your
Linux architecture:

https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

For Ubuntu on common x86_64 systems, the official AWS installer can be
used as follows:

``` bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
```

For ARM64/aarch64, use the ARM64 package URL from the official AWS
installation page instead.

Verify:

``` bash
aws --version
```

The output must show AWS CLI version 2.

### 4.3 Install Terraform

Install Terraform using HashiCorp's official Ubuntu/Debian instructions:

https://developer.hashicorp.com/terraform/install

Terraform 1.5.0 or newer is required.

Verify:

``` bash
terraform version
```

### 4.4 Install AWS Session Manager plugin

The Session Manager plugin is required on the local workstation for SSM
sessions and Ansible's SSM connection.

Follow the official Linux installation instructions for your
architecture:

https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-linux.html

Verify:

``` bash
session-manager-plugin
```

The command should print plugin usage/version information.

### 4.5 Confirm all local prerequisites

``` bash
git --version
python3 --version
aws --version
terraform version
session-manager-plugin
```

**What the project setup script installs:** Ansible Python dependencies
and the required Ansible collection.

**What it does not install:** system-level Git, Python, AWS CLI,
Terraform CLI or the Session Manager plugin. Install those before
running the project setup.

------------------------------------------------------------------------

## 5. Configure AWS Credentials

You need an active AWS account and an IAM identity with permissions to
create and manage the resources in this project. The identity must also
be able to use Systems Manager and access the S3 transfer bucket.

Configure a local AWS CLI profile. If you use the `default` profile:

``` bash
aws configure --profile default
```

Provide the access method/credentials required by your organization, the
default region and output format. Prefer IAM Identity Center or
short-lived credentials where available. Do not hardcode credentials in
project files.

The example region used by this repository is `ap-south-1` (Mumbai). You
may use another AWS region where the required services and selected EC2
instance type are available.

Verify the identity:

``` bash
aws sts get-caller-identity --profile default
```

Make sure this is the AWS account in which you intend to create
resources.

> Never paste access keys, secret keys, session tokens, or verbose SSM
> session output into chat or commit them to Git.

------------------------------------------------------------------------

## 6. Clone the Repository

``` bash
git clone https://github.com/mohdafzalalbd/aws-devops-jump-server-automation.git
cd aws-devops-jump-server-automation
```

Confirm the working directory:

``` bash
pwd
ls -la
```

All remaining project commands should be run from this repository clone
unless a step explicitly tells you to change directories.

------------------------------------------------------------------------

## 7. Run First-Time Project Setup

Make the setup script executable and run it:

``` bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

The script performs the following actions:

1.  Checks for Python 3.11 or newer.
2.  Checks that the Ansible requirements files and configuration
    templates exist.
3.  Creates `.env` from `.env.example` if `.env` does not already exist.
4.  Creates `terraform.tfvars` from `terraform.tfvars.example` if it
    does not already exist.
5.  Preserves existing local configuration files on subsequent runs.
6.  Creates an isolated virtual environment at `ansible/.venv`.
7.  Installs the pinned Python dependencies.
8.  Installs the required Ansible collection.
9.  Runs Ansible version and Python dependency checks.

### Pinned Ansible dependencies

`ansible/requirements.txt`:

-   `ansible-core==2.18.20`
-   `boto3==1.43.126`

`ansible/requirements.yml`:

-   `amazon.aws==11.5.1`

The setup script does **not** create AWS infrastructure.

------------------------------------------------------------------------

## 8. Create the Private S3 Transfer Bucket

The Ansible `amazon.aws.aws_ssm` connection plugin uses S3 to transfer
Ansible modules and files between the local workstation and the EC2
instance.

Each user must create and use their **own private S3 bucket** in the
same AWS region as the Jump Server.

### Example: create a bucket in ap-south-1

Choose a globally unique bucket name and replace the placeholder below:

``` bash
export AWS_PROFILE=default
export AWS_REGION=ap-south-1
export S3_BUCKET_NAME=YOUR_GLOBALLY_UNIQUE_BUCKET_NAME

aws s3api create-bucket \
  --bucket "$S3_BUCKET_NAME" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" \
  --profile "$AWS_PROFILE"
```

Keep Block Public Access enabled:

``` bash
aws s3api put-public-access-block \
  --bucket "$S3_BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"
```

Check the bucket location:

``` bash
aws s3api get-bucket-location \
  --bucket "$S3_BUCKET_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"
```

For regions other than `ap-south-1`, use your selected region
consistently. The `us-east-1` bucket creation command does not use
`LocationConstraint`; follow the AWS CLI documentation for that region.

### S3 permissions required by the local Ansible identity

The local identity generally needs these actions scoped to the transfer
bucket:

-   `s3:GetBucketLocation`
-   `s3:ListBucket`
-   `s3:GetObject`
-   `s3:PutObject`
-   `s3:DeleteObject`

Use least privilege and your organization's IAM standards. The bucket
must remain private; do not add public bucket policies.

### Understand the two AWS identities

**Local workstation / Ansible controller identity**

-   Uses the configured AWS CLI profile.
-   Discovers the EC2 instance through the AWS EC2 dynamic inventory
    plugin.
-   Starts SSM sessions.
-   Accesses the S3 transfer bucket.

**EC2 instance IAM role**

-   Is attached to the Jump Server through its instance profile.
-   Includes `AmazonSSMManagedInstanceCore`.
-   Allows the instance to register with and be managed by AWS Systems
    Manager.

These are separate permissions. The EC2 instance role does not
automatically give the local workstation permission to access the S3
transfer bucket.

The deployment script checks that the bucket exists, belongs to the
authenticated AWS account and is in the configured AWS region before
continuing.

------------------------------------------------------------------------

## 9. Configure the Project

The setup script creates two local configuration files:

-   `.env` in the repository root
-   `terraform.tfvars` in
    `terraform/aws-lab/environments/jump-server/dev/`

Both are user-specific configuration. They should not be committed.

### 9.1 Configure `.env`

Open the file:

``` bash
nano .env
```

Example:

``` dotenv
AWS_PROFILE=default
AWS_REGION=ap-south-1
AWS_DEFAULT_REGION=ap-south-1

PROJECT_NAME=my-devops-lab
ENVIRONMENT=learning
JUMP_SERVER_NAME=my-devops-lab-learning-jump-server

ANSIBLE_AWS_SSM_BUCKET_NAME=YOUR_GLOBALLY_UNIQUE_BUCKET_NAME
```

Replace the example values with your own:

  Variable                        Meaning
  ------------------------------- ------------------------------------------
  `AWS_PROFILE`                   AWS CLI profile used on your workstation
  `AWS_REGION`                    AWS deployment region
  `AWS_DEFAULT_REGION`            Must match `AWS_REGION`
  `PROJECT_NAME`                  Project identifier used in resource tags
  `ENVIRONMENT`                   Environment label for this deployment
  `JUMP_SERVER_NAME`              Expected EC2 Name tag
  `ANSIBLE_AWS_SSM_BUCKET_NAME`   Your private S3 transfer bucket

Save and exit.

The configuration loader accepts only the documented configuration keys,
validates the region/name/bucket formats, checks that both region
variables match, and requires a real S3 bucket name.

### 9.2 Configure Terraform variables

Open:

``` bash
nano terraform/aws-lab/environments/jump-server/dev/terraform.tfvars
```

Example:

``` hcl
aws_region  = "ap-south-1"
aws_profile = "default"

project_name = "my-devops-lab"
environment  = "learning"

ami_architecture = "amd64"
instance_type    = "t3.small"
root_volume_size = 30

vpc_cidr           = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"

availability_zone = null

owner_name = "my-platform-team"
```

Keep the following values consistent with `.env`:

  Terraform variable   `.env` variable
  -------------------- -----------------
  `aws_region`         `AWS_REGION`
  `aws_profile`        `AWS_PROFILE`
  `project_name`       `PROJECT_NAME`
  `environment`        `ENVIRONMENT`

The EC2 Name tag is generated from:

``` text
<project_name>-<environment>-jump-server
```

Therefore, `JUMP_SERVER_NAME` in `.env` must match the generated
Terraform EC2 Name tag. The dynamic inventory and deployment script use
the project, environment and Name tags to find the expected instance. If
the values do not match, discovery can fail.

### 9.3 Choose instance type and CPU architecture

The supported architecture values are:

-   `amd64` --- x86_64
-   `arm64` --- ARM64

AMD64 example:

``` hcl
ami_architecture = "amd64"
instance_type    = "t3.small"
```

ARM64 example:

``` hcl
ami_architecture = "arm64"
instance_type    = "t4g.small"
```

You can select another compatible EC2 size, such as `t3.medium`, if it
is available in your region and suitable for your workload.

Terraform looks up the official Ubuntu 24.04 AMI for the selected
architecture and checks whether the chosen EC2 instance type supports
that architecture. A mismatch is rejected by a Terraform precondition.

Changing the instance type may require an EC2 stop/start. Changing CPU
architecture generally requires EC2 replacement because the AMI
architecture changes. Always inspect the Terraform plan and consider
data backup and downtime before approving changes.

### 9.4 Availability Zone and storage

-   `root_volume_size` controls the encrypted gp3 root volume size in
    GB.
-   `availability_zone = null` allows Terraform to select an available
    Availability Zone in the configured region.
-   You may set an explicit Availability Zone if required, provided the
    selected subnet and instance type are supported there.

------------------------------------------------------------------------

## 10. Pre-Deployment Checks

Before running the deployment, verify your AWS identity:

``` bash
aws sts get-caller-identity --profile default
```

Verify local tools:

``` bash
aws --version
terraform version
ansible --version
session-manager-plugin
```

If `ansible` is not found in the current shell, activate the virtual
environment:

``` bash
source ansible/.venv/bin/activate
```

Check the S3 bucket:

``` bash
aws s3api head-bucket \
  --bucket YOUR_GLOBALLY_UNIQUE_BUCKET_NAME \
  --profile default \
  --region ap-south-1
```

Review your configuration locally:

``` bash
cat .env
cat terraform/aws-lab/environments/jump-server/dev/terraform.tfvars
```

Do not share the output of `.env`; it contains account-specific
configuration.

Optional Terraform formatting and validation:

``` bash
cd terraform/aws-lab/environments/jump-server/dev
terraform fmt -recursive
terraform init
terraform validate
cd -
```

The main deployment script also initializes Terraform and creates the
actual deployment plan.

------------------------------------------------------------------------

## 11. Deploy the Jump Server

Run this from the repository root:

``` bash
./scripts/rebuild-jump-server.sh
```

### What the deployment script does

1.  Loads and validates `.env`.
2.  Sets the AWS CLI profile consistently.
3.  Checks Terraform, AWS CLI and Session Manager plugin availability.
4.  Activates and verifies the Ansible virtual environment.
5.  Verifies the AWS caller identity.
6.  Checks that the S3 transfer bucket belongs to the authenticated
    account and matches the deployment region.
7.  Initializes Terraform in the single-server environment directory.
8.  Generates a saved Terraform plan using the selected AWS region,
    profile, project and environment.
9.  Displays the plan for review.
10. Requests explicit deployment approval.
11. Applies the reviewed plan only after approval.
12. Waits for exactly one matching EC2 instance to become `running`.
13. Waits for AWS Systems Manager to report the instance as `Online`.
14. Validates the Ansible dynamic inventory and `jump_servers` group.
15. Runs the Ansible ping module through SSM.
16. Executes `playbooks/site.yml`.
17. Prints the final deployment status.

### Explicit deployment approval

The script displays the Terraform plan and asks:

``` text
Type DEPLOY to approve AWS infrastructure deployment:
```

Review the complete plan. If it contains only the resources and changes
you expect, enter:

``` text
DEPLOY
```

Any other response cancels the deployment without running
`terraform apply`.

**Never approve a plan you have not reviewed.** Terraform may create
billable resources. If a later Ansible step fails, the script does not
automatically destroy the infrastructure. Diagnose the failure and
inspect the current Terraform state before retrying.

------------------------------------------------------------------------

## 12. Verify the Deployment

### 12.1 Verify Terraform outputs

From the Terraform environment directory:

``` bash
cd terraform/aws-lab/environments/jump-server/dev
terraform output
```

Useful outputs include:

``` bash
terraform output -raw jump_server_name
terraform output -raw jump_server_instance_id
terraform output -raw jump_server_public_ip
terraform output -raw jump_server_private_ip
terraform output -raw vpc_id
terraform output -raw public_subnet_id
terraform output -raw jump_server_security_group_id
```

Return to the repository root when finished:

``` bash
cd -
```

### 12.2 Verify EC2 state

``` bash
aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=my-devops-lab-learning-jump-server" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress]" \
  --output table \
  --region ap-south-1 \
  --profile default
```

Replace the example Name tag, region and profile with your configured
values.

Confirm in the AWS Console under **EC2 → Instances** that the instance
is running and both EC2 status checks have passed.

### 12.3 Verify SSM registration

``` bash
aws ssm describe-instance-information \
  --query "InstanceInformationList[].[InstanceId,PingStatus,PlatformName,PlatformVersion]" \
  --output table \
  --region ap-south-1 \
  --profile default
```

The Jump Server should show `PingStatus` as `Online`.

### 12.4 Open an interactive SSM session (optional)

Get the instance ID from Terraform:

``` bash
cd terraform/aws-lab/environments/jump-server/dev
INSTANCE_ID="$(terraform output -raw jump_server_instance_id)"
```

Start a session:

``` bash
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --region ap-south-1 \
  --profile default
```

Inside the session, verify the operating system:

``` bash
hostname
cat /etc/os-release
uname -m
```

Exit the SSM session:

``` bash
exit
```

Return to the repository root:

``` bash
cd -
```

### 12.5 Verify Ansible dynamic inventory

The Ansible configuration file sets the dynamic inventory as its default
inventory. Load `.env` before running Ansible so the inventory and SSM
connection receive the correct settings.

From the repository root:

``` bash
source scripts/lib/config.sh
load_project_config
export AWS_DEFAULT_PROFILE="${AWS_PROFILE}"

cd ansible
source .venv/bin/activate
```

Display the inventory graph:

``` bash
ansible-inventory --graph
```

The `jump_servers` group should contain the Jump Server.

### 12.6 Verify Ansible connectivity

``` bash
ansible jump_servers -m ansible.builtin.ping
```

Expected result includes:

``` text
"ping": "pong"
```

This confirms that Ansible can reach the EC2 instance through SSM.

------------------------------------------------------------------------

## 13. Run Ansible Manually

The deployment script already runs the complete Ansible playbook. Use
this section when you want to rerun configuration or execute an
individual playbook.

From the repository root:

``` bash
source scripts/lib/config.sh
load_project_config
export AWS_DEFAULT_PROFILE="${AWS_PROFILE}"

cd ansible
source .venv/bin/activate
```

### Run the complete configuration

``` bash
ansible-playbook playbooks/site.yml
```

The `ansible.cfg` file selects `inventory/jump-server.aws_ec2.yml` as
the default inventory.

The main playbook runs these roles in order:

``` text
common
  |
  v
aws_cli
  |
  v
terraform
  |
  v
docker
  |
  v
kubectl
  |
  v
helm
  |
  v
eksctl
```

### Run one playbook

For example, run Docker configuration only:

``` bash
ansible-playbook playbooks/docker.yml
```

Other individual playbooks:

``` bash
ansible-playbook playbooks/common.yml
ansible-playbook playbooks/aws-cli.yml
ansible-playbook playbooks/terraform.yml
ansible-playbook playbooks/kubectl.yml
ansible-playbook playbooks/helm.yml
ansible-playbook playbooks/eksctl.yml
```

### Validate playbook syntax

``` bash
ansible-playbook playbooks/site.yml --syntax-check
```

### List inventory

``` bash
ansible-inventory --graph
```

### Use an explicit inventory path

From the `ansible/` directory:

``` bash
ansible-inventory -i inventory/jump-server.aws_ec2.yml --graph
ansible -i inventory/jump-server.aws_ec2.yml jump_servers -m ansible.builtin.ping
ansible-playbook -i inventory/jump-server.aws_ec2.yml playbooks/site.yml
```

### Static inventory alternative

The repository also contains `inventory/jump-server.ini` as a template
for a manually specified instance. If you choose to use it, create a
local copy:

``` bash
cp inventory/jump-server.ini inventory/jump-server.local.ini
nano inventory/jump-server.local.ini
```

Replace its placeholders with your own instance ID, region and S3
transfer bucket settings. Validate and use it:

``` bash
ansible-inventory -i inventory/jump-server.local.ini --graph
ansible-playbook -i inventory/jump-server.local.ini playbooks/site.yml
```

The local inventory file is excluded by `.gitignore`. Never commit
account-specific inventory details.

------------------------------------------------------------------------

## 14. Terraform State and Local Configuration

This project uses Terraform's default **local backend**.

-   Terraform state is maintained in the local Terraform environment
    directory.
-   Each user's clone has its own independent local state.
-   A remote Terraform state backend is not configured by default.
-   The Ansible S3 transfer bucket is not used for Terraform state.
-   Do not commit Terraform state files or saved plan files.
-   Keep `.terraform.lock.hcl` under version control.
-   Do not commit `.terraform/`, `.env`, local `terraform.tfvars`, or
    local inventory files.

Use the same repository clone and Terraform working directory that
created the resources when you plan changes or destroy them. Losing the
state file can make resource management and cleanup difficult.

------------------------------------------------------------------------

## 15. Security Considerations

The current implementation includes:

-   No inbound EC2 security-group rules.
-   SSM-based remote management rather than inbound SSH.
-   An EC2 IAM instance profile with `AmazonSSMManagedInstanceCore`.
-   Encrypted gp3 root EBS volume.
-   IMDSv2 required.
-   Ubuntu AMI selected from Canonical's official owner ID.
-   Terraform validation that the selected instance type supports the
    selected architecture.
-   No hardcoded personal AWS access keys in Terraform or Ansible
    configuration.

### Important network note

The security group permits unrestricted outbound IPv4 traffic
(`0.0.0.0/0`) so the instance can reach SSM endpoints and download
packages/tools. This is functional for the learning project, but it is
broader than a restricted-egress production security policy.

### Protect local files

Never commit or publish:

-   `.env`
-   AWS credentials or session tokens
-   `terraform.tfvars`
-   Terraform state files
-   Terraform plan files
-   Private keys
-   `inventory/jump-server.local.ini`
-   Any account-specific or sensitive configuration

`.gitignore` helps prevent accidental commits, but it does not remove
files that were already committed. Review Git status and repository
contents before pushing changes.

------------------------------------------------------------------------

## 16. Cost Awareness

AWS resources created by this project can incur charges. Potential
cost-generating resources include:

-   EC2 instance runtime
-   EBS storage
-   Public IPv4 address
-   Data transfer
-   S3 storage and requests

Actual charges depend on region, instance type, usage, and current AWS
pricing. This project does not guarantee Free Tier eligibility.

Before deployment:

1.  Review the Terraform plan.
2.  Check current AWS pricing for the selected region and instance type.
3.  Monitor AWS billing and usage.
4.  Remove resources when they are no longer required.

The deployment script does not stop or destroy the EC2 instance after
Ansible finishes. The instance remains running until you intentionally
change or destroy it.

------------------------------------------------------------------------

## 17. Cleanup --- Destroy Your Deployment

When you no longer need the Jump Server, use the **same repository clone
and Terraform working directory** that created it. The original local
Terraform state must still be available.

From the repository root:

``` bash
cd terraform/aws-lab/environments/jump-server/dev
terraform init
terraform plan -destroy
```

Review the entire destroy plan. Confirm that it contains only resources
belonging to this deployment.

Only when you are certain, execute:

``` bash
terraform destroy
```

Terraform asks for confirmation before deleting resources.

**Warning:** `terraform destroy` is destructive. Do not run it from an
unrelated clone or against a state file you do not understand. Do not
delete the state file before managing the resources it tracks.

The S3 transfer bucket was created manually and is not managed by these
Terraform modules. It will not be deleted by `terraform destroy`. Review
its contents and dependencies before deciding whether to remove it
separately.

------------------------------------------------------------------------

## 18. Troubleshooting

  -------------------------------------------------------------------------------------------
  Problem                             What to check
  ----------------------------------- -------------------------------------------------------
  AWS credentials error               Run
                                      `aws sts get-caller-identity --profile YOUR_PROFILE`;
                                      verify the selected profile and credential source.

  Wrong AWS account                   Confirm the caller identity before deployment. Do not
                                      approve the plan until the target account is correct.

  Region mismatch                     Make `.env`, `terraform.tfvars`, the S3 bucket and AWS
                                      CLI commands use the same region.

  Setup cannot create virtual         Install `python3-venv`, then rerun
  environment                         `./scripts/setup.sh`.

  Terraform initialization error      Check network connectivity, AWS permissions, provider
                                      configuration and `.terraform.lock.hcl`.

  Terraform validation error          Run `terraform validate` from the environment directory
                                      and inspect the first reported error.

  No inventory hosts found            Confirm EC2 is running and Name, Project and
                                      Environment tags match `.env` and Terraform variables.

  SSM connection failure              Check SSM registration, instance profile, outbound
                                      connectivity, local Session Manager plugin and AWS
                                      identity.

  SSM instance not Online             Verify EC2 instance role, SSM agent status, network
                                      access and AWS Systems Manager registration.

  S3 bucket error                     Confirm bucket name, owner, region, privacy settings
                                      and local IAM permissions.

  Ansible dependency error            Activate `ansible/.venv`; if needed, rerun
                                      `./scripts/setup.sh` from the repository root.

  Ansible command not found           Activate the virtual environment using
                                      `source ansible/.venv/bin/activate` from the repository
                                      root.

  Ansible cannot discover EC2         Load `.env` using the configuration loader and verify
                                      AWS profile, region and tag filters.

  Architecture mismatch               Select an EC2 instance type compatible with `amd64` or
                                      `arm64`.

  Deployment script stops after       Check whether infrastructure was applied; inspect
  Terraform                           Terraform state and the first failing Ansible/SSM step
                                      before retrying.

  More than one matching instance     The deployment script expects exactly one matching EC2
                                      instance. Check tags and existing resources before
                                      proceeding.
  -------------------------------------------------------------------------------------------

Useful diagnostics from the repository root:

``` bash
source scripts/lib/config.sh
load_project_config
export AWS_DEFAULT_PROFILE="${AWS_PROFILE}"

aws sts get-caller-identity
aws ssm describe-instance-information --region "${AWS_REGION}"
```

Then inspect dynamic inventory:

``` bash
cd ansible
source .venv/bin/activate
ansible-inventory --graph
```

Do not blindly rerun `terraform apply` or `terraform destroy` after an
error. First understand the current state and the proposed plan.

------------------------------------------------------------------------

## 19. Current Scope and Future Projects

### Included in this repository

-   [x] Single Jump Server deployment
-   [x] Terraform network module
-   [x] Terraform IAM/SSM module
-   [x] Terraform Jump Server module
-   [x] Ubuntu 24.04 LTS AMI selection
-   [x] AMD64 and ARM64 configuration
-   [x] EC2 instance-type architecture compatibility check
-   [x] Encrypted gp3 root volume
-   [x] IMDSv2 enforcement
-   [x] Security group with no inbound rules
-   [x] Ansible dynamic EC2 inventory
-   [x] SSM-based remote connectivity
-   [x] Private S3 transfer bucket integration
-   [x] AWS CLI installation
-   [x] Terraform installation
-   [x] Docker installation
-   [x] kubectl installation
-   [x] Helm installation
-   [x] eksctl installation
-   [x] Deployment approval and readiness checks

### Future work --- separate project/repository

The following are deliberately outside this beginner single-server
repository:

-   Multiple Jump Servers in one environment
-   Separate Dev, QA, Staging and Production infrastructure roots
-   Terraform `for_each` for multiple instances
-   Separate Terraform state per environment
-   Environment-aware Ansible inventory and targeting
-   Multi-server deployment orchestration
-   Jenkins CI/CD integration
-   ELK Stack deployment
-   Kubernetes application deployment
-   Monitoring and observability stack deployment

The intention is to keep this repository easy for a beginner to clone
and deploy. Advanced multi-environment and multi-server Terraform design
will be developed and published separately.

------------------------------------------------------------------------

## 20. End-to-End Command Checklist

Use this condensed sequence after reading the detailed instructions
above. Replace example values with your own.

### A. Local machine

``` bash
sudo apt update
sudo apt install -y git curl unzip jq python3 python3-venv python3-pip

git --version
python3 --version
aws --version
terraform version
session-manager-plugin
```

### B. AWS profile

``` bash
aws configure --profile default
aws sts get-caller-identity --profile default
```

### C. Clone and setup

``` bash
git clone https://github.com/mohdafzalalbd/aws-devops-jump-server-automation.git
cd aws-devops-jump-server-automation

chmod +x scripts/setup.sh
./scripts/setup.sh
```

### D. Configure local files

``` bash
nano .env
nano terraform/aws-lab/environments/jump-server/dev/terraform.tfvars
```

Create your private S3 transfer bucket as described in Section 8, and
put its name in `.env`.

### E. Deploy

``` bash
./scripts/rebuild-jump-server.sh
```

Review the plan and type `DEPLOY` only when you approve it.

### F. Verify

``` bash
cd terraform/aws-lab/environments/jump-server/dev
terraform output
cd -

source scripts/lib/config.sh
load_project_config
export AWS_DEFAULT_PROFILE="${AWS_PROFILE}"

cd ansible
source .venv/bin/activate

ansible-inventory --graph
ansible jump_servers -m ansible.builtin.ping
ansible-playbook playbooks/site.yml
```

The deployment script already runs the full playbook; the last command
is for a manual rerun if needed.

### G. Cleanup when intentionally finished

``` bash
cd terraform/aws-lab/environments/jump-server/dev
terraform plan -destroy
terraform destroy
```

Review the destroy plan before confirming.

------------------------------------------------------------------------

## 21. Important Disclaimer

This repository is a learning and automation blueprint. Each user is
responsible for:

-   Using their own AWS account, credentials and IAM permissions.
-   Creating and maintaining their own private S3 transfer bucket.
-   Protecting local configuration and Terraform state.
-   Reviewing Terraform plans before approving infrastructure changes.
-   Monitoring AWS usage and charges.
-   Managing and cleaning up resources they deploy.

Never publish AWS access keys, secret keys, session tokens, Terraform
state files, private keys, `.env` files or personal configuration.

**The goal of this repository is to demonstrate a complete,
beginner-friendly single AWS DevOps Jump Server lifecycle using
Terraform, Ansible and AWS Systems Manager.**
