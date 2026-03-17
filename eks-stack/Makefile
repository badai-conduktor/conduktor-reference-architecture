# Global Vars
#############
WORKING_DIR 	     = $(shell pwd)

# Main targets you should run
#############################
.DEFAULT_GOAL := help

.PHONY: help
help: ## Prints help for targets with comments
	@cat $(MAKEFILE_LIST) | grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: infra
infra: ## Deploy AWS infrastructure (VPC, EKS, IAM, S3, ACM) via Terraform
	cd $(CURDIR)/infrastructure && terraform init && terraform apply

.PHONY: start-eks-stack
start-eks-stack: ## Deploy K8s dependencies to EKS
	$(CURDIR)/01-start.sh

.PHONY: install-conduktor-platform
install-conduktor-platform: ## Install Conduktor Console and Gateway
	$(CURDIR)/02-install-conduktor-platform.sh

.PHONY: init-conduktor-platform
init-conduktor-platform: ## Provision Conduktor platform via Terraform
	$(CURDIR)/03-init-conduktor-platform.sh

.PHONY: stop-eks-stack
stop-eks-stack: ## Teardown EKS stack (K8s resources only)
	$(CURDIR)/04-stop.sh

.PHONY: destroy-infra
destroy-infra: ## Destroy AWS infrastructure via Terraform
	cd $(CURDIR)/infrastructure && terraform destroy
