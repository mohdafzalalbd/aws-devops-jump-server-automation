# AWS DevOps Jump Server Automation

A reusable Infrastructure as Code (IaC) and configuration-management project for provisioning an AWS DevOps Jump Server using Terraform and Ansible.

The project provisions AWS networking, configures IAM permissions for AWS Systems Manager (SSM), creates an Ubuntu EC2 instance and installs essential DevOps tools through Ansible.

Each user deploys and manages independent infrastructure using their own AWS account, credentials, Terraform state and S3 transfer bucket.

---

## 1. Project Overview

### Current implementation

- AWS VPC and public subnet provisioning
- Internet Gateway and public routing
- IAM role and instance profile for Systems Manager
- Ubuntu 24.04 LTS EC2 Jump Server
- AMD64 and ARM64 architecture configuration
- Encrypted gp3 root EBS volume
- IMDSv2 enforcement
- No inbound SSH security-group rules
- Ansible dynamic EC2 inventory
- AWS Systems Manager-based remote administration
- Automated installation of DevOps tools

### Tools installed on the Jump Server

| Tool | Purpose |
|---|---|
| AWS CLI v2 | AWS resource management |
| Terraform | Infrastructure as Code |
| Docker | Container management |
| kubectl | Kubernetes administration |
| Helm | Kubernetes package management |
| eksctl | Amazon EKS cluster management |

**Project scope:** The Docker, ELK, Jenkins and Kubernetes directories are reserved for future expansion. Their complete application or platform implementations are not currently included.

---

## 2. Architecture

```text
Developer / Ansible Controller
            |
            | AWS Credentials
            |
            +-----------------------------+
            |                             |
            v                             v
     AWS EC2 Dynamic Inventory      S3 Transfer Bucket
            |                             |
            +-------------+---------------+
                          |
                          v
                 AWS Systems Manager
                          |
                          v
                    AWS Account
                          |
                          v
                  AWS VPC 10.0.0.0/16
                          |
                 Public Subnet
                  10.0.1.0/24
                          |
             +------------+-------------+
             |                          |
             v                          v
       Internet Gateway          Public Route Table
             |                          |
             +------------+-------------+
                          |
                          v
                    EC2 Jump Server
                    Ubuntu 24.04 LTS
                          |
                  IAM Instance Profile
                          |
               AmazonSSMManagedInstanceCore
```

The Jump Server is managed through AWS Systems Manager rather than inbound SSH.

The public subnet and Internet Gateway provide outbound internet connectivity. The EC2 security group has no inbound rules and permits outbound IPv4 traffic.

---

## 3. Repository Structure

```text
aws-devops-jump-server-automation/
│
├── .env.example
├── .gitignore
├── README.md
│
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.txt
│   ├── requirements.yml
│   │
│   ├── inventory/
│   │   ├── jump-server.aws_ec2.yml
│   │   └── jump-server.ini
│   │
│   ├── playbooks/
│   │   ├── site.yml
│   │   ├── connectivity.yml
│   │   ├── common.yml
│   │   ├── aws-cli.yml
│   │   ├── terraform.yml
│   │   ├── docker.yml
│   │   ├── kubectl.yml
│   │   ├── helm.yml
│   │   └── eksctl.yml
│   │
│   └── roles/
│       ├── common/
│       ├── aws_cli/
│       ├── terraform/
│       ├── docker/
│       ├── kubectl/
│       ├── helm/
│       └── eksctl/
│
├── scripts/
│   ├── setup.sh
│   ├── rebuild-jump-server.sh
│   └── lib/
│       └── config.sh
│
└── terraform/
    └── aws-lab/
        ├── environments/
        │   └── jump-server/
        │       └── dev/
        │
        └── modules/
            ├── network/
            ├── iam-ssm/
            └── jump-server/
```

---

## 4. Prerequisites

### Local machine

The following tools must be installed on the machine running the deployment scripts.

| Requirement | Version / Details |
|---|---|
| Linux / WSL | Ubuntu recommended |
| Python | 3.11 or newer |
| AWS CLI | Version 2 |
| Terraform | 1.5.0 or newer |
| Session Manager plugin | Installed and available in PATH |
| AWS account | Active account with required permissions |
| AWS credentials | Configured local profile |

On Ubuntu, Python virtual-environment support may need to be installed separately:

```bash
sudo apt update
sudo apt install -y python3-venv
```

The setup script installs Ansible Python dependencies and the required AWS Ansible collection. It does not install the system-level AWS CLI, Terraform CLI or Session Manager plugin.

### Ansible dependencies

Python requirements:

- ansible-core 2.18.20
- boto3 1.43.126

Ansible collection:

- amazon.aws 11.5.1

---

## 5. Clone the Repository

```bash
git clone https://github.com/mohdafzalalbd/aws-devops-jump-server-automation.git

cd aws-devops-jump-server-automation
```


---

## 6. First-Time Setup

Make the setup script executable and run it:

```bash
chmod +x scripts/setup.sh

./scripts/setup.sh
```

The setup script:

1. Checks Python 3.11 or newer.
2. Creates `.env` from `.env.example`.
3. Creates `terraform.tfvars` from its example.
4. Creates an independent Ansible virtual environment.
5. Installs pinned Python dependencies.
6. Installs the required Ansible collection.
7. Verifies Ansible and Python package dependencies.

The script does not deploy AWS infrastructure.

Activate the environment when working with Ansible manually:

```bash
source ansible/.venv/bin/activate
```

---

## 7. AWS Configuration

### Configure `.env`

Edit the generated `.env` file:

```bash
nano .env
```

Example:

```dotenv
AWS_PROFILE=default
AWS_REGION=ap-south-1
AWS_DEFAULT_REGION=ap-south-1

PROJECT_NAME=my-devops-lab
ENVIRONMENT=learning
JUMP_SERVER_NAME=my-devops-lab-learning-jump-server

ANSIBLE_AWS_SSM_BUCKET_NAME=YOUR_UNIQUE_S3_BUCKET_NAME
```

Replace the example profile, project identifiers and S3 bucket name with your own values.

The AWS profile must exist in your local AWS CLI configuration.

Verify your identity:

```bash
aws sts get-caller-identity --profile default
```

Never commit `.env` or AWS credentials.

### Configure Terraform variables

Edit:

```bash
nano terraform/aws-lab/environments/jump-server/dev/terraform.tfvars
```

Example:

```hcl
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

Keep these values consistent:

- `aws_region` must match `AWS_REGION`.
- `aws_profile` must match `AWS_PROFILE`.
- `project_name` must match `PROJECT_NAME`.
- `environment` must match `ENVIRONMENT`.
- `JUMP_SERVER_NAME` must match the resulting Terraform resource name: `<project_name>-<environment>-jump-server`.

The dynamic inventory uses project, environment and server-name tags to discover the correct running EC2 instance. Inconsistent values can prevent discovery.

### Architecture options

AMD64:

```hcl
ami_architecture = "amd64"
instance_type    = "t3.small"
```

ARM64:

```hcl
ami_architecture = "arm64"
instance_type    = "t4g.small"
```

Choose an instance type compatible with the selected architecture and available in your AWS region.

The architecture configuration has been validated through Terraform planning and compatibility checks. Actual deployment and runtime validation should be performed in the user's own AWS account.

---

## 8. Configure the Ansible SSM S3 Bucket

The Ansible AWS SSM connection plugin uses S3 for file and module transfers.

Each user must create their own S3 bucket in their AWS account.

Requirements:

- Use a globally unique bucket name.
- Use the same AWS region as the EC2 instance.
- Keep S3 Block Public Access enabled.
- Grant the local AWS identity the required bucket and object permissions.
- Do not use another user's bucket.

The local AWS identity running Ansible generally requires:

- `s3:GetObject`
- `s3:PutObject`
- `s3:ListBucket`
- `s3:DeleteObject`
- `s3:GetBucketLocation`

Configure the bucket name in `.env`:

```dotenv
ANSIBLE_AWS_SSM_BUCKET_NAME=your-unique-bucket-name
```

### Important IAM distinction

There are two separate AWS access contexts:

**Local Ansible controller identity**

- Uses the configured AWS CLI profile.
- Discovers EC2 instances.
- Connects through Systems Manager.
- Accesses the S3 transfer bucket.

**EC2 instance IAM role**

- Uses the EC2 instance profile.
- Receives `AmazonSSMManagedInstanceCore`.
- Supports Systems Manager management of the instance.

The EC2 IAM role does not automatically receive the local controller's S3 bucket permissions.

The rebuild script checks bucket accessibility, expected bucket ownership and region before continuing. This preflight does not test every individual S3 object operation.

---

## 9. Infrastructure Deployment

The main deployment script is:

```bash
./scripts/rebuild-jump-server.sh
```

The script performs the following workflow:

1. Loads and validates project configuration.
2. Checks local system prerequisites.
3. Activates the Ansible virtual environment.
4. Verifies AWS account identity.
5. Checks the S3 transfer bucket.
6. Initializes Terraform.
7. Generates a Terraform plan.
8. Displays the plan for review.
9. Requests explicit deployment approval.
10. Waits for the EC2 instance to become running.
11. Waits for SSM registration.
12. Discovers the Jump Server through dynamic inventory.
13. Tests Ansible connectivity.
14. Executes the complete Ansible configuration playbook.

### Deployment approval

The script displays the Terraform plan and asks:

```text
Type DEPLOY to approve AWS infrastructure deployment:
```

Only entering the exact word:

```text
DEPLOY
```

approves the Terraform apply operation.

Any other response cancels deployment.

Always inspect the plan before approving it.

The deployment script does not automatically destroy infrastructure if a later Ansible configuration step fails. Review the AWS resources and Terraform state before attempting recovery.

---

## 10. Ansible Configuration

The main playbook is:

```text
ansible/playbooks/site.yml
```

To run Ansible commands manually, first load and validate the project configuration:

```bash
source scripts/lib/config.sh
load_project_config
export AWS_DEFAULT_PROFILE="${AWS_PROFILE}"
cd ansible

source .venv/bin/activate
```

The execution sequence is:

```text
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

Run the complete configuration:

```bash
ansible-playbook playbooks/site.yml
```

Individual playbooks can also be executed separately:

```bash
ansible-playbook playbooks/docker.yml
```

Test dynamic inventory:

```bash
ansible-inventory --graph
```

### Using a local static inventory (alternative)

To configure a specific EC2 instance manually instead of using dynamic discovery:

```bash
cp inventory/jump-server.ini inventory/jump-server.local.ini
nano inventory/jump-server.local.ini
```

Replace the placeholders with your EC2 instance ID, AWS region and private S3 transfer bucket name.

Validate the inventory:

```bash
ansible-inventory -i inventory/jump-server.local.ini --graph
```

Run the playbook using this inventory:

```bash
ansible-playbook -i inventory/jump-server.local.ini playbooks/site.yml
```

The local inventory is excluded by `.gitignore`. Never commit account-specific inventory details.

Test connectivity:

```bash
ansible jump_servers -m ansible.builtin.ping
```

The project uses the `amazon.aws.aws_ssm` connection plugin. SSH access is not required.

---

## 11. Terraform State Management

This project uses Terraform's default local backend.

Each user maintains an independent state file within their own local clone.

Important rules:

- Do not commit Terraform state files.
- Do not share state files between users.
- Do not overwrite another user's Terraform configuration.
- Keep the `.terraform.lock.hcl` provider lock file under version control.
- Keep `.terraform/` and Terraform plan files out of Git.

A remote backend is not configured by default.

---

## 12. Security Considerations

The infrastructure implements the following protections:

- No inbound security-group rules.
- SSM-based remote management.
- IAM instance profile for EC2.
- Encrypted gp3 root volume.
- IMDSv2 required.
- Ubuntu AMI selected from the official Canonical owner.
- Architecture compatibility validation.
- No hardcoded personal AWS credentials.
- Local Terraform variables and state excluded from Git.

The security group allows unrestricted outbound IPv4 traffic. This is functional for the current design but broader than a restricted-egress production configuration.

The S3 bucket should remain private.

The `.gitignore` rules help prevent accidental commits of local configuration and sensitive files. They do not remove files that have already been committed. Review repository contents before publishing.

---

## 13. Cleanup and Infrastructure Lifecycle

The rebuild script does not automatically destroy infrastructure.

When you no longer need your Jump Server, use the same Terraform working directory and the state file belonging to that deployment.

```bash
cd terraform/aws-lab/environments/jump-server/dev
```

Initialize Terraform if necessary:

```bash
terraform init
```

Review the proposed destruction:

```bash
terraform plan -destroy
```

If the plan contains only resources you intend to remove, execute:

```bash
terraform destroy
```

**Warning:** `terraform destroy` is destructive. It removes resources managed by the selected Terraform state. Review the plan carefully and make sure you are using your own deployment's state.

The manually created S3 transfer bucket is not managed by these Terraform modules and will not automatically be deleted by this command.

Do not delete the S3 transfer bucket or its contents until you have confirmed that no active workflow depends on them.

---

## 14. Cost Awareness

AWS resources can incur charges.

Potential cost-generating resources include:

- EC2 instance
- EBS volumes
- Public IPv4 address
- Data transfer
- S3 storage and requests

Charges vary by AWS region, instance type, usage and current AWS pricing.

This project does not guarantee Free Tier eligibility.

Deploy only when required and review AWS billing regularly.

---

## 15. Troubleshooting

| Problem | Initial checks |
|---|---|
| AWS credentials error | Check AWS profile and `aws sts get-caller-identity` |
| Terraform initialization error | Check provider access and lock file |
| No inventory hosts found | Check EC2 state and project/environment tags |
| SSM connection failure | Check SSM agent, IAM role, connectivity and plugin |
| S3 bucket error | Check bucket name, region, owner and permissions |
| Ansible dependency error | Activate the virtual environment and rerun dependency installation |
| Architecture mismatch | Match the AMI architecture with a compatible EC2 instance type |
| Ansible command not found | Activate `ansible/.venv` and check the working directory |

---

## 16. Project Roadmap

### Current implementation

- [x] Terraform AWS networking module
- [x] Terraform IAM SSM module
- [x] Terraform Jump Server module
- [x] AMD64 and ARM64 configuration
- [x] Ansible dynamic EC2 inventory
- [x] SSM-based connectivity
- [x] AWS CLI installation
- [x] Terraform installation
- [x] Docker installation
- [x] kubectl installation
- [x] Helm installation
- [x] eksctl installation

### Future expansion areas

- [ ] Docker application deployment examples
- [ ] Kubernetes application manifests
- [ ] Jenkins CI/CD integration
- [ ] ELK Stack deployment
- [ ] Additional monitoring and observability automation

---

## 17. Important Disclaimer

This repository is a reusable learning and automation blueprint.

Every user is responsible for:

- Their own AWS account and credentials.
- Their own infrastructure and Terraform state.
- Their own S3 transfer bucket.
- Reviewing Terraform plans before deployment.
- Monitoring AWS costs.
- Managing and cleaning up deployed resources.

Never publish AWS access keys, secret keys, Terraform state files, private keys or personal configuration files.

**The repository is intended to help users understand and implement reusable AWS infrastructure automation using Terraform, Ansible and Systems Manager.**
