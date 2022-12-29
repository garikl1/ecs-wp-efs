##############################################
# Terraform configuration
##############################################

terraform {
  required_version = ">= 0.12"
}

##############################################
# ECR
##############################################

resource "aws_ecr_repository" "ecs-service" {
  count = length(var.containers) == 0 ? 1 : 0

  name = var.ecr_prefix == "" ? var.application_name : "${var.ecr_prefix}/{var.application_name}"

  image_scanning_configuration {
    scan_on_push = true
  }
}

##############################################
# DATA source(get latest revision)
##############################################
data "aws_ecs_task_definition" "ecs-service" {
  task_definition = aws_ecs_task_definition.ecs-service-taskdef.arn != "" ? aws_ecs_task_definition.ecs-service-taskdef.family : ""
}

##############################################
# LOCALS
#- computed values inside the config that can be used
#- in other programming languages, these would usually be called variables
#- the values or locals are not submitted from an external input, 
#- but they can be computed based on input variables and internal references.
##############################################
locals {
  template-vars = {
    aws_region = var.aws_region
    containers = length(var.containers) > 0 ? var.containers : [{
      application_name    = var.application_name
      host_port           = 0
      application_port    = var.application_port
      additional_ports    = var.additional_ports
      application_version = var.application_version
      ecr_url             = aws_ecr_repository.ecs-service.0.repository_url
      cpu_reservation     = var.cpu_reservation
      memory_reservation  = var.memory_reservation
      command             = var.command
      links               = []
      dependsOn           = []
      mountpoints         = var.mountpoints
      secrets             = var.secrets
      environments        = var.environments
      environment_files   = var.environment_files
      docker_labels       = {}
    }]
  }
}

##############################################
# TASK DEFINITION
##############################################
resource "aws_ecs_task_definition" "ecs-service-taskdef" {
  family                   = var.application_name
  container_definitions    = templatefile("${path.module}/templates/ecs-service.json.tpl", local.template-vars)
  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.execution_role_arn
  requires_compatibilities = ["EC2"]
  dynamic "volume" {
    for_each = var.volumes
    content {
      name = volume.value.name
      dynamic "efs_volume_configuration" {
        for_each = length(volume.value.efs_volume_configuration) > 0 ? [volume.value.efs_volume_configuration] : []
        content {
          file_system_id     = efs_volume_configuration.value.file_system_id
          transit_encryption = efs_volume_configuration.value.transit_encryption
          dynamic "authorization_config" {
            for_each = length(efs_volume_configuration.value.authorization_config) > 0 ? [efs_volume_configuration.value.authorization_config] : []
            content {
              access_point_id = authorization_config.value.access_point_id
              iam             = authorization_config.value.iam
            }
          }
        }
      }
    }
  }
}

##############################################
# TASK SERVICE
##############################################
resource "aws_ecs_service" "ecs-service" {
  name    = var.application_name
  cluster = var.cluster_arn
  task_definition = "${aws_ecs_task_definition.ecs-service-taskdef.family}:${max(
    aws_ecs_task_definition.ecs-service-taskdef.revision,
    data.aws_ecs_task_definition.ecs-service.revision,
  )}"
  iam_role                           = var.service_role_arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type                        = var.launch_type
  enable_execute_command             = var.enable_execute_command

  load_balancer {
    #element function retrieves a single element from a list.
    #element(["a", "b", "c"], 1) -> b
    #target_group_arn = element([for ecs-service in aws_lb_target_group.ecs-service : ecs-service.arn], 0)
    target_group_arn = aws_lb_target_group.ecs-service.arn
    container_name   = length(var.containers) == 0 ? var.application_name : var.exposed_container_name
    container_port   = length(var.containers) == 0 ? var.application_port : var.exposed_container_port
  }

  depends_on = [null_resource.alb_exists]
}

resource "null_resource" "alb_exists" {
  triggers = {
    alb_name = var.alb_arn
  }
}

##############################################
# ALB
##############################################

resource "aws_lb_target_group" "ecs-service" {
  name                 = var.application_name
  port                 = var.application_port
  protocol             = var.protocol
  vpc_id               = var.vpc_id
  deregistration_delay = var.deregistration_delay

  health_check {
    healthy_threshold   = var.healthcheck_healthy_threshold
    unhealthy_threshold = var.healthcheck_unhealthy_threshold
    protocol            = var.protocol
    path                = var.healthcheck_path
    interval            = var.healthcheck_interval
    matcher             = var.healthcheck_matcher
  }
}

##############################################
# SECURITY GROUPS
##############################################

# resource "aws_security_group" "ecs-service" {
#   name        = var.application_name
#   vpc_id      = var.vpc_id
#   description = var.application_name

#   dynamic ingress {
#     for_each = var.ingress_rules
#     content {
#       from_port       = ingress.value.from_port
#       to_port         = ingress.value.to_port
#       protocol        = ingress.value.protocol
#       security_groups = ingress.value.security_groups
#     }
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }