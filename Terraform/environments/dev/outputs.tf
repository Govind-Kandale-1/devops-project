output "eks_cluster_name" { value = module.eks.cluster_name }
output "eks_cluster_endpoint" { value = module.eks.cluster_endpoint }
output "ecr_repository_url" { value = module.eks.ecr_repository_url }
output "rds_endpoint" { value = module.rds.db_instance_endpoint }
output "vpc_id" { value = module.vpc.vpc_id }
