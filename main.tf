module "ec2_cluster" {
  source                 = "https://github.com/terraform-aws-modules/terraform-aws-ec2-instance"
  version                = "~> 2.0"
  name                   = "my-cluster"
  instance_count         = 5
  ami                    = "ami-ebd02392"
  instance_type          = "t2.micro"
  key_name               = "user1"
  monitoring             = true
  vpc_security_group_ids = ["abcd123"]
  subnet_id              = "abcd1234"

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
