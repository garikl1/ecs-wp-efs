#https://buildvirtual.net/terraform-module-dependency/

data "aws_caller_identity" "current" {
}

module "wp-ecs-cluster" {
  source               = "./modules/ecs-cluster"
  vpc_id               = var.vpc_id
  cluster_name         = "pma"
  instance_type        = "t3.micro"
  ecs_minsize          = "2"
  ecs_maxsize          = "4"
  ecs_desired_capacity = "2"
  ssh_key_name         = aws_key_pair.mykeypair.key_name
  vpc_subnets          = join(",", var.subnets)
  enable_ssh           = true
  lb_sg                = module.wp-alb.security-group-id.id
  aws_account_id       = data.aws_caller_identity.current.account_id
  aws_region           = var.aws_region
}

module "wp-ecs-service" {
  source              = "./modules/ecs-service"
  vpc_id              = var.vpc_id
  application_name    = "pma-service"
  application_port    = "80"
  application_version = "latest"
  cluster_arn         = module.wp-ecs-cluster.cluster_arn
  service_role_arn    = module.wp-ecs-cluster.service_role_arn
  aws_region          = var.aws_region
  volumes = [{
    efs_volume_configuration = {
      authorization_config = {
        #access_point_id = aws_efs_access_point.pma-wpdata.id
        access_point_id = module.efs-wpdata.access_point_id
        iam             = "DISABLED"
      }
      file_system_id     = module.efs-wpdata.id
      transit_encryption = "ENABLED"
    }
    name = "pma-wpdata"
  }]
  mountpoints = [{
    containerPath = "/var/www/html"
    sourceVolume  = "pma-wpdata"
  }]
  healthcheck_matcher = "200,301,302"
  cpu_reservation     = "256"
  memory_reservation  = "128"
  log_group           = "wp-log-group"
  #Create service with 2 instances to start
  desired_count = 2
  alb_arn       = module.wp-alb.lb_arn
}

module "efs-wpdata" {
  source      = "./modules/efs"
  vpc_subnets = var.subnets
  ecs_sg      = [module.wp-ecs-cluster.cluster_sg]
}

module "wp-alb" {
  source             = "./modules/alb"
  vpc_id             = var.vpc_id
  lb_name            = "pma-alb"
  vpc_subnets        = var.subnets
  default_target_arn = module.wp-ecs-service.target_group_arn
  domain             = "geekgeneration.space"
  internal           = false
  ecs_sg             = [module.wp-ecs-cluster.cluster_sg]
}

module "wp-alb-rule" {
  source           = "./modules/alb-rule"
  listener_arn     = module.wp-alb.http_listener_arn
  priority         = 100
  target_group_arn = module.wp-ecs-service.target_group_arn
  condition_field  = "host-header"
  condition_values = ["geekgeneration.space"]
}