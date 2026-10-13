# Sample Terraform for testing the pre-deploy observability review.
# Deliberately defines resources with NO CloudWatch alarms — the exact
# "we shipped without alarm coverage" scenario the agent should catch.
#
# Prefer feeding the agent the JSON plan (more reliable than raw .tf):
#   terraform plan -out=tfplan
#   terraform show -json tfplan > plan.json
# ...then ask the agent to review plan.json. Raw .tf also works as a fallback.

provider "aws" {
  region = "us-east-1"
}

# --- Compute: a web server, no alarms ---
resource "aws_instance" "web" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t3.medium" # burstable — watch CPUCreditBalance
  tags = {
    Name = "checkout-web"
    env  = "prod"
  }
}

# --- Database: RDS Postgres, no alarms ---
# NOTE: credentials are intentionally omitted from this sample. In real IaC,
# source them from AWS Secrets Manager (manage_master_user_password = true),
# never as a literal in the template.
resource "aws_db_instance" "orders" {
  identifier                  = "orders-prod"
  engine                      = "postgres"
  engine_version              = "15.4"
  instance_class              = "db.t3.medium"
  allocated_storage           = 100
  db_name                     = "orders"
  username                    = "appuser"
  manage_master_user_password = true
  skip_final_snapshot         = true
  tags = {
    Name = "orders-prod"
    env  = "prod"
  }
}

# --- Cache: ElastiCache Redis, single node (no HA), no alarms ---
resource "aws_elasticache_cluster" "sessions" {
  cluster_id      = "sessions-prod"
  engine          = "redis"
  node_type       = "cache.t3.small"
  num_cache_nodes = 1
  tags = {
    env = "prod"
  }
}
