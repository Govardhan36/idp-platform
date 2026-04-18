# terraform/modules/eks/main.tf
# ─────────────────────────────────────────────────────────────────
# WHAT THIS FILE DOES:
# Creates an AWS EKS (Elastic Kubernetes Service) cluster.
# EKS is a managed Kubernetes — AWS handles the control plane,
# you only manage the worker nodes.
# ─────────────────────────────────────────────────────────────────

# ── IAM ROLE FOR EKS CONTROL PLANE ─────────────────────────────
# IAM Role = permission identity for AWS services
# The EKS control plane needs permission to manage AWS resources
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"

  # assume_role_policy = WHO can use this role
  # Here: the EKS service (eks.amazonaws.com) can use it
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

# Attach AWS-managed policy to the role
# AmazonEKSClusterPolicy gives EKS permission to manage EC2, networking etc.
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# ── EKS CLUSTER ─────────────────────────────────────────────────
# This is the actual Kubernetes cluster
resource "aws_eks_cluster" "main" {
  name    = var.cluster_name
  version = var.kubernetes_version          # e.g. "1.29"
  role_arn = aws_iam_role.eks_cluster.arn   # Use the IAM role we created above

  vpc_config {
    # Place the cluster in our private subnets (more secure)
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true    # kubectl works from inside VPC
    endpoint_public_access  = true    # kubectl also works from your laptop
    # In production: set endpoint_public_access = false for maximum security
  }

  # Enable control plane logging to CloudWatch
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # depends_on = wait for IAM role before creating cluster
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]

  tags = {
    Name        = var.cluster_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ── IAM ROLE FOR WORKER NODES ────────────────────────────────────
# Worker nodes (EC2 instances) also need IAM permissions
resource "aws_iam_role" "eks_nodes" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      # ec2.amazonaws.com = EC2 instances can use this role
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Three policies worker nodes need:
# 1. AmazonEKSWorkerNodePolicy — register with cluster, manage pods
# 2. AmazonEKS_CNI_Policy — manage pod networking (IP addresses)
# 3. AmazonEC2ContainerRegistryReadOnly — pull Docker images from ECR
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# ── EKS NODE GROUP ───────────────────────────────────────────────
# Node group = pool of EC2 worker machines for running pods
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-workers"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnet_ids

  # EC2 instance type for worker nodes
  # t3.medium = 2 vCPU, 4GB RAM — good for dev
  # m5.large = 2 vCPU, 8GB RAM — better for prod
  instance_types = [var.node_instance_type]

  # scaling_config = auto-scaling settings
  scaling_config {
    desired_size = var.desired_node_count   # Start with this many nodes
    min_size     = var.min_node_count       # Never go below this
    max_size     = var.max_node_count       # Never go above this
  }

  # update_config = how many nodes can be updated simultaneously
  update_config {
    max_unavailable = 1   # Only take down 1 node at a time during updates
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]

  tags = {
    Name        = "${var.cluster_name}-workers"
    Environment = var.environment
  }
}
