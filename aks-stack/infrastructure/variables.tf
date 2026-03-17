variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "conduktor-aks-rg"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "conduktor-aks"
}

variable "aks_node_count" {
  description = "Number of nodes in the AKS default node pool"
  type        = number
  default     = 3
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "storage_account_name" {
  description = "Name of the Azure Storage Account (must be globally unique, lowercase, no hyphens)"
  type        = string
  default     = "conduktorstorage"
}

variable "blob_container_name" {
  description = "Name of the Blob container for Cortex monitoring"
  type        = string
  default     = "conduktor-monitoring"
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault (must be globally unique)"
  type        = string
  default     = "conduktor-kv"
}

variable "domain" {
  description = "Base domain for Conduktor services"
  type        = string
  default     = "conduktor.test"
}

variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aks_subnet_prefix" {
  description = "Address prefix for the AKS subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "appgw_subnet_prefix" {
  description = "Address prefix for the Application Gateway subnet"
  type        = string
  default     = "10.0.2.0/24"
}
