#!/usr/bin/env bash

# Stop on errors, undefined variables, and failed pipeline commands.
set -Eeuo pipefail

# --------------------------------------------------
# 1. PROJECT CONFIGURATION
# --------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

TERRAFORM_DIR="${PROJECT_ROOT}/terraform/aws-lab/environments/jump-server/dev"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
VENV_DIR="${ANSIBLE_DIR}/.venv"
VENV_ACTIVATE="${VENV_DIR}/bin/activate"

CONFIG_LOADER="${PROJECT_ROOT}/scripts/lib/config.sh"

# Operational retry settings.
EC2_WAIT_ATTEMPTS=60
SSM_WAIT_ATTEMPTS=60
WAIT_INTERVAL=10

# --------------------------------------------------
# 2. LOGGING AND ERROR HANDLING
# --------------------------------------------------

log() {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

fail() {
    log "ERROR: $1"
    exit 1
}

on_error() {
    local exit_code=$?
    log "Script failed at line ${BASH_LINENO[0]} with exit code ${exit_code}."
    exit "$exit_code"
}

trap on_error ERR

# --------------------------------------------------
# 3. LOAD AND VALIDATE PROJECT CONFIGURATION
# --------------------------------------------------

[[ -f "${CONFIG_LOADER}" ]] \
    || fail "Project configuration loader is missing: ${CONFIG_LOADER}"

source "${CONFIG_LOADER}"

load_project_config     || fail "Could not load project configuration."

# Keep AWS CLI profile selection consistent.
export AWS_DEFAULT_PROFILE="${AWS_PROFILE}"

# --------------------------------------------------
# 4. CHECK REQUIRED SYSTEM COMMANDS AND FILES
# --------------------------------------------------

log "Checking required system commands..."

for command_name in terraform aws session-manager-plugin; do
    command -v "${command_name}" >/dev/null 2>&1 \
        || fail "Required command not found: ${command_name}"
done

[[ -d "${TERRAFORM_DIR}" ]] \
    || fail "Terraform directory not found: ${TERRAFORM_DIR}"

[[ -d "${ANSIBLE_DIR}" ]] \
    || fail "Ansible directory not found: ${ANSIBLE_DIR}"

[[ -f "${VENV_ACTIVATE}" ]] \
    || fail "Ansible virtual environment is missing. Run ./scripts/setup.sh first."

[[ -f "${ANSIBLE_DIR}/inventory/jump-server.aws_ec2.yml" ]] \
    || fail "Dynamic inventory file is missing."

# --------------------------------------------------
# 5. ACTIVATE AND VERIFY ANSIBLE ENVIRONMENT
# --------------------------------------------------

log "Activating Ansible virtual environment..."

source "${VENV_ACTIVATE}"

for command_name in ansible ansible-playbook ansible-inventory; do
    command -v "${command_name}" >/dev/null 2>&1 \
        || fail "Required Ansible command not found: ${command_name}"
done

cd "${ANSIBLE_DIR}"

log "Ansible version:"
ansible --version

# --------------------------------------------------
# 6. VERIFY AWS IDENTITY
# --------------------------------------------------

log "Checking AWS identity..."

AWS_ACCOUNT_ID="$(
    aws sts get-caller-identity \
        --profile "${AWS_PROFILE}" \
        --region "${AWS_REGION}" \
        --query 'Account' \
        --output text
)"

log "Authenticated AWS account: ${AWS_ACCOUNT_ID}"

# --------------------------------------------------
# 7. VALIDATE ANSIBLE SSM S3 BUCKET
# --------------------------------------------------

log "Validating Ansible SSM S3 bucket..."

if ! aws s3api head-bucket \
    --bucket "${ANSIBLE_AWS_SSM_BUCKET_NAME}" \
    --expected-bucket-owner "${AWS_ACCOUNT_ID}" \
    --profile "${AWS_PROFILE}" \
    --region "${AWS_REGION}"; then
    fail "S3 bucket is missing, inaccessible, or does not belong to the authenticated AWS account."
fi

if ! BUCKET_REGION="$(
    aws s3api get-bucket-location \
        --bucket "${ANSIBLE_AWS_SSM_BUCKET_NAME}" \
        --expected-bucket-owner "${AWS_ACCOUNT_ID}" \
        --profile "${AWS_PROFILE}" \
        --region "${AWS_REGION}" \
        --query 'LocationConstraint' \
        --output text
)"; then
    fail "Could not determine the S3 bucket region."
fi

# AWS represents the us-east-1 bucket location as null.
if [[ "${BUCKET_REGION}" == "None" || -z "${BUCKET_REGION}" ]]; then
    BUCKET_REGION="us-east-1"
fi

if [[ "${BUCKET_REGION}" != "${AWS_REGION}" ]]; then
    fail "S3 bucket region (${BUCKET_REGION}) does not match AWS region (${AWS_REGION})."
fi

log "S3 bucket verified: ${ANSIBLE_AWS_SSM_BUCKET_NAME}"
log "S3 bucket region: ${BUCKET_REGION}"

# --------------------------------------------------
# 8. TERRAFORM INITIALIZATION AND APPLY
# --------------------------------------------------

log "Initializing Terraform..."

cd "${TERRAFORM_DIR}"

terraform init -input=false

# Create a private temporary plan file.
umask 077
PLAN_FILE="$(mktemp "${TMPDIR:-/tmp}/devops-jump-server.XXXXXX")"

cleanup() {
    if [[ -n "${PLAN_FILE}" ]]; then
        rm -f -- "${PLAN_FILE}"
    fi
}

trap cleanup EXIT

log "Generating Terraform deployment plan..."

terraform plan \
    -input=false \
    -out="${PLAN_FILE}" \
    -var="aws_region=${AWS_REGION}" \
    -var="aws_profile=${AWS_PROFILE}" \
    -var="project_name=${PROJECT_NAME}" \
    -var="environment=${ENVIRONMENT}"

log "Displaying Terraform deployment plan..."

terraform show -no-color "${PLAN_FILE}"

printf '\n'
printf '%s\n' "Review the Terraform plan carefully."
read -r -p "Type DEPLOY to approve AWS infrastructure deployment: " confirmation

if [[ "${confirmation}" != "DEPLOY" ]]; then
    log "Deployment cancelled. No Terraform apply was performed."
    exit 0
fi

log "Approval received. Applying the reviewed Terraform plan..."

terraform apply -input=false "${PLAN_FILE}"

# --------------------------------------------------
# 9. WAIT FOR EC2 INSTANCE TO BECOME RUNNING
# --------------------------------------------------

log "Waiting for the Jump Server EC2 instance..."

INSTANCE_ID=""

for ((attempt=1; attempt<=EC2_WAIT_ATTEMPTS; attempt++)); do

    INSTANCE_ROWS="$(
        aws ec2 describe-instances \
            --profile "${AWS_PROFILE}" \
            --region "${AWS_REGION}" \
            --filters \
                "Name=tag:Name,Values=${JUMP_SERVER_NAME}" \
                "Name=tag:Project,Values=${PROJECT_NAME}" \
                "Name=tag:Environment,Values=${ENVIRONMENT}" \
                "Name=instance-state-name,Values=pending,running,stopping,stopped" \
            --query 'Reservations[].Instances[].[InstanceId,State.Name]' \
            --output text
    )"

    INSTANCE_COUNT="$(
        printf '%s\n' "${INSTANCE_ROWS}" |
        awk 'NF { count++ } END { print count+0 }'
    )"

    if [[ "${INSTANCE_COUNT}" -gt 1 ]]; then
        fail "Found ${INSTANCE_COUNT} matching EC2 instances. Expected exactly one."
    fi

    if [[ "${INSTANCE_COUNT}" -eq 1 ]]; then
        read -r INSTANCE_ID INSTANCE_STATE <<< "${INSTANCE_ROWS}"

        if [[ "${INSTANCE_STATE}" == "running" ]]; then
            log "EC2 instance is running: ${INSTANCE_ID}"
            break
        fi

        log "EC2 state is ${INSTANCE_STATE}. Waiting..."
    else
        log "Matching EC2 instance not discovered yet. Waiting..."
    fi

    if [[ "${attempt}" -eq "${EC2_WAIT_ATTEMPTS}" ]]; then
        fail "Timed out waiting for EC2 instance to become running."
    fi

    sleep "${WAIT_INTERVAL}"
done

[[ -n "${INSTANCE_ID}" ]] || fail "Could not identify the EC2 instance."

# --------------------------------------------------
# 10. WAIT FOR AWS SYSTEMS MANAGER TO SHOW ONLINE
# --------------------------------------------------

log "Waiting for SSM registration..."

SSM_STATUS=""

for ((attempt=1; attempt<=SSM_WAIT_ATTEMPTS; attempt++)); do

    SSM_STATUS="$(
        aws ssm describe-instance-information \
            --profile "${AWS_PROFILE}" \
            --region "${AWS_REGION}" \
            --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null || true
    )"

    if [[ "${SSM_STATUS}" == "Online" ]]; then
        log "SSM is Online for ${INSTANCE_ID}"
        break
    fi

    log "SSM status: ${SSM_STATUS}. Waiting..."

    if [[ "${attempt}" -eq "${SSM_WAIT_ATTEMPTS}" ]]; then
        fail "Timed out waiting for SSM to become Online."
    fi

    sleep "${WAIT_INTERVAL}"
done

# --------------------------------------------------
# 11. VALIDATE DYNAMIC INVENTORY
# --------------------------------------------------

log "Validating AWS dynamic inventory..."

cd "${ANSIBLE_DIR}"

INVENTORY_GRAPH="$(ansible-inventory --graph)"

printf '%s\n' "${INVENTORY_GRAPH}"

grep -Fq "${JUMP_SERVER_NAME}" <<< "${INVENTORY_GRAPH}" \
    || fail "Jump Server was not found in dynamic inventory."

grep -Fq "@jump_servers:" <<< "${INVENTORY_GRAPH}" \
    || fail "Expected Ansible group jump_servers was not found."

# --------------------------------------------------
# 12. TEST SSM CONNECTION THROUGH ANSIBLE
# --------------------------------------------------

log "Testing Ansible connectivity..."

ansible jump_servers \
    -m ansible.builtin.ping

# --------------------------------------------------
# 13. RUN COMPLETE ANSIBLE CONFIGURATION
# --------------------------------------------------

log "Running the complete Ansible configuration..."

ansible-playbook playbooks/site.yml

# --------------------------------------------------
# 14. FINAL STATUS
# --------------------------------------------------

log "Jump Server rebuild and configuration completed successfully."

printf '\n'
printf '%s\n' "--------------------------------------------"
printf '%s\n' " PROJECT       : ${PROJECT_NAME}"
printf '%s\n' " ENVIRONMENT   : ${ENVIRONMENT}"
printf '%s\n' " AWS REGION    : ${AWS_REGION}"
printf '%s\n' " INSTANCE ID   : ${INSTANCE_ID}"
printf '%s\n' " SSM STATUS    : ${SSM_STATUS}"
printf '%s\n' " ANSIBLE GROUP : jump_servers"
printf '%s\n' "--------------------------------------------"
