output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_kube_config_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "appgw_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "blob_container_name" {
  value = azurerm_storage_container.cortex.name
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "key_vault_certificate_id" {
  value = azurerm_key_vault_certificate.wildcard.versionless_secret_id
}

output "cortex_identity_client_id" {
  value = azurerm_user_assigned_identity.cortex.client_id
}

output "kube_context" {
  value = var.aks_cluster_name
}
