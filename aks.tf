variable "location" {
  type    = string
  default = "centralus"
}

variable "dnsprefix" {
  type        = string
  description = "DNS prefix must contain between 2 and 45 characters. The name can contain only letters, numbers, and hyphens."
  default     = "dgdns"
}

variable "clusterName" {
  type        = string
  description = "Cluster Name must contain between 2 and 45 characters. The name can contain only letters, numbers, and hyphens."
  default     = "dgakstest"
}

variable "acrName" {
  type        = string
  description = "Set Container Registry Name. Name can contain only alphanumeric values."
  default     = "dgacr123"
}

variable "clientId" {
  type = string
}

variable "clientSecret" {
  type = string
}

variable "resgrp" {
 type = string
}

variable "tenantId" {
 type = string
}

variable "subscriptionId" {
 type = string
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 1.1.0"
    }
	kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}

  subscription_id = var.subscriptionId
  client_id       = var.clientId
  client_secret   = var.clientSecret
  tenant_id       = var.tenantId
  skip_provider_registration = true
}

data "azurerm_resource_group" "example" {
  name = var.resgrp
}

resource "azurerm_container_registry" "example" {
  name                = var.acrName
  resource_group_name = var.resgrp
  location            = var.location
  sku                 = "Standard"
}

resource "azurerm_public_ip" "example" {
  name                = "aksClusterPublicIp"
  resource_group_name = var.resgrp
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.clusterName
  
  tags = {
    source = "Morpheus"
  }
}

resource "azurerm_kubernetes_cluster" "example" {
  name                = var.clusterName
  location            = var.location
  resource_group_name = var.resgrp
  dns_prefix          = var.dnsprefix
  kubernetes_version  = "1.23.12"

  default_node_pool {
    name       = "default"
    node_count = 3 #as variable
    vm_size    = "Standard_D2_v2" #as variable (optionlist incl. Standard_D3_v2)
  }

  identity {
    type = "SystemAssigned"
  }
  
  network_profile {
    network_plugin     = "kubenet"
    load_balancer_sku  = "standard"
    load_balancer_profile {
        outbound_ip_address_ids = [ azurerm_public_ip.example.id ]
    }
  }

  tags = {
    source = "Morpheus"
  }
}

resource "azurerm_role_assignment" "publicIP" {
  principal_id                     = azurerm_kubernetes_cluster.example.identity[0].principal_id
  role_definition_name             = "Network Contributor"
  scope                            = data.azurerm_resource_group.example.id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "containerRegistry" {
  principal_id                     = azurerm_kubernetes_cluster.example.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.example.id
  skip_service_principal_aad_check = true
}

# apply ingress controller on aks
provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.example.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.example.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.example.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.example.kube_config.0.cluster_ca_certificate)
  load_config_file       = false
}

data "kubectl_file_documents" "docs" {
    content = file("ingress.yaml")
#    vars = {
#        aks_cluster_name = var.clusterName
#	resgrp           = var.resgrp
#	public_lb_ip     = azurerm_public_ip.example.id
#    }
}

resource "kubectl_manifest" "example" {
    for_each  = data.kubectl_file_documents.docs.manifests
    yaml_body = each.value
}

output "aks_public_dns" {
  value     = azurerm_public_ip.example.fqdn
  sensitive = true
}

output "acr_service_principal" {
  value     = azurerm_kubernetes_cluster.example.kubelet_identity[0]
  sensitive = true
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.example.kube_config.0.client_certificate
  sensitive = true
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.example.kube_config_raw
  sensitive = true
}
