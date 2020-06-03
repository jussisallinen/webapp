# Force minimum Terraform version as we implement variable syntax used in >0.12.
terraform {
  required_version = ">= 0.12.0"
}

# Configure the AWS Provider
provider "aws" {
  version = "~> 2.0"
  region  = var.region
  # We read keys from Env - export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
  #  access_key = var.access_key
  #  secret_key = var.secret_key
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.0"

  name = "webapp"
  cidr = "10.0.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
  single_nat_gateway     = false
  enable_vpn_gateway     = false

  tags = {
    Terraform   = "true"
    Environment = "Production"
  }

  vpc_tags = {
    Name = "webapp"
  }
}

data "aws_ami" "webapp-ami" {
  most_recent = true
  owners      = ["self"]
  tags = {
    Name = "packer-webapp"
  }
}

# A security group for the ALB so it is accessible from the Internet.
resource "aws_security_group" "webapp-alb-sg" {
  name        = "webapp_alb"
  description = "Security Group for webapp Application LB"
  vpc_id      = module.vpc.vpc_id

  # Inbound HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "webapp-backend-sg" {
  name        = "webapp_backend_sg"
  description = "Allow webapp backend traffic"
  vpc_id      = module.vpc.vpc_id

  # SSH access from bastion
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = flatten([module.vpc.public_subnets_cidr_blocks])
  }

  # HTTPS access from ALB
  ingress {
    from_port   = 443
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = flatten([module.vpc.public_subnets_cidr_blocks])
  }

  # Outbound Internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "webapp_bastion_sg" {
  name        = "webapp_bastion_sg"
  description = "Allow SSH traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = flatten([var.bastion_ssh_from, module.vpc.public_subnets_cidr_blocks])
  }

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = flatten([module.vpc.private_subnets_cidr_blocks])
  }

  tags = {
    Name = "webapp_bastion_sg"
  }
}

resource "aws_acm_certificate" "default" {
  domain_name       = var.cert_fqdn
  validation_method = "DNS"
}

data "aws_route53_zone" "external" {
  name = var.route53_zone
}

resource "aws_route53_record" "validation" {
  name    = aws_acm_certificate.default.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.default.domain_validation_options.0.resource_record_type
  zone_id = data.aws_route53_zone.external.zone_id
  records = [aws_acm_certificate.default.domain_validation_options.0.resource_record_value]
  ttl     = "60"
}

resource "aws_acm_certificate_validation" "default" {
  certificate_arn = aws_acm_certificate.default.arn

  validation_record_fqdns = [
    aws_route53_record.validation.fqdn,
  ]
}

resource "aws_alb" "webapp" {
  name               = "webapp"
  subnets            = flatten([module.vpc.public_subnets])
  security_groups    = [aws_security_group.webapp-alb-sg.id]
  internal           = false
  load_balancer_type = "application"
  idle_timeout       = 60
  tags = {
    Name = "webapp-alb"
  }
}

resource "aws_alb" "bastion" {
  name               = "bastion"
  subnets            = flatten([module.vpc.public_subnets])
  internal           = false
  load_balancer_type = "network"
  idle_timeout       = 300
  tags = {
    Name = "bastion-alb"
  }
}

resource "aws_alb_target_group" "webapp_alb_target_group" {
  name     = "webapp-alb-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}

resource "aws_alb_target_group" "webapp_bastion_alb_target_group" {
  name     = "webapp-bastion-alb-target-group"
  port     = 22
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    protocol = "TCP"
  }
}

resource "aws_alb_listener" "webapp_alb_http_listener" {
  load_balancer_arn = aws_alb.webapp.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
    target_group_arn = aws_alb_target_group.webapp_alb_target_group.id
  }
}

resource "aws_alb_listener" "webapp_alb_https_listener" {
  load_balancer_arn = aws_alb.webapp.id
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.default.id

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.webapp_alb_target_group.id
  }
}

resource "aws_alb_listener" "webapp_bastion_alb_listener" {
  load_balancer_arn = aws_alb.bastion.id
  port              = "22"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.webapp_bastion_alb_target_group.id
  }
}

resource "aws_route53_record" "webapp" {
  zone_id = data.aws_route53_zone.external.zone_id
  name    = "webapp"
  type    = "A"

  alias {
    name                   = aws_alb.webapp.dns_name
    zone_id                = aws_alb.webapp.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "sshjump_webapp" {
  zone_id = data.aws_route53_zone.external.zone_id
  name    = "sshjump.webapp"
  type    = "A"

  alias {
    name                   = aws_alb.bastion.dns_name
    zone_id                = aws_alb.bastion.zone_id
    evaluate_target_health = true
  }
}

resource "aws_key_pair" "auth" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

resource "aws_launch_configuration" "webapp_lc" {
  name_prefix     = "webapp-backend-lc-"
  image_id        = data.aws_ami.webapp-ami.id
  instance_type   = var.instance_size
  key_name        = aws_key_pair.auth.id
  security_groups = [aws_security_group.webapp-backend-sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "webapp-asg-eu-central-1" {
  name                 = "webapp-asg-eu-central-1"
  launch_configuration = aws_launch_configuration.webapp_lc.name
  min_size             = 3
  max_size             = 6
  vpc_zone_identifier  = flatten([module.vpc.private_subnets])
  target_group_arns    = [aws_alb_target_group.webapp_alb_target_group.id]
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "webapp_bastion_lc" {
  name_prefix                 = "webapp-bastion-lc-"
  image_id                    = lookup(var.aws_amis, var.region)
  instance_type               = var.instance_size
  key_name                    = aws_key_pair.auth.id
  security_groups             = [aws_security_group.webapp_bastion_sg.id]
  associate_public_ip_address = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "webapp-bastion-asg-eu-central-1" {
  name                 = "webapp-bastion-asg-eu-central-1"
  launch_configuration = aws_launch_configuration.webapp_bastion_lc.name
  min_size             = 3
  max_size             = 3
  vpc_zone_identifier  = flatten([module.vpc.public_subnets])
  target_group_arns    = [aws_alb_target_group.webapp_bastion_alb_target_group.id]
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_notification" "asg_notifications" {
  group_names = [
    aws_autoscaling_group.webapp-asg-eu-central-1.name,
    aws_autoscaling_group.webapp-bastion-asg-eu-central-1.name,
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = module.notify_slack.this_slack_topic_arn
}

resource "aws_kms_key" "asg-slack" {
  description = "KMS key for notify-slack"
}

resource "aws_kms_alias" "asg-slack" {
  name          = "alias/kms-slack-key"
  target_key_id = aws_kms_key.asg-slack.id
}

resource "aws_kms_ciphertext" "slack_url" {
  plaintext = var.slack_webhook_url
  key_id    = aws_kms_key.asg-slack.arn
}

# We want ASG notifications to a Slack channel.
module "notify_slack" {
  source  = "terraform-aws-modules/notify-slack/aws"
  version = "~> 2.0"

  sns_topic_name = "asg-notification-topic"

  slack_webhook_url = aws_kms_ciphertext.slack_url.ciphertext_blob
  slack_channel     = var.slack_channel
  slack_username    = var.slack_username

  kms_key_arn = aws_kms_key.asg-slack.arn

  lambda_description = "Lambda function which sends notifications to Slack"
  log_events         = true

  tags = {
    Name = "cloudwatch-alerts-to-slack"
  }
}

resource "aws_cloudwatch_metric_alarm" "LambdaDuration" {
  alarm_name          = "NotifySlackDuration"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Average"
  threshold           = "5000"
  alarm_description   = "Duration of notifying slack exceeds threshold"

  alarm_actions = [module.notify_slack.this_slack_topic_arn]

  dimensions = {
    FunctionName = module.notify_slack.notify_slack_lambda_function_name
  }
}