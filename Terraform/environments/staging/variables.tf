variable "aws_region" { default = "us-east-1" }
variable "environment" { default = "staging" }
variable "cluster_name" { default = "devops-staging" }
variable "vpc_cidr" { default = "10.1.0.0/16" }
variable "public_subnet_cidrs" { default = ["10.1.1.0/24", "10.1.2.0/24"] }
variable "private_subnet_cidrs" { default = ["10.1.3.0/24", "10.1.4.0/24"] }
variable "db_subnet_cidrs" { default = ["10.1.5.0/24", "10.1.6.0/24"] }
variable "availability_zones" { default = ["us-east-1a", "us-east-1b"] }
variable "db_name" { default = "appdb" }
variable "db_username" { default = "admin" }
variable "db_password" {
  description = "RDS master password — set via TF_VAR_db_password"
  sensitive   = true
}
