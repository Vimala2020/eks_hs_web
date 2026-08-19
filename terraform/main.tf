
locals {

  aws_region = "ap-south-1"

  # ----------------------------------------------------------
  # VPC
  # ----------------------------------------------------------

  vpc_cidr = "10.1.0.0/16"

  # ----------------------------------------------------------
  # Availability Zones
  # ----------------------------------------------------------

  az_a = "ap-south-1a"
  az_b = "ap-south-1b"

  # ----------------------------------------------------------
  # Public Subnets
  # ----------------------------------------------------------

  public_subnet_a_cidr = "10.1.1.0/24"
  public_subnet_b_cidr = "10.1.2.0/24"

  # ----------------------------------------------------------
  # Private Subnets
  # ----------------------------------------------------------

  private_subnet_a_cidr = "10.1.101.0/24"
  private_subnet_b_cidr = "10.1.102.0/24"

  # ----------------------------------------------------------
  # EKS
  # ----------------------------------------------------------

  cluster_name = "my-eks-cluster-v1"

  # ----------------------------------------------------------
  # Node Group
  # ----------------------------------------------------------

  node_group_name = "my-node-group-v1"

  instance_type = "t3.small"

  desired_nodes = 2
  min_nodes     = 1
  max_nodes     = 3

  # ----------------------------------------------------------
  # Public ECR image
  # ----------------------------------------------------------

  ecr_image = "public.ecr.aws/v7m8e2b0/test-public:latest"

  # ----------------------------------------------------------
  # Application
  # ----------------------------------------------------------

  container_port = 8080

  service_port = 80

  # ----------------------------------------------------------
  # Tags
  # ----------------------------------------------------------

  tags = {
    Project     = "EKS-Test"
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}


# ============================================================
# CURRENT AWS ACCOUNT
# ============================================================

data "aws_iam_user" "user" {
  user_name = "vimala"
}

data "aws_iam_role" "github_role" {
  name = "AWS_ROLE_TO_ASSUME"
}

# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "eks_vpc" {

  cidr_block = local.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-vpc"
    }
  )
}


# ============================================================
# INTERNET GATEWAY
# ============================================================

resource "aws_internet_gateway" "igw" {

  vpc_id = aws_vpc.eks_vpc.id

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-igw"
    }
  )
}


# ============================================================
# PUBLIC SUBNET - AZ A
# ============================================================

resource "aws_subnet" "public_a" {

  vpc_id = aws_vpc.eks_vpc.id

  cidr_block = local.public_subnet_a_cidr

  availability_zone = local.az_a

  map_public_ip_on_launch = true

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-public-a"

      # Required/useful for AWS load balancers
      "kubernetes.io/role/elb" = "1"
    }
  )
}


# ============================================================
# PUBLIC SUBNET - AZ B
# ============================================================

resource "aws_subnet" "public_b" {

  vpc_id = aws_vpc.eks_vpc.id

  cidr_block = local.public_subnet_b_cidr

  availability_zone = local.az_b

  map_public_ip_on_launch = true

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-public-b"

      "kubernetes.io/role/elb" = "1"
    }
  )
}


# ============================================================
# PRIVATE SUBNET - AZ A
# ============================================================

resource "aws_subnet" "private_a" {

  vpc_id = aws_vpc.eks_vpc.id

  cidr_block = local.private_subnet_a_cidr

  availability_zone = local.az_a

  map_public_ip_on_launch = false

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-private-a"

      # Useful for internal AWS load balancers
      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}


# ============================================================
# PRIVATE SUBNET - AZ B
# ============================================================

resource "aws_subnet" "private_b" {

  vpc_id = aws_vpc.eks_vpc.id

  cidr_block = local.private_subnet_b_cidr

  availability_zone = local.az_b

  map_public_ip_on_launch = false

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-private-b"

      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}


# ============================================================
# PUBLIC ROUTE TABLE
# ============================================================

resource "aws_route_table" "public" {

  vpc_id = aws_vpc.eks_vpc.id

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-public-rt"
    }
  )
}


# ============================================================
# PUBLIC ROUTE -> INTERNET GATEWAY
# ============================================================

resource "aws_route" "public_internet" {

  route_table_id = aws_route_table.public.id

  destination_cidr_block = "0.0.0.0/0"

  gateway_id = aws_internet_gateway.igw.id
}


# ============================================================
# PUBLIC SUBNET A -> PUBLIC ROUTE TABLE
# ============================================================

resource "aws_route_table_association" "public_a" {

  subnet_id = aws_subnet.public_a.id

  route_table_id = aws_route_table.public.id
}


# ============================================================
# PUBLIC SUBNET B -> PUBLIC ROUTE TABLE
# ============================================================

resource "aws_route_table_association" "public_b" {

  subnet_id = aws_subnet.public_b.id

  route_table_id = aws_route_table.public.id
}


# ============================================================
# ELASTIC IP - NAT GATEWAY A
# ============================================================

resource "aws_eip" "nat_a" {

  domain = "vpc"

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-nat-eip-a"
    }
  )

  depends_on = [
    aws_internet_gateway.igw
  ]
}


# ============================================================
# ELASTIC IP - NAT GATEWAY B
# ============================================================

resource "aws_eip" "nat_b" {

  domain = "vpc"

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-nat-eip-b"
    }
  )

  depends_on = [
    aws_internet_gateway.igw
  ]
}


# ============================================================
# NAT GATEWAY - AZ A
# ============================================================

resource "aws_nat_gateway" "nat_a" {

  allocation_id = aws_eip.nat_a.id

  subnet_id = aws_subnet.public_a.id

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-nat-a"
    }
  )

  depends_on = [
    aws_internet_gateway.igw
  ]
}


# ============================================================
# NAT GATEWAY - AZ B
# ============================================================

resource "aws_nat_gateway" "nat_b" {

  allocation_id = aws_eip.nat_b.id

  subnet_id = aws_subnet.public_b.id

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-nat-b"
    }
  )

  depends_on = [
    aws_internet_gateway.igw
  ]
}


# ============================================================
# PRIVATE ROUTE TABLE - AZ A
# ============================================================

resource "aws_route_table" "private_a" {

  vpc_id = aws_vpc.eks_vpc.id

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-private-rt-a"
    }
  )
}


# ============================================================
# PRIVATE ROUTE TABLE - AZ B
# ============================================================

resource "aws_route_table" "private_b" {

  vpc_id = aws_vpc.eks_vpc.id

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-private-rt-b"
    }
  )
}


# ============================================================
# PRIVATE ROUTE A -> NAT A
# ============================================================

resource "aws_route" "private_a_nat" {

  route_table_id = aws_route_table.private_a.id

  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id = aws_nat_gateway.nat_a.id
}


# ============================================================
# PRIVATE ROUTE B -> NAT B
# ============================================================

resource "aws_route" "private_b_nat" {

  route_table_id = aws_route_table.private_b.id

  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id = aws_nat_gateway.nat_b.id
}


# ============================================================
# PRIVATE SUBNET A -> PRIVATE ROUTE TABLE A
# ============================================================

resource "aws_route_table_association" "private_a" {

  subnet_id = aws_subnet.private_a.id

  route_table_id = aws_route_table.private_a.id
}


# ============================================================
# PRIVATE SUBNET B -> PRIVATE ROUTE TABLE B
# ============================================================

resource "aws_route_table_association" "private_b" {

  subnet_id = aws_subnet.private_b.id

  route_table_id = aws_route_table.private_b.id
}


# ============================================================
# EKS CLUSTER IAM ROLE
# ============================================================

resource "aws_iam_role" "eks_cluster_role" {

  name = "${local.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}


resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {

  role = aws_iam_role.eks_cluster_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ============================================================
# EKS CLUSTER
# ============================================================

resource "aws_eks_cluster" "eks" {

  name = local.cluster_name

  role_arn = aws_iam_role.eks_cluster_role.arn

  version = "1.33"

  access_config {

    authentication_mode = "API_AND_CONFIG_MAP"
  }

  vpc_config {

    # EKS control plane uses private subnets
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id
    ]

    endpoint_public_access  = true
    endpoint_private_access = true
  }

  tags = local.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,

    aws_route.private_a_nat,
    aws_route.private_b_nat
  ]
}


# ============================================================
# EKS ACCESS ENTRY
# ============================================================

resource "aws_eks_access_entry" "current_user" {

  cluster_name = aws_eks_cluster.eks.name

  principal_arn = data.aws_iam_role.github_role.arn

  type = "STANDARD"
}


# ============================================================
# EKS ADMIN ACCESS
# ============================================================

resource "aws_eks_access_policy_association" "current_user_admin" {

  cluster_name = aws_eks_cluster.eks.name

  principal_arn = data.aws_iam_role.github_role.arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {

    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.current_user
  ]
}


# ============================================================
# EKS NODE IAM ROLE
# ============================================================

resource "aws_iam_role" "eks_node_role" {

  name = "${local.cluster_name}-node-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}


# ============================================================
# NODE WORKER POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "node_worker_policy" {

  role = aws_iam_role.eks_node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}


# ============================================================
# NODE CNI POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "node_cni_policy" {

  role = aws_iam_role.eks_node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


# ============================================================
# ECR PULL POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {

  role = aws_iam_role.eks_node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}


# ============================================================
# EKS MANAGED NODE GROUP
# ============================================================

resource "aws_eks_node_group" "nodes" {

  cluster_name = aws_eks_cluster.eks.name

  node_group_name = local.node_group_name

  node_role_arn = aws_iam_role.eks_node_role.arn

  # Worker nodes go into PRIVATE subnets
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  instance_types = [
    local.instance_type
  ]

  capacity_type = "ON_DEMAND"

  scaling_config {

    desired_size = local.desired_nodes

    min_size = local.min_nodes

    max_size = local.max_nodes
  }

  update_config {

    max_unavailable = 1
  }

  tags = local.tags

  depends_on = [

    aws_iam_role_policy_attachment.node_worker_policy,

    aws_iam_role_policy_attachment.node_cni_policy,

    aws_iam_role_policy_attachment.node_ecr_policy
  ]
}


# ============================================================
# EKS VPC CNI ADD-ON
# ============================================================

resource "aws_eks_addon" "vpc_cni" {

  cluster_name = aws_eks_cluster.eks.name

  addon_name = "vpc-cni"

  resolve_conflicts_on_create = "OVERWRITE"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.nodes
  ]
}


# ============================================================
# EKS KUBE-PROXY ADD-ON
# ============================================================

resource "aws_eks_addon" "kube_proxy" {

  cluster_name = aws_eks_cluster.eks.name

  addon_name = "kube-proxy"

  resolve_conflicts_on_create = "OVERWRITE"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.nodes
  ]
}


# ============================================================
# EKS COREDNS ADD-ON
# ============================================================

resource "aws_eks_addon" "coredns" {

  cluster_name = aws_eks_cluster.eks.name

  addon_name = "coredns"

  resolve_conflicts_on_create = "OVERWRITE"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.nodes
  ]
}


# ============================================================
# EKS AUTHENTICATION
# ============================================================

data "aws_eks_cluster_auth" "eks" {

  name = aws_eks_cluster.eks.name

  depends_on = [
    aws_eks_cluster.eks
  ]
}


# ============================================================
# KUBERNETES DEPLOYMENT
# ============================================================

resource "kubernetes_deployment" "app" {

  metadata {

    name = "test-public"

    labels = {
      app = "test-public"
    }
  }

  spec {

    replicas = 2

    selector {

      match_labels = {
        app = "test-public"
      }
    }

    template {

      metadata {

        labels = {
          app = "test-public"
        }
      }

      spec {

        container {

          name = "test-public"

          image = local.ecr_image

          image_pull_policy = "Always"

          port {

            container_port = local.container_port
          }
        }
      }
    }
  }

  depends_on = [
    aws_eks_node_group.nodes,
    aws_eks_access_policy_association.current_user_admin
  ]
}


# ============================================================
# KUBERNETES SERVICE
# ============================================================

resource "kubernetes_service" "app" {

  metadata {

    name = "test-public"

    labels = {
      app = "test-public"
    }
  }

  spec {

    type = "LoadBalancer"

    selector = {
      app = "test-public"
    }

    port {

      port = local.service_port

      target_port = local.container_port

      protocol = "TCP"
    }
  }

  depends_on = [
    kubernetes_deployment.app
  ]
}


# ============================================================
# OUTPUTS
# ============================================================

output "vpc_id" {

  value = aws_vpc.eks_vpc.id
}


output "vpc_cidr" {

  value = aws_vpc.eks_vpc.cidr_block
}


output "public_subnet_a" {

  value = aws_subnet.public_a.id
}


output "public_subnet_b" {

  value = aws_subnet.public_b.id
}


output "private_subnet_a" {

  value = aws_subnet.private_a.id
}


output "private_subnet_b" {

  value = aws_subnet.private_b.id
}


output "eks_cluster_name" {

  value = aws_eks_cluster.eks.name
}


output "eks_cluster_endpoint" {

  value = aws_eks_cluster.eks.endpoint
}


output "eks_cluster_version" {

  value = aws_eks_cluster.eks.version
}


output "ecr_image" {

  value = local.ecr_image
}


output "load_balancer_hostname" {

  value = try(
    kubernetes_service.app.status[0].load_balancer[0].ingress[0].hostname,
    "Load Balancer is still being created"
  )
}
