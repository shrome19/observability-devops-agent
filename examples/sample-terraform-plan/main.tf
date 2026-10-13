# Sample Terraform for the plan-JSON demo of the pre-deploy observability review.
# A small API tier: ALB + Lambda + RDS. Deliberately NO CloudWatch alarms.
#
# Generate the plan JSON the agent prefers (T1 runbook) with:
#   terraform init
#   terraform plan -out=tfplan
#   terraform show -json tfplan > plan.json
#
# A pre-generated sample plan.json sits next to this file (real `terraform show
# -json` output, Terraform 1.16.5) so you can demo the plan-JSON path without
# running Terraform yourself. Regenerate it with the commands above anytime.

provider "aws" {
  region = "us-east-1"
}

# --- Edge: Application Load Balancer, no alarms ---
resource "aws_lb" "api" {
  name               = "payments-api-alb"
  load_balancer_type = "application"
  subnets            = ["subnet-0aaa1111", "subnet-0bbb2222"]
  security_groups    = ["sg-0ccc3333"]
  tags = {
    Name = "payments-api-alb"
    env  = "prod"
  }
}

# --- Serverless: API handler, no alarms ---
resource "aws_lambda_function" "api" {
  function_name = "payments-api-handler"
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  timeout       = 15
  memory_size   = 256
  role          = "arn:aws:iam::123456789012:role/payments-api-role"
  filename      = "handler.zip"
  tags = {
    Name = "payments-api-handler"
    env  = "prod"
  }
}

# --- Data: RDS MySQL, no alarms ---
resource "aws_db_instance" "payments" {
  identifier                  = "payments-prod"
  engine                      = "mysql"
  engine_version              = "8.0.35"
  instance_class              = "db.r6g.large"
  allocated_storage           = 200
  db_name                     = "payments"
  username                    = "appuser"
  manage_master_user_password = true
  skip_final_snapshot         = true
  tags = {
    Name = "payments-prod"
    env  = "prod"
  }
}
