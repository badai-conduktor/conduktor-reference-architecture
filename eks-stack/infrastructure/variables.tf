variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "conduktor-eks"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes (m5.xlarge = 4 vCPU / 16 GB RAM)"
  type        = string
  default     = "m5.xlarge"
}

variable "node_desired_count" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "node_min_count" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 5
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for Cortex monitoring storage (must be globally unique)"
  type        = string
  default     = "conduktor-monitoring"
}

variable "domain" {
  description = "Base domain for Conduktor services. Use conduktor.test with /etc/hosts for local testing, or a real domain for production."
  type        = string
  default     = "conduktor.test"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
