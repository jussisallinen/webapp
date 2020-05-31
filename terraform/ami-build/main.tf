# Force minimum Terraform version as we implement variable syntax used in >0.12.
terraform {
  required_version = ">= 0.12.0"
}

# Configure the AWS Provider
provider "aws" {
  version    = "~> 2.0"
  region     = var.region
  # We read keys from Env - export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
  #  access_key = var.access_key
  #  secret_key = var.secret_key
}

module "vpc" {
  version = "~> 2.0"
  source  = "terraform-aws-modules/vpc/aws"

  name = "builder"
  cidr = "10.0.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]

  enable_nat_gateway = true
  one_nat_gateway_per_az = true
  single_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Terraform = "true"
    Environment = "Build"
  }

  vpc_tags = {
    Name = "builder"
  }
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "builder" {
  name        = "builder"
  description = "Security Group for Packer SSH"
  vpc_id      = module.vpc.vpc_id

  # SSH access from our Ansible and Terraform host
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_from]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "auth" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}
