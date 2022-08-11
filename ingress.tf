provider "helm" {
  debug   = true
  kubernetes {
    host = data.azurerm_kubernetes_cluster.aks_cluster.kube_config[0].host

    client_key             = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_key)
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_certificate)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = data.azurerm_kubernetes_cluster.aks_cluster.kube_config[0].host
  client_key             = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_key)
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_certificate)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks_cluster.kube_config[0].cluster_ca_certificate)
  load_config_file       = false
}

resource "helm_release" "csi_secrets_store_provider" {
  depends_on       = [data.azurerm_kubernetes_cluster.aks_cluster]
  name             = local.csi_secrets_store_name
  repository       = "https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts"
  chart            = "csi-secrets-store-provider-azure"
  namespace        = local.namespace
  
  values = [
    file("./manifests/secretStore.yaml")
  ]
}

resource "kubectl_manifest" "create_secret_prov_class" {
  depends_on = [helm_release.csi_secrets_store_provider] 
  yaml_body  = templatefile("./manifests/secretProviderClassVar.yaml", 
                            {namespace_name = local.namespace,
							 key_vault_name = local.key_vaults.key_vault_name,
							 cert_name      = local.ingress_cert_name,
							 tenant_id      = data.azurerm_client_config.current.tenant_id})
}

resource "helm_release" "create_ingress_controller" {
  depends_on       = [kubectl_manifest.create_secret_prov_class, module.aks_pod_identity]
  name             = local.ingress_nginx_name
  repository       = "https://kubernetes.github.io/ingress-nginx/"
  chart            = "ingress-nginx"
  namespace        = local.namespace

  values = [
    templatefile("./manifests/ingressControllerVar.yaml",
	             {key_vault_name = local.key_vaults.key_vault_name,
				  pod_id_name    = local.pod_identity_name})
  ]
}

resource "kubectl_manifest" "create_ingress" {
  depends_on = [helm_release.create_ingress_controller] 
  yaml_body  = templatefile("./manifests/ingressVar.yaml", 
                            {ingress_name   = local.ingress_name,
							 namespace_name = local.namespace,
							 fqdn_name      = local.fqdn_name,
							 cert_name      = local.ingress_cert_name,
							 service_name   = local.service_name})
}
