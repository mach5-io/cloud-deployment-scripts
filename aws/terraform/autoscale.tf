resource "helm_release" "autoscale-release_gcp" {
  count = (var.enable_cluster_autoscaling && !var.use_ecr) ? 1 : 0
  name        = "autoscale-release"
  namespace   = "default"
  repository  = "https://kubernetes.github.io/autoscaler"
  #version     = "9.34.1"
  chart       = "cluster-autoscaler"
  create_namespace = false
  values = [
    file("${path.module}/values_ca.yaml")
  ]
  wait = true 

  set {
    name  = "autoDiscovery.clusterName"
    value = aws_eks_cluster.mach5-cluster.name
  }
  provider   = helm.gcp
}

resource "helm_release" "autoscale-release_ecr" {
  count = (var.enable_cluster_autoscaling && var.use_ecr) ? 1 : 0
  name        = "autoscale-release"
  namespace   = "default"
  repository  = "https://kubernetes.github.io/autoscaler"
  #version     = "9.34.1"
  chart       = "cluster-autoscaler"
  create_namespace = false
  values = [
    file("${path.module}/values_ca.yaml")
  ]
  wait = true 

  set {
    name  = "autoDiscovery.clusterName"
    value = aws_eks_cluster.mach5-cluster.name
  }
  provider   = helm.ecr
}

resource "kubernetes_config_map" "configmap_cluster_autoscaler_priority_expander" {
  count = var.spot_fallback_to_ondemand ? 1 : 0
  metadata {
    name = "cluster-autoscaler-priority-expander"
    namespace = "default"
  }

  data = {
    priorities = <<-EOT
      50:
        - .*compactor.*
        - .*ingestor.*
      10:
        - .*ondemand-ingest.*
        - .*ondemand-compact.*
      0:
        - .*
      EOT
  }
}