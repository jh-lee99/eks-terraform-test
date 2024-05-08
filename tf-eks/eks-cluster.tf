module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns = {
      preserve    = true
      most_recent = true

      timeouts = {
        create = "25m"
        delete = "10m"
      }
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  create_kms_key = false
  cluster_encryption_config = {
    resources        = ["secrets"]
    provider_key_arn = module.kms.key_arn
  }

  # manage_aws_auth_configmap = true

  # aws_auth_roles = [
  #   # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
  #   {
  #     rolearn  = module.karpenter.iam_role_arn
  #     username = "system:node:{{EC2PrivateDNSName}}"
  #     groups = [
  #       "system:bootstrappers",
  #       "system:nodes",
  #     ]
  #   },
  # ]
  iam_role_additional_policies = {
    additional = aws_iam_policy.additional.arn
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

    iam_role_additional_policies = {
      additional = aws_iam_policy.additional.arn
    }

    ebs_optimized = true
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size = 100
          volume_type = "gp3"
          iops        = 3000
          throughput  = 150
          # encrypted             = true
          # kms_key_id            = aws_kms_key.ebs.arn
          delete_on_termination = true
        }
      }
    }
    tags = local.tags
  }

  eks_managed_node_groups = {
    base = {
      name            = "karpenter"
      use_name_prefix = false

      instance_types = ["t3.large", "t3a.large", "m6i.large"]
      capacity_type  = "SPOT"

      min_size     = 1
      max_size     = 2
      desired_size = 1

      subnet_ids = module.vpc.private_subnets
    }
  }

  enable_cluster_creator_admin_permissions = true

  access_entries = {
    # One access entry with a policy associated
    example = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::123456789012:role/something"

      policy_associations = {
        example = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
          access_scope = {
            namespaces = ["default"]
            type       = "namespace"
          }
        }
      }
    }
  }

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  })

}
