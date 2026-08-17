terraform {
  required_version = ">=1.7"

  backend "s3" {
    bucket = "vimala-testing-demo-storage"
    key = "state-files/eks.tfstate"
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

  }
}

provider "aws" {
  region = "ap-south-1"
}

provider "kubernetes" {
  host = aws_eks_cluster.eks.endpoint

  cluster_ca_certificate = base64decode(
    aws_eks_cluster.eks.certificate_authority[0].data
  )

  token = data.aws_eks_cluster_auth.eks.token
}

