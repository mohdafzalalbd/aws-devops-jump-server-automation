#!/usr/bin/env bash

# --------------------------------------------------
# PROJECT CONFIGURATION LOADER
# --------------------------------------------------

CONFIG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${CONFIG_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

load_project_config() {

    if [[ ! -f "${ENV_FILE}" ]]; then
        echo "ERROR: .env file not found."
        echo "Copy .env.example to .env and configure your settings."
        return 1
    fi

    declare -A config=()

    # Read configuration as plain text; never execute the file.
    while IFS= read -r line || [[ -n "${line}" ]]; do

        # Ignore blank lines and comments.
        [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue

        if [[ ! "${line}" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            echo "ERROR: Invalid configuration line in .env."
            return 1
        fi

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        # Allow only documented configuration keys.
        case "${key}" in
            AWS_PROFILE|AWS_REGION|AWS_DEFAULT_REGION|PROJECT_NAME|ENVIRONMENT|JUMP_SERVER_NAME|ANSIBLE_AWS_SSM_BUCKET_NAME)
                ;;
            *)
                echo "ERROR: Unsupported configuration key: ${key}"
                return 1
                ;;
        esac

        # Remove surrounding whitespace.
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        # Remove matching single or double quotes.
        if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
            value="${value:1:${#value}-2}"
        fi

        config["${key}"]="${value}"

    done < "${ENV_FILE}"

    # Apply defaults.
    export AWS_PROFILE="${config[AWS_PROFILE]:-default}"
    export AWS_REGION="${config[AWS_REGION]:-ap-south-1}"
    export AWS_DEFAULT_REGION="${config[AWS_DEFAULT_REGION]:-${AWS_REGION}}"

    export PROJECT_NAME="${config[PROJECT_NAME]:-my-devops-lab}"
    export ENVIRONMENT="${config[ENVIRONMENT]:-learning}"
    export JUMP_SERVER_NAME="${config[JUMP_SERVER_NAME]:-${PROJECT_NAME}-${ENVIRONMENT}-jump-server}"

    export ANSIBLE_AWS_SSM_BUCKET_NAME="${config[ANSIBLE_AWS_SSM_BUCKET_NAME]:-}"

    # Validate required values.
    if [[ ! "${AWS_PROFILE}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        echo "ERROR: AWS_PROFILE contains invalid characters."
        return 1
    fi

    if [[ ! "${AWS_REGION}" =~ ^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$ ]]; then
        echo "ERROR: Invalid AWS_REGION format."
        return 1
    fi

    if [[ "${AWS_DEFAULT_REGION}" != "${AWS_REGION}" ]]; then
        echo "ERROR: AWS_DEFAULT_REGION must match AWS_REGION."
        return 1
    fi

    if [[ ! "${PROJECT_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] ||
       [[ ! "${ENVIRONMENT}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] ||
       [[ ! "${JUMP_SERVER_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        echo "ERROR: Invalid project, environment, or jump-server name."
        return 1
    fi

    if [[ -z "${ANSIBLE_AWS_SSM_BUCKET_NAME}" ]] ||
       [[ "${ANSIBLE_AWS_SSM_BUCKET_NAME}" == "YOUR_UNIQUE_S3_BUCKET_NAME" ]]; then
        echo "ERROR: Configure your own S3 bucket in .env."
        return 1
    fi

    if [[ ! "${ANSIBLE_AWS_SSM_BUCKET_NAME}" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] ||
       [[ "${ANSIBLE_AWS_SSM_BUCKET_NAME}" == *..* ]] ||
       [[ "${ANSIBLE_AWS_SSM_BUCKET_NAME}" == *.-* ]] ||
       [[ "${ANSIBLE_AWS_SSM_BUCKET_NAME}" == *-. ]]; then
        echo "ERROR: S3 bucket name does not meet the expected naming rules."
        return 1
    fi

    echo "Project configuration loaded successfully."
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Profile: ${AWS_PROFILE}"
    echo "Project: ${PROJECT_NAME}"
    echo "Environment: ${ENVIRONMENT}"
    echo "Jump Server: ${JUMP_SERVER_NAME}"
    echo "SSM Bucket: configured"
}
