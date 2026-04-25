terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# ── Application namespace ─────────────────────────────────────────────────────

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.project
    labels = {
      name        = var.project
      environment = var.environment
    }
  }
}

# ── Karpenter ─────────────────────────────────────────────────────────────────

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  wait             = true
  timeout          = 300

  values = [yamlencode({
    settings = {
      clusterName       = var.cluster_name
      clusterEndpoint   = var.cluster_endpoint
      interruptionQueue = var.cluster_name
    }
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = var.karpenter_irsa_arn
      }
    }
    controller = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "256Mi" }
      }
    }
    tolerations = [{
      key      = "CriticalAddonsOnly"
      operator = "Exists"
    }]
  })]
}

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      amiFamily = "AL2023"
      role       = var.karpenter_node_iam_role_name
      subnetSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      securityGroupSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      tags = {
        Project     = var.project
        Environment = var.environment
        ManagedBy   = "karpenter"
      }
    }
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_node_pool_spot" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "default" }
    spec = {
      template = {
        metadata = {
          labels = { "node.${var.project}/pool" = "default" }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            { key = "karpenter.sh/capacity-type",      operator = "In", values = ["spot", "on-demand"] }
            { key = "kubernetes.io/arch",               operator = "In", values = ["amd64"] }
            { key = "node.kubernetes.io/instance-type", operator = "In", values = var.karpenter_instance_types }
          ]
        }
      }
      limits = { cpu = "200", memory = "800Gi" }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}

# ── AWS Load Balancer Controller ──────────────────────────────────────────────

resource "helm_release" "aws_lbc" {
  namespace  = "kube-system"
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_lbc_version

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.aws_lbc_irsa_arn
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  depends_on = [helm_release.karpenter]
}

# ── Metrics Server (required for HPA) ────────────────────────────────────────

resource "helm_release" "metrics_server" {
  namespace  = "kube-system"
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version
}

# ── Fluent Bit → CloudWatch Container Insights ────────────────────────────────

resource "helm_release" "fluent_bit" {
  namespace        = "amazon-cloudwatch"
  create_namespace = true
  name             = "aws-for-fluent-bit"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-for-fluent-bit"
  version          = var.fluent_bit_version

  values = [yamlencode({
    cloudWatch = {
      enabled       = true
      region        = var.aws_region
      logGroupName  = "/aws/eks/${var.cluster_name}/application"
      logStreamName = "$(kubernetes['pod_name'])"
    }
    firehose      = { enabled = false }
    kinesis       = { enabled = false }
    elasticsearch = { enabled = false }
  })]
}
