output "id" {
    value = aws_efs_file_system.wpdata.id
} 

output "access_point_id" {
    value = aws_efs_access_point.wpdata_access_point.id
}