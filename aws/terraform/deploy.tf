provider "helm" {
  alias = "gcp"
  kubernetes {
    host                   = aws_eks_cluster.mach5-cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.mach5-cluster.certificate_authority.0.data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.mach5-cluster.id]
      command     = "aws"
    }
  }
  registry {
    url = var.use_ecr ? "" : var.artifact_registry_url
    username = var.use_ecr ? "" : var.artifact_registry_username
    password = var.use_ecr ? "" : var.artifact_registry_password
  }
}

provider "helm" {
  alias = "ecr"

  kubernetes {
    host                   = aws_eks_cluster.mach5-cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.mach5-cluster.certificate_authority.0.data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.mach5-cluster.id]
      command     = "aws"
    }
  }
}

provider "kubectl" {
  host                   = aws_eks_cluster.mach5-cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.mach5-cluster.certificate_authority.0.data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", aws_eks_cluster.mach5-cluster.id]
  }
}

data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.mach5-cluster.name
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.mach5-cluster.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

resource "kubernetes_namespace" "cm" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "cm_gcp" {
  count = var.use_ecr ? 0 : 1
  name             = "cm"
  namespace        = kubernetes_namespace.cm.metadata[0].name
  create_namespace = false
  chart            = "cert-manager"
  repository       = "https://charts.jetstack.io"
  version          = "v1.5.3"
  values = [
    file("values_cm.yaml")
  ]
  provider   = helm.gcp
}

resource "kubernetes_namespace" "cache-proxy" {
  metadata {
    name = "cache-proxy"
  }
}

resource "helm_release" "mach5-cache-proxy" {
  count = var.use_ecr ? 0 : 1
  create_namespace = false
  name        = "m5-cache"
  namespace   = kubernetes_namespace.cache-proxy.metadata[0].name
  repository  = var.mach5_helm_repository
  version     = var.cache_proxy_version
  chart       = "mach5-cache-proxy"
  values = [
    file("values_cp.yaml")
  ]
  depends_on = [ helm_release.cm_gcp ]
  provider   = helm.gcp
}

resource "kubernetes_namespace" "mach5" {
  metadata {
    name = var.namespace
  }
}
 
resource "kubectl_manifest" "fdb_clusters" {
  yaml_body = file("${path.module}/crds/apps.foundationdb.org_foundationdbclusters.yaml")
  depends_on = [kubernetes_namespace.mach5 ]
}

resource "kubectl_manifest" "fdb_backups" {
  yaml_body = file("${path.module}/crds/apps.foundationdb.org_foundationdbbackups.yaml")
  depends_on = [ kubectl_manifest.fdb_clusters ]
}

resource "kubectl_manifest" "fdb_restores" {
  yaml_body = file("${path.module}/crds/apps.foundationdb.org_foundationdbrestores.yaml")
  depends_on = [ kubectl_manifest.fdb_backups ]
}

resource "helm_release" "cm_ecr" {
  count = var.use_ecr ? 1 : 0
  name             = "cm"
  namespace        = kubernetes_namespace.cm.metadata[0].name
  create_namespace = false
  chart            = "cert-manager"
  repository       = "https://charts.jetstack.io"
  version          = "v1.5.3"
  values = [
    file("values_cm.yaml")
  ]
  provider   = helm.ecr
}

resource "helm_release" "mach5-release-gcp" {
  count = var.use_ecr ? 0 : 1
  name        = var.mach5_helm_release_name
  namespace   = var.namespace
  repository  = var.mach5_helm_repository
  version     = var.mach5_helm_chart_version
  chart       = var.mach5_helm_chart_name
  values = [
    file("${path.module}/values.yaml")
  ]
  wait = false 
  depends_on = [ helm_release.mach5-cache-proxy ]
  provider   = helm.gcp
}

resource "null_resource" "download_chart" {
  provisioner "local-exec" {
    command = "aws ecr get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin 709825985650.dkr.ecr.us-east-1.amazonaws.com; helm pull oci://709825985650.dkr.ecr.us-east-1.amazonaws.com/mach5-software/mach5-io/mach5-search --version ${var.mach5_helm_chart_version} "
  }
  triggers = {
    always_run = timestamp()
  }
}

resource "helm_release" "mach5-release-ecr" {
  count = var.use_ecr ? 1 : 0

  chart      = "./mach5-search-${var.mach5_helm_chart_version}.tgz"
  name        = var.mach5_helm_release_name
  namespace   = var.namespace
  values = [
    file("${path.module}/values.yaml")
  ]
  wait = false
  depends_on = [null_resource.download_chart, helm_release.cm_ecr]
  provider   = helm.ecr
}
