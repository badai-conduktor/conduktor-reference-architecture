#!/usr/bin/env sh

set -e

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
INFRA_DIR="${SCRIPT_DIR}/infrastructure"

echo "Destroying Azure infrastructure..."

pushd "${INFRA_DIR}"
  if [ ! -f terraform.tfvars ]; then
    echo "terraform.tfvars not found. Nothing to destroy."
    exit 1
  fi

  terraform init -upgrade
  terraform destroy -var-file=terraform.tfvars -auto-approve
popd

echo
echo "Azure infrastructure destroyed!"
