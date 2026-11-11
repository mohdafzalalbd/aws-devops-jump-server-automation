#!/usr/bin/env bash

# Stop on errors, undefined variables, and failed pipeline commands.
set -Eeuo pipefail

# --------------------------------------------------
# 1. PROJECT PATHS
# --------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
VENV_DIR="${ANSIBLE_DIR}/.venv"

ENV_EXAMPLE="${PROJECT_ROOT}/.env.example"
ENV_FILE="${PROJECT_ROOT}/.env"

TF_DIR="${PROJECT_ROOT}/terraform/aws-lab/environments/jump-server/dev"
TFVARS_EXAMPLE="${TF_DIR}/terraform.tfvars.example"
TFVARS_FILE="${TF_DIR}/terraform.tfvars"

log() {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

fail() {
    log "ERROR: $1"
    exit 1
}

# --------------------------------------------------
# 2. VERIFY PREREQUISITES
# --------------------------------------------------

log "Checking setup prerequisites..."

command -v python3 >/dev/null 2>&1 \
    || fail "Python 3 is required. Install Python 3.11 or newer."

python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' \
    || fail "Python 3.11 or newer is required for the pinned Ansible version."

[[ -f "${ANSIBLE_DIR}/requirements.txt" ]] \
    || fail "Ansible Python requirements file is missing."

[[ -f "${ANSIBLE_DIR}/requirements.yml" ]] \
    || fail "Ansible collection requirements file is missing."

[[ -f "${ENV_EXAMPLE}" ]] \
    || fail ".env.example is missing."

[[ -f "${TFVARS_EXAMPLE}" ]] \
    || fail "terraform.tfvars.example is missing."

PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

log "Detected Python version: ${PYTHON_VERSION}"

# --------------------------------------------------
# 3. CREATE USER CONFIGURATION FILES
# --------------------------------------------------

if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    log "Created .env from .env.example."
else
    chmod 600 "${ENV_FILE}"
    log "Existing .env preserved."
fi

if [[ ! -f "${TFVARS_FILE}" ]]; then
    cp "${TFVARS_EXAMPLE}" "${TFVARS_FILE}"
    log "Created terraform.tfvars from its example."
else
    log "Existing terraform.tfvars preserved."
fi

# Restrict access to user-specific Terraform configuration.
chmod 600 "${TFVARS_FILE}"

# --------------------------------------------------
# 4. CREATE PYTHON VIRTUAL ENVIRONMENT
# --------------------------------------------------

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    log "Creating independent Ansible virtual environment..."

    if ! python3 -m venv "${VENV_DIR}"; then
        fail "Could not create the virtual environment. On Ubuntu, install it using: sudo apt update && sudo apt install -y python3-venv"
    fi
else
    log "Existing Ansible virtual environment detected."
fi

source "${VENV_DIR}/bin/activate"

# --------------------------------------------------
# 5. INSTALL PYTHON DEPENDENCIES
# --------------------------------------------------

log "Installing pinned Ansible Python dependencies..."

python -m pip install -r "${ANSIBLE_DIR}/requirements.txt"

# --------------------------------------------------
# 6. INSTALL ANSIBLE COLLECTIONS
# --------------------------------------------------

log "Installing required Ansible collections..."

cd "${ANSIBLE_DIR}"

ansible-galaxy collection install -r requirements.yml

# --------------------------------------------------
# 7. VERIFY INSTALLATION
# --------------------------------------------------

log "Verifying installed tools..."

ansible --version
python -m pip check

log "First-time setup completed successfully."

printf '\n'
printf '%s\n' "--------------------------------------------"
printf '%s\n' " NEXT CONFIGURATION STEPS"
printf '%s\n' "--------------------------------------------"
printf '%s\n' "1. Edit .env and configure your own AWS profile."
printf '%s\n' "2. Configure your own S3 bucket for Ansible SSM."
printf '%s\n' "3. Review terraform.tfvars."
printf '%s\n' "4. Verify your AWS credentials before deployment."
printf '%s\n' "5. Review the Terraform plan before approving deployment."
printf '%s\n' "--------------------------------------------"
printf '%s\n' "No AWS infrastructure was deployed by this script."
