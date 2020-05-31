variable "key_name" {
  description = "SSH Public Key name - must be unique between VPCs"
  default = "foobar-builder"
}

variable "public_key_path" {
  description = "SSH Public Key - used for connecting to instances."
  default = "~/.ssh/foobar.id_rsa.pub"
}

variable "region" {
  default = "eu-central-1"
}

variable "aws_amis" {
  # Currently defaults to Ubuntu 18.04 LTS (x64) on eu-central-1 as we deploy there.
  default = {
    eu-central-1 = "ami-0e342d72b12109f91"
  }
}

variable "ssh_from" {
  description = "Allow SSH only from Ansible / Terraform hosts external IP"
  default = "127.0.0.1/32"
}
