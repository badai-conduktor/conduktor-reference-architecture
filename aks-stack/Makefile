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
infra: ## Deploy Azure infrastructure (AKS, App Gateway, Storage, Key Vault)
	$(CURDIR)/01-infra.sh

.PHONY: start-aks-stack
start-aks-stack: ## Deploy dependencies to AKS
	$(CURDIR)/02-start.sh

.PHONY: install-conduktor-platform
install-conduktor-platform: ## Install Conduktor Console and Gateway
	$(CURDIR)/03-install-conduktor-platform.sh

.PHONY: init-conduktor-platform
init-conduktor-platform: ## Provision Conduktor platform via Terraform
	$(CURDIR)/04-init-conduktor-platform.sh

.PHONY: stop-aks-stack
stop-aks-stack: ## Teardown AKS stack (K8s resources only)
	$(CURDIR)/05-stop.sh

.PHONY: destroy-infra
destroy-infra: ## Destroy Azure infrastructure via Terraform
	$(CURDIR)/06-destroy-infra.sh
