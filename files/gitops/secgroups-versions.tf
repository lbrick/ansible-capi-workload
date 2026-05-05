terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54.0"
    }
  }
  backend "kubernetes" {
    secret_suffix     = "placeholder"
    namespace         = "flux-system"
    in_cluster_config = true
  }
}

provider "openstack" {
  cloud = "openstack"
}
