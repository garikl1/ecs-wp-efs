provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Name    = var.project_name
      Billing = var.project_name
    }
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>3.0"
    }
  }
}