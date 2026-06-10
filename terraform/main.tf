terraform {
  backend "s3" {
    key     = "gitlabeks48data/terraform.tfstate"
    encrypt = true
    # bucket and region passed via -backend-config at init time
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {}

variable "container_image" {
  description = "Full image URI (registry/name:tag)"
  default     = "placeholder"
}

variable "app_port" {
  type    = number
  default = 3000
}

variable "replica_count" {
  type    = number
  default = 2
}

variable "node_instance_type" {
  # t3.small (2 GiB) fits the EKS system pods + app comfortably. NOTE: it is NOT
  # Free Tier-eligible — on Free-plan-restricted AWS accounts, override
  # node_instance_type to t3.micro.
  default = "t3.small"
}

variable "min_nodes" {
  type    = number
  default = 1
}

variable "max_nodes" {
  type    = number
  default = 3
}

variable "health_check_path" {
  default = "/"
}

# ── Optional secrets passed to kubectl apply as env vars ─────────────────────
variable "database_url" {
  type      = string
  default   = ""
  sensitive = true
}

variable "db_host" {
  type    = string
  default = ""
}

variable "db_port" {
  type    = string
  default = ""
}

variable "db_name" {
  type    = string
  default = ""
}

variable "db_username" {
  type    = string
  default = ""
}

variable "db_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "mongo_uri" {
  type      = string
  default   = ""
  sensitive = true
}

variable "redis_url" {
  type      = string
  default   = ""
  sensitive = true
}

variable "secret_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "jwt_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "spring_datasource_url" {
  type      = string
  default   = ""
  sensitive = true
}

variable "spring_datasource_user" {
  type    = string
  default = ""
}

variable "spring_datasource_pass" {
  type      = string
  default   = ""
  sensitive = true
}

variable "spring_mongodb_uri" {
  type      = string
  default   = ""
  sensitive = true
}


locals {
  name_safe = trimsuffix(substr(lower(replace(replace(var.project_name, "_", "-"), " ", "-")), 0, 24), "-")
  ecr_name  = lower(replace(replace(var.project_name, "_", "-"), " ", "-"))
  namespace = local.name_safe

  _ext_port    = var.db_port != "" ? var.db_port : "5432"
  _ext_scheme  = "postgresql+asyncpg"
  _auto_db_url = var.db_host != "" ? "${local._ext_scheme}://${var.db_username}:${var.db_password}@${var.db_host}:${local._ext_port}/${var.db_name}" : ""
  _db_url      = var.database_url != "" ? var.database_url : local._auto_db_url
  _db_host     = var.db_host
  _db_port     = local._ext_port
  _db_name     = var.db_name
  _db_user     = var.db_username
  _db_password = var.db_password
  _spring_ds_url  = var.spring_datasource_url
  _spring_ds_user = var.spring_datasource_user
  _spring_ds_pass = var.spring_datasource_pass

  _all_env = {
    PORT                        = tostring(var.app_port)
    APP_ENV                     = "production"
    DATABASE_URL                = local._db_url
    DB_HOST                     = local._db_host
    DB_PORT                     = local._db_port
    DB_NAME                     = local._db_name
    DB_USER                     = local._db_user
    DB_PASSWORD                 = local._db_password
    MONGO_URI                   = var.mongo_uri
    REDIS_URL                   = var.redis_url
    SECRET_KEY                  = var.secret_key
    JWT_SECRET                  = var.jwt_secret
    SPRING_DATASOURCE_URL       = local._spring_ds_url
    SPRING_DATASOURCE_USERNAME  = local._spring_ds_user
    SPRING_DATASOURCE_PASSWORD  = local._spring_ds_pass
    SPRING_DATA_MONGODB_URI     = var.spring_mongodb_uri
  }
  app_env = { for k, v in local._all_env : k => v if v != "" }
}

# ── VPC ────────────────────────────────────────────────────────────────────────
data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_safe}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # Free-tier default: NO NAT gateway. Nodes run in the PUBLIC subnets with
  # auto-assigned public IPs, so they reach the EKS control plane and ECR
  # directly — zero Elastic IPs consumed, no NAT hourly cost. This avoids the
  # AddressLimitExceeded EIP failure (and the downstream NodeCreationFailure it
  # causes) on accounts at their EIP quota. To switch to private nodes + NAT,
  # ask to "use a NAT gateway".
  enable_nat_gateway      = false
  map_public_ip_on_launch = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# ── EKS Cluster ────────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${local.name_safe}-eks"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  # Free-tier default places nodes in public subnets (no NAT needed); the NAT
  # path keeps them private. RDS always stays in private_subnets either way.
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true

  # Skip the customer-managed KMS key the module otherwise creates for secret
  # envelope encryption. Creating + tagging that CMK needs broad KMS admin
  # rights (kms:CreateKey, kms:TagResource, kms:CreateAlias, …) that a typical
  # deploy IAM user lacks — and it was the hard blocker on first-time EKS runs.
  # EKS secrets are still encrypted at rest with the AWS-managed key; this only
  # drops the extra CMK envelope layer. To re-enable: grant the KMS actions and
  # set create_kms_key = true with cluster_encryption_config = { resources = ["secrets"] }.
  create_kms_key            = false
  cluster_encryption_config = {}

  eks_managed_node_groups = {
    default = {
      name           = "${local.name_safe}-ng"
      instance_types = [var.node_instance_type]
      min_size       = var.min_nodes
      max_size       = var.max_nodes
      desired_size   = var.replica_count

      labels = {
        project = var.project_name
      }
    }
  }

  enable_cluster_creator_admin_permissions = true
}

# ── ECR ────────────────────────────────────────────────────────────────────────
data "aws_ecr_repository" "app" {
  depends_on = [module.eks]
  name       = local.ecr_name
}



# ── Outputs ────────────────────────────────────────────────────────────────────
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "namespace" {
  value = local.namespace
}

output "ecr_repository_url" {
  value = data.aws_ecr_repository.app.repository_url
}

output "app_env_json" {
  value     = jsonencode(local.app_env)
  sensitive = true
}
