variable "key_name" {
  description = "This needs to be unique between VPCs so we prefix it with -webapp"
  default = "foobar-webapp"
}

variable "public_key_path" {
  description = "SSH Public Key - used for connecting to instances."
  default = "~/.ssh/foobar.id_rsa.pub"
}

variable "route53_zone" {
  description = "Zone delegated to Route53 for DNS automation"
  default = "route53.jus.si"
}

variable "cert_fqdn" {
  description = "FQDN for ACM certificate."
  default = "webapp.route53.jus.si"
}

variable "region" {
  default = "eu-central-1"
}

variable "aws_amis" {
  description = "Stock Ubuntu 18.04 LTS for Bastion"
  default = {
    eu-central-1 = "ami-0e342d72b12109f91"
  }
}

variable "instance_size" {
  default = "t2.micro"
}

variable "alb_s3_bucket" {
  default = "webapp-lb-logs"
}

variable "bastion_ssh_from" {
  description = "List of allowed IPs in CIDR notation, ie. address where you connect from"
  type    = list
  default = ["127.0.0.1/32"]
}

variable "slack_webhook_url" {
  default = "https://hooks.slack.com/services/AAA/BBB/CCC"
}

variable "slack_channel" {
  default = "aws"
}

variable "slack_username" {
  default = "aws"
}