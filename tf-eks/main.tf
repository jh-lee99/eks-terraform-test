terraform {
  required_version = "~> 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # version = ">= 4.57.0"
      version = ">= 5.40.0"
    }
  }

  # backend "s3" {
  #   bucket         = "ljh-test-tfstate"
  #   key            = "ljh-test.tfstate"
  #   region         = "ap-northeast-2"
  #   #profile        = "ljh-test"
  #   profile        = "default"
  #   dynamodb_table = "ljh-TerraformStateLock"
  # }
}

provider "aws" {
  region = local.region
  # shared_config_files=["~/.aws/config"] # Or $HOME/.aws/config
  # shared_credentials_files = ["~/.aws/credentials"] # Or $HOME/.aws/credentials
  #profile        = "ljh-test"
  # profile        = "default"
}

# Error handling with "The configmap "aws-auth" does not exist"
# https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2009
# data "aws_eks_cluster" "default" {
#   name = module.eks.cluster_name
# }

data "aws_iam_role" "ljh_cloud9_test_admin" {
  name = "ljh-cloud9-test-admin"
}

data "aws_eks_cluster_auth" "default" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.default.token

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

locals {
  name            = "ljh-test"
  cluster_version = "1.28"
  region          = "ap-northeast-2"

  vpc_cidr = "10.11.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 4)

  tags = {
    env  = "test"
    owner = "ljh"
  }
}

resource "aws_iam_policy" "additional" {
  name = "${local.name}-additional"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
  
  tags = local.tags
}

module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "1.1.0"

  aliases               = ["eks/${local.name}"]
  description           = "${local.name} cluster encryption key"
  enable_default_policy = true
  key_owners            = [data.aws_caller_identity.current.arn]

  tags = local.tags
}
