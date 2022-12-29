resource "aws_efs_file_system" "wpdata" {
}

resource "aws_efs_access_point" "wpdata_access_point" {
  file_system_id = aws_efs_file_system.wpdata.id
}

resource "aws_efs_mount_target" "efs-mount-us-east-2a" {
  file_system_id = aws_efs_file_system.wpdata.id
  subnet_id = var.vpc_subnets[0]
  security_groups = var.ecs_sg
}

resource "aws_efs_mount_target" "efs-mount-us-east-2b" {
  file_system_id = aws_efs_file_system.wpdata.id
  subnet_id = var.vpc_subnets[1]
  security_groups = var.ecs_sg
}