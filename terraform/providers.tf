terraform {
  required_version = ">=1.7"

  backend "s3" {
    bucket = "vimala-testing-demo-storage"
    key    = "state-files/eks.tfstate"
    region = "ap-south-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
        time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

provider "kubernetes" {

  host = aws_eks_cluster.eks.endpoint

  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.aws_region]
  }
}

provider "helm" {

  kubernetes {

    host = aws_eks_cluster.eks.endpoint

    cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.aws_region]
    }
  }
}

