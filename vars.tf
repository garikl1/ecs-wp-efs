variable "project_name" {
  type    = string
  default = "pma"
}

variable "aws_region" {
  default = "us-east-2"
}

data "aws_vpc" "default" {
  default = true
}

variable "vpc_id" {
  type    = string
  default = "vpc-0b2a20ad148e49177"
}

variable "vpc_name" {
  type    = string
  default = "main"
}

variable "subnets" {
  type    = list(string)
  default = ["subnet-004dda88af2ef94b9", "subnet-05858e8148515c780"]
}

variable "private_key" {
  default = "keys/garik.pem"
}

variable "public_key" {
  default = "keys/garik.pub"
}