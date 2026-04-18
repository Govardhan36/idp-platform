# terraform/modules/eks/variables.tf
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment: dev, staging, or prod"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where worker nodes will run"
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "desired_node_count" {
  description = "Number of worker nodes to start with"
  type        = number
  default     = 2
}

variable "min_node_count" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 5
}
