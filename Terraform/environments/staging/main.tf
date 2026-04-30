terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source               = "../../modules/vpc"
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  db_subnet_cidrs      = var.db_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "security_groups" {
  source      = "../../modules/security-groups"
  vpc_id      = module.vpc.vpc_id
  environment = var.environment
}

module "iam" {
  source       = "../../modules/iam"
  environment  = var.environment
  cluster_name = var.cluster_name
}

module "eks" {
  source              = "../../modules/eks"
  cluster_name        = var.cluster_name
  environment         = var.environment
  kubernetes_version  = "1.29"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  eks_role_arn        = module.iam.eks_role_arn
  node_instance_types = ["t3.large"]
  node_desired_size   = 2
  node_min_size       = 2
  node_max_size       = 5
}

module "rds" {
  source               = "../../modules/rds"
  identifier           = "${var.cluster_name}-db"
  environment          = var.environment
  db_name              = var.db_name
  db_username          = var.db_username
  db_password          = var.db_password
  db_subnet_ids        = module.vpc.db_subnet_ids
  db_security_group_id = module.security_groups.db_sg_id
  instance_class       = "db.t3.small"
  multi_az             = false
}
