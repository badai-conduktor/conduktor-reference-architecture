#!/usr/bin/env sh

set -e

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
INFRA_DIR="${SCRIPT_DIR}/infrastructure"

echo "Deploying Azure infrastructure..."

# Check for required tools
az --version > /dev/null 2>&1 || { echo >&2 "Azure CLI (az) is not installed. Please install it to continue."; exit 1; }
terraform --version > /dev/null 2>&1 || { echo >&2 "Terraform is not installed. Please install it to continue."; exit 1; }

# Ensure logged in to Azure
az account show > /dev/null 2>&1 || { echo >&2 "Not logged in to Azure. Run 'az login' first."; exit 1; }

pushd "${INFRA_DIR}"
  if [ ! -f terraform.tfvars ]; then
    echo "terraform.tfvars not found. Copy terraform.tfvars.example to terraform.tfvars and fill in your values."
    exit 1
  fi

  echo
  echo "01 - Initializing Terraform"
  terraform init -upgrade

  echo
  echo "02 - Applying Terraform (this may take 10-15 minutes)"
  terraform apply -var-file=terraform.tfvars -auto-approve

  echo
  echo "03 - Configuring kubectl"
  eval "$(terraform output -raw aks_kube_config_command)"

  echo
  echo "Infrastructure deployment complete!"
  echo
  echo "Terraform outputs:"
  terraform output
  echo
  echo "Update your config.env with the values above, then run:"
  echo "  make start-aks-stack"
popd
