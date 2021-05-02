module "ServerName" {
  source        = "./modules/aws_instance"
  ami           = "ami-123456789" #Or use a data source to select AMI
  instance_type = "t3.xlarge"
  key_name      = "ssh-key-name"
  environment   = "Int" #Used for naming, e.x. Int, Qa, Stg, Prd
  cpu_credits   = "unlimited"

  name = [
    "ServerName"
  ]

  subnet_id = [
    var.subnet_id_value
  ]

  vpc_security_group_ids = [
    [
      var.security_group1_id,
      var.security_group2_id,
    ]
  ]

  root_block_device = [
    {
      volume_type           = "gp2"
      volume_size           = 100
      delete_on_termination = false
      encrypted             = false
    }
  ]

  ebs_block_device = {
    "/dev/sdl" = {
      volume_type = "standard"
      volume_size = 50
      encrypted   = true
      kms_key_id  = var.kms_key_arn
    },
    "xvdf" = {
      volume_type = "gp2"
      volume_size = 200
      encrypted   = true
      kms_key_id  = var.kms_key_arn
    }
  }

  tags = {    
    "Extra Tag 1"        = "Tag1 Value", 
    "Extra Tag 2"        = "Tag2 Value", 
  }
}

# Associate ServerName to IamPolicyName
resource "aws_iam_role_policy_attachment" "ServerName_IamPolicyName" {
  role       = module.ServerName.aws_iam_role_name[0]
  policy_arn = "arn:aws:iam::123456789:policy/IamPolicyName"
}
