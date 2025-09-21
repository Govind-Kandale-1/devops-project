variable "primary_region" {
  default = "us-east-1"
}

variable "replica_region" {
  default = "us-west-2"
}

variable "bucket_name" {
  default = "your-terraform-state-bucket"  # Replace with unique bucket name
}

variable "dynamodb_table_name" {
  default = "terraform-lock-table"
}