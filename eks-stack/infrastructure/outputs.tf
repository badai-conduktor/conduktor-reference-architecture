output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "acm_certificate_arn" {
  value = aws_acm_certificate.wildcard.arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.monitoring.bucket
}

output "cortex_irsa_role_arn" {
  value = aws_iam_role.cortex.arn
}

output "aws_lb_controller_irsa_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "kube_context" {
  value = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${aws_eks_cluster.main.name}"
}

output "kubeconfig_command" {
  description = "Run this command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "config_env" {
  description = "Paste these values into eks-stack/config.env"
  value       = <<-EOT
    export AWS_REGION=${var.aws_region}
    export EKS_CLUSTER_NAME=${aws_eks_cluster.main.name}
    export KUBE_CONTEXT="arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${aws_eks_cluster.main.name}"
    export CONSOLE_DOMAIN=console.${var.domain}
    export GATEWAY_DOMAIN=gateway.${var.domain}
    export OIDC_DOMAIN=oidc.${var.domain}
    export ACM_CERTIFICATE_ARN=${aws_acm_certificate.wildcard.arn}
    export S3_BUCKET_NAME=${aws_s3_bucket.monitoring.bucket}
    export S3_REGION=${var.aws_region}
    export CORTEX_IRSA_ROLE_ARN=${aws_iam_role.cortex.arn}
    export VPC_ID=${aws_vpc.main.id}
    export AWS_LB_CONTROLLER_IRSA_ROLE_ARN=${aws_iam_role.alb_controller.arn}
  EOT
}
