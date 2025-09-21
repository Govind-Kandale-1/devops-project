# Backend Configuration (place this in your terraform.tf or backend.tf file)
terraform {
  backend "s3" {
    bucket         = var.bucket_name
    key            = "envs/terraform.tfstate"    # adjust path per environment
    region         = "us-east-1"                  # primary region
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
    profile        = "default"                    # optional, depends on your AWS CLI config
  }
}

# Resources for Remote Backend Setup

provider "aws" {
  region = "us-east-1"
}


# S3 Bucket for Terraform State in primary region
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bucket_name

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "TerraformStateBucket"
    Environment = "Terraform"
  }
}

# S3 Bucket Public Access Block (secure bucket)
resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "TerraformStateLockTable"
    Environment = "Terraform"
  }
}

# IAM Policy for Terraform to access S3 and DynamoDB
data "aws_iam_policy_document" "terraform_access" {
  statement {
    sid = "AllowS3Access"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn
    ]
  }

  statement {
    sid = "AllowS3ObjectAccess"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObjectAcl"
    ]
    resources = [
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]
  }

  statement {
    sid = "AllowDynamoDBAccess"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem"
    ]
    resources = [
      aws_dynamodb_table.terraform_locks.arn
    ]
  }
}

resource "aws_iam_policy" "terraform_policy" {
  name        = "TerraformS3DynamoDBAccess"
  description = "Policy to allow Terraform to use S3 bucket and DynamoDB table for state management"
  policy      = data.aws_iam_policy_document.terraform_access.json
}

# Create IAM User for Terraform CLI usage or attach to roles as needed
resource "aws_iam_user" "terraform_user" {
  name = "terraform-user"
}

resource "aws_iam_user_policy_attachment" "terraform_user_attach" {
  user       = aws_iam_user.terraform_user.name
  policy_arn = aws_iam_policy.terraform_policy.arn
}

# Access Keys for terraform_user (store securely, e.g., Secrets Manager or CI/CD secrets)
resource "aws_iam_access_key" "terraform_user_key" {
  user = aws_iam_user.terraform_user.name
}

# Cross-region replication setup
# Create S3 Bucket in replica region for replication target
provider "aws" {
  alias  = "replica"
  region = var.replica_region
}

resource "aws_s3_bucket" "terraform_state_replica" {
  provider = aws.replica

  bucket = "${var.bucket_name}-replica"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "TerraformStateBucketReplica"
    Environment = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "replica_block_public_access" {
  provider = aws.replica
  bucket   = aws_s3_bucket.terraform_state_replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for replication
resource "aws_iam_role" "replication_role" {
  name = "terraform-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "s3.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replication_role_policy" {
  name = "terraform-s3-replication-policy"
  role = aws_iam_role.replication_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ],
        Resource = [
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ],
        Resource = [
          "${aws_s3_bucket.terraform_state_replica.arn}/*"
        ]
      }
    ]
  })
}

# Enable Cross-region Replication on primary bucket
resource "aws_s3_bucket_replication_configuration" "replication" {
  bucket = aws_s3_bucket.terraform_state.id

  role = aws_iam_role.replication_role.arn

  rule {
    id     = "terraform-replication-rule"
    status = "Enabled"

    filter {
      prefix = ""
    }

    destination {
      bucket         = aws_s3_bucket.terraform_state_replica.arn
      storage_class  = "STANDARD"
    }
  }

  depends_on = [
    aws_iam_role_policy.replication_role_policy
  ]
}
