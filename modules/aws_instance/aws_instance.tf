# Based on: https://github.com/terraformawsmodules/terraformawsec2instance/blob/master/main.tf

# Locals
# Would like to support multiple instances, but EBS volume management is a complex beast
#  with multiple hosts. #FutureImprovement
locals {
  instance_count = 1
}

# Identify AZs of all subnets referenced
data "aws_subnet" "subnet_azs" {
  count = local.instance_count
  id    = element(var.subnet_id, count.index)
}

# Build the AWS Instance
resource "aws_instance" "aws_instance" {
  count = local.instance_count

  ami                    = var.ami
  instance_type          = var.instance_type
  user_data              = var.user_data
  subnet_id              = element(var.subnet_id, count.index)
  key_name               = var.key_name == null ? null : var.key_name
  monitoring             = var.monitoring
  get_password_data      = var.get_password_data
  vpc_security_group_ids = element(var.vpc_security_group_ids, count.index)
  # If iam_instance_profile is set, use it. Else, generate below resources and use them
  iam_instance_profile = var.iam_instance_profile == "" ? aws_iam_instance_profile.iam_instance_profile[count.index].id : var.iam_instance_profile

  associate_public_ip_address = var.associate_public_ip_address
  private_ip                  = length(var.private_ips) > 0 ? element(var.private_ips, count.index) : var.private_ip
  ipv6_address_count          = var.ipv6_address_count
  ipv6_addresses              = var.ipv6_addresses

  ebs_optimized = var.ebs_optimized

  dynamic "root_block_device" {
    for_each = var.root_block_device
    content {
      delete_on_termination = lookup(root_block_device.value, "delete_on_termination", null)
      encrypted             = lookup(root_block_device.value, "encrypted", true)
      iops                  = lookup(root_block_device.value, "iops", null)
      kms_key_id            = lookup(root_block_device.value, "kms_key_id", null)
      volume_size           = lookup(root_block_device.value, "volume_size", null)
      volume_type           = lookup(root_block_device.value, "volume_type", "gp3")
    }
  }

  dynamic "ephemeral_block_device" {
    for_each = var.ephemeral_block_device
    content {
      device_name  = ephemeral_block_device.value.device_name
      no_device    = lookup(ephemeral_block_device.value, "no_device", null)
      virtual_name = lookup(ephemeral_block_device.value, "virtual_name", null)
    }
  }

  source_dest_check                    = var.source_dest_check
  disable_api_termination              = var.disable_api_termination
  instance_initiated_shutdown_behavior = var.instance_initiated_shutdown_behavior
  placement_group                      = var.placement_group
  tenancy                              = var.tenancy

  tags = merge(
    {
      "Name"           = var.name != null ? element(var.name, count.index) : format("%s%02d", var.name, count.index + 1)
      "Id"             = format("%02d", count.index + 1)
      "Terraform"      = "true",
      # An other standard tags you want each ec2 instance to have
    },
    var.tags,
  )

  volume_tags = merge(
    {
      "Name"      = var.name != null ? element(var.name, count.index) : format("%s%02d", var.name, count.index + 1),
      "Terraform" = "true"
    },
    var.volume_tags
  )

  credit_specification {
    cpu_credits = var.cpu_credits
  }

  lifecycle {
    ignore_changes = [
      user_data,
      tags["SSM Status"],
      tags["OS Type"],
      tags["OS Name"],
      tags["OS Version"],
      tags["Windows Domain"]
    ]
  }
}

# Manage the EBS volume as a separate resource
# Ref Terraform bug: https://github.com/hashicorp/terraform-provider-aws/issues/2709
# Difficult to keep for_each coordinated with count, so module only handles 1 server at a time now
resource "aws_ebs_volume" "ebs_block_device_volumes" {
  for_each             = var.ebs_block_device
  availability_zone    = data.aws_subnet.subnet_azs[0].availability_zone
  encrypted            = lookup(each.value, "encrypted", true)
  iops                 = lookup(each.value, "iops", null)
  multi_attach_enabled = lookup(each.value, "multi_attach_enabled", null)
  size                 = lookup(each.value, "volume_size", null)
  snapshot_id          = lookup(each.value, "snapshot_id", null)
  outpost_arn          = lookup(each.value, "outpost_arn", null)
  type                 = lookup(each.value, "volume_type", "gp3") #GP3 can safely be affirmed as default value since gp2 --> gp3 is seamless upgrade
  kms_key_id           = lookup(each.value, "kms_key_id", null)
}

resource "aws_volume_attachment" "ebs_attach" {
  for_each    = var.ebs_block_device
  device_name = each.key
  volume_id   = aws_ebs_volume.ebs_block_device_volumes[each.key].id
  instance_id = aws_instance.aws_instance[0].id
}

resource "aws_iam_instance_profile" "iam_instance_profile" {
  # If the IAM instance profile is set, an external IAM policy should be used, and these resources shouldn't be created
  count = var.iam_instance_profile == "" ? local.instance_count : 0
  name  = "${element(var.name, count.index)}IamInstanceProfile"
  path  = var.environment == "" ? "/" : "/${lower(var.environment)}/"
  role  = aws_iam_role.iam_role[count.index].id
}

# Default Iam Role assigned to host if a policy isn't provided in module call
resource "aws_iam_role" "iam_role" {
  # If the IAM instance profile is set, an external IAM policy should be used, and these resources shouldn't be created
  count = var.iam_instance_profile == "" ? local.instance_count : 0
  name  = "${element(var.name, count.index)}IamRole"
  path  = var.environment == "" ? "/" : "/${lower(var.environment)}/"

  assume_role_policy = var.iam_role_assume_role_policy != "" ? var.iam_role_assume_role_policy : <<POLICY
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "ec2_instance_access_policy" {
  # If the IAM instance profile is set, an external IAM policy should be used, and these resources shouldn't be created
  count  = var.iam_instance_profile == "" ? local.instance_count : 0
  name   = "${element(var.name, count.index)}InstanceAccessPolicy"
  role   = aws_iam_role.iam_role[count.index].id
  policy = var.iam_role_access_policy != "" ? var.iam_role_access_policy : <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:DescribeInstances",
        "ec2:CreateTags",
        "ec2:DescribeTags"
      ],
      "Resource": [
        "*"
      ],
      "Effect": "Allow",
      "Sid": "EC2AllowedActionsAllResources"
    }
  ]
}
POLICY
}