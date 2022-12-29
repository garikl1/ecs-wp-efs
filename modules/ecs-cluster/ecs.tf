##################################################################################
# PROVIDER CONFIGURATION
##################################################################################

terraform {
  required_version = ">= 0.12"
}

##################################################################################
# DATA The data source type
##################################################################################

data "aws_ami" "ecs" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami-*-amazon-ecs-optimized"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["591542846629"] # AWS
}

data "template_file" "ecs_init" {
  template = "${file("${path.module}/templates/ecs_init")}"
  vars = {
    cluster_name = var.cluster_name
  }
}

##################################################################################
# ECS Cluster
##################################################################################
resource "aws_ecs_cluster" "cluster" {
  name = var.cluster_name
}

##################################################################################
# Launch Template
##################################################################################

resource "aws_launch_template" "template" {
  name                   = "ecs-${var.cluster_name}-lt"
  instance_type          = var.instance_type
  image_id               = data.aws_ami.ecs.id
  ebs_optimized          = true
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.cluster.id]
  iam_instance_profile {
    arn = aws_iam_instance_profile.cluster-ec2-role.arn
  }

  user_data = "${base64encode(data.template_file.ecs_init.rendered)}"
  #The create_before_destroy meta-argument changes this behavior so that the new replacement object is created first,
  #and the prior object is destroyed after the replacement is created.
  
  lifecycle {
    create_before_destroy = true
  }
}

##################################################################################
# ASG
##################################################################################

resource "aws_autoscaling_group" "asg" {
  name                = "ecs-${var.cluster_name}-autoscaling"
  vpc_zone_identifier = split(",", var.vpc_subnets)
  #   launch_configuration = aws_launch_configuration.cluster.name
  termination_policies = split(",", var.ecs_termination_policies)
  min_size             = var.ecs_minsize
  max_size             = var.ecs_maxsize
  desired_capacity     = var.ecs_desired_capacity
  protect_from_scale_in = true
  launch_template {
    id      = aws_launch_template.template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-ecs"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

resource "aws_ecs_cluster_capacity_providers" "asg-cps" {
  cluster_name = aws_ecs_cluster.cluster.name
  capacity_providers = [aws_ecs_capacity_provider.asg-cp.name]
}

resource "aws_ecs_capacity_provider" "asg-cp" {
  name = "${var.cluster_name}-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.asg.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 600
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 10
    }
  }
}

##################################################################################
# Security Groups
##################################################################################

resource "aws_security_group" "cluster" {
  name        = var.cluster_name
  vpc_id      = var.vpc_id
  description = var.cluster_name
}

resource "aws_security_group_rule" "cluster-allow-ssh" {
   count                    = var.enable_ssh ? 1 : 0
   security_group_id        = aws_security_group.cluster.id
   type                     = "ingress"
   from_port                = 22
   to_port                  = 22
   protocol                 = "tcp"
   cidr_blocks              = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "cluster-allow-lb" {
   security_group_id = aws_security_group.cluster.id
   type = "ingress"
   from_port = 0
   to_port = 65535
   protocol = "tcp"
   source_security_group_id = var.lb_sg
}

resource "aws_security_group_rule" "cluster-allow-traffic-insde-sg" {
   security_group_id = aws_security_group.cluster.id
   type = "ingress"
   from_port = 0
   to_port = 65535
   protocol = "tcp"
   source_security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "cluster-egress" {
  security_group_id = aws_security_group.cluster.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}