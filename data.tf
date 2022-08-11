data "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = local.aks_name
  resource_group_name = local.aks_resource_group_name
}