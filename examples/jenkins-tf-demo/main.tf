# Minimal REAL resources for the Jenkins + Terraform demo.
# These actually deploy to AWS (they cost money — tear down with `terraform destroy`).
# Deliberately NO CloudWatch alarms, so the observability agent finds coverage gaps.
#
# Kept intentionally cheap and fast: a t3.micro EC2 instance and an S3 bucket.
# No RDS/ElastiCache (slow + costly to create for a demo).

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "obs-agent-demo"
}

# Look up the latest Amazon Linux 2023 AMI so we don't hardcode an AMI id.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# --- Compute: a tiny EC2 instance, no alarms (EC2 tier / A1) ---
resource "aws_instance" "web" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"
  tags = {
    Name = "${var.name_prefix}-web"
    env  = "dev"
  }
}

# --- Storage: an S3 bucket, no alarms (S3 tier / F1) ---
resource "aws_s3_bucket" "assets" {
  bucket_prefix = "${var.name_prefix}-assets-"
  force_destroy = true   # lets `terraform destroy` remove it even if objects exist
  tags = {
    Name = "${var.name_prefix}-assets"
    env  = "dev"
  }
}

output "instance_id" {
  value = aws_instance.web.id
}

output "bucket_name" {
  value = aws_s3_bucket.assets.bucket
}
