terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "target" {
  type    = string
  default = "ministack"

  validation {
    condition     = contains(["ministack", "aws"], var.target)
    error_message = "target must be either ministack or aws."
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type    = string
  default = "terraform-lab"
}

variable "bucket_suffix" {
  type        = string
  description = "A globally unique suffix for the AWS S3 bucket."
}

locals {
  is_ministack = var.target == "ministack"
}

provider "aws" {
  region  = var.aws_region
  profile = local.is_ministack ? null : var.aws_profile

  access_key = local.is_ministack ? "test" : null
  secret_key = local.is_ministack ? "test" : null

  skip_credentials_validation = local.is_ministack
  skip_metadata_api_check     = local.is_ministack
  skip_requesting_account_id  = local.is_ministack
  s3_use_path_style           = local.is_ministack

  endpoints {
    s3 = local.is_ministack ? "http://localhost:4566" : null
  }
}

resource "aws_s3_bucket" "lab" {
  bucket = "terraform-s3-${var.bucket_suffix}"

  tags = {
    Project = "terraform-practice"
    Lesson  = "terraform-s3"
    Target  = var.target
    Env
  }
}

output "bucket_name" {
  value = aws_s3_bucket.lab.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.lab.arn
}