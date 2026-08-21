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
  # ECR
  # ----------------------------------------------------------

  ecr_repo_name = "myapp"

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


  # ----------------------------------------------------------
  # RDS
  # ----------------------------------------------------------

  db_name           = "appdb"
  db_username       = "appadmin"
  db_instance_class = "db.t3.micro"
  db_engine_version = "8.0"

}
# ============================================================
# CURRENT AWS ACCOUNT
# ============================================================

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
# ECR REPOSITORY
# ============================================================

resource "aws_ecr_repository" "app" {

  name = local.ecr_repo_name

  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {

    scan_on_push = true
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-ecr-repo"
    }
  )
}


# ============================================================
# ECR LIFECYCLE POLICY - AUTO-EXPIRE OLD IMAGES
# ============================================================

resource "aws_ecr_lifecycle_policy" "app" {

  repository = aws_ecr_repository.app.name

  policy = jsonencode({

    rules = [
      {
        rulePriority = 1

        description = "Expire untagged images older than 7 days"

        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }

        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2

        description = "Keep only the last 15 tagged images"

        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 15
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
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

resource "time_sleep" "wait_for_access_entry" {

  depends_on = [
    aws_eks_access_policy_association.current_user_admin
  ]

  create_duration = "30s"
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

          env {
            name = "DB_HOST"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "DB_HOST"
              }
            }
          }

          env {
            name = "DB_PORT"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "DB_PORT"
              }
            }
          }

          env {
            name = "DB_NAME"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "DB_NAME"
              }
            }
          }

          env {
            name = "DB_USER"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "DB_USER"
              }
            }
          }

          env {
            name = "DB_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "DB_PASSWORD"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    aws_eks_node_group.nodes,
    time_sleep.wait_for_access_entry,
    kubernetes_secret.db_credentials
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

    type = "ClusterIP"

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

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks_oidc" {

  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = local.tags
}


# ============================================================
# ALB CONTROLLER - IAM POLICY
# ============================================================

resource "aws_iam_policy" "alb_controller" {

  name = "${local.cluster_name}-alb-controller-policy"

  policy = file("${path.module}/iam_policy_alb_controller.json")
}


# ============================================================
# ALB CONTROLLER - IRSA ROLE
# ============================================================

resource "aws_iam_role" "alb_controller" {

  name = "${local.cluster_name}-alb-controller-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_oidc.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks_oidc.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"

            "${replace(aws_iam_openid_connect_provider.eks_oidc.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {

  role = aws_iam_role.alb_controller.name

  policy_arn = aws_iam_policy.alb_controller.arn
}


# ============================================================
# ALB CONTROLLER - SERVICE ACCOUNT + HELM INSTALL
# ============================================================

resource "kubernetes_service_account" "alb_controller" {

  metadata {

    name      = "aws-load-balancer-controller"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }

    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.alb_controller,
    time_sleep.wait_for_access_entry
  ]
}

resource "helm_release" "alb_controller" {

  name = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"

  chart = "aws-load-balancer-controller"

  namespace = "kube-system"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.eks.name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "region"
    value = local.aws_region
  }

  set {
    name  = "vpcId"
    value = aws_vpc.eks_vpc.id
  }

  depends_on = [
    kubernetes_service_account.alb_controller,
    aws_eks_addon.vpc_cni
  ]
}


# ============================================================
# INGRESS
# ============================================================

resource "kubernetes_ingress_v1" "app" {

  metadata {

    name = "test-public-ingress"

    annotations = {
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
    }
  }

  spec {

    ingress_class_name = "alb"

    rule {

      http {

        path {

          path      = "/"
          path_type = "Prefix"

          backend {

            service {

              name = kubernetes_service.app.metadata[0].name

              port {
                number = local.service_port
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.alb_controller
  ]
}

# ============================================================
# RDS - DB SUBNET GROUP (PRIVATE SUBNETS ONLY)
# ============================================================

resource "aws_db_subnet_group" "mysql" {

  name = "${local.cluster_name}-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-db-subnet-group"
    }
  )
}


# ============================================================
# RDS - SECURITY GROUP
# ============================================================
# Only allows MySQL traffic (3306) from the EKS cluster's
# security group - not from the whole VPC.

resource "aws_security_group" "mysql" {

  name        = "${local.cluster_name}-mysql-sg"
  description = "Allow MySQL access from EKS cluster only"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {

    description     = "MySQL from EKS cluster"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id]
  }

  egress {

    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-mysql-sg"
    }
  )
}


# ============================================================
# RDS - RANDOM PASSWORD
# ============================================================
# Generated once, stored only in Terraform state and the
# Kubernetes Secret below - never hardcoded in any file.

resource "random_password" "db_password" {

  length  = 20
  special = false # avoids characters that need escaping in connection strings
}


# ============================================================
# RDS - MYSQL INSTANCE (MULTI-AZ FOR HA)
# ============================================================

resource "aws_db_instance" "mysql" {

  identifier = "${local.cluster_name}-mysql"

  engine         = "mysql"
  engine_version = local.db_engine_version

  instance_class    = local.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = local.db_name
  username = local.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.mysql.id]

  # HA: standby replica in a second AZ, automatic failover
  multi_az = true

  # Private subnets only - never internet-reachable
  publicly_accessible = false

  backup_retention_period = 7
  skip_final_snapshot     = true # fine for dev/test; set false + add final_snapshot_identifier for prod

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-mysql"
    }
  )
}


# ============================================================
# KUBERNETES SECRET - DB CREDENTIALS
# ============================================================
# Keeps DB credentials out of the Deployment spec itself;
# the pod pulls them at runtime via secretKeyRef.

resource "kubernetes_secret" "db_credentials" {

  metadata {

    name = "db-credentials"
  }

  data = {
    DB_HOST     = aws_db_instance.mysql.address
    DB_PORT     = tostring(aws_db_instance.mysql.port)
    DB_NAME     = local.db_name
    DB_USER     = local.db_username
    DB_PASSWORD = random_password.db_password.result
  }

  type = "Opaque"

  depends_on = [
    time_sleep.wait_for_access_entry
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


output "ecr_repository_url" {

  value = aws_ecr_repository.app.repository_url
}


output "ingress_hostname" {

  value = try(
    kubernetes_ingress_v1.app.status[0].load_balancer[0].ingress[0].hostname,
    "ALB is still being provisioned"
  )
}
output "rds_endpoint" {

  value = aws_db_instance.mysql.address
}