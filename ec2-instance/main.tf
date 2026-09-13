terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    # Create this bucket with the MiniStack command before running terraform init.
    bucket = "terraform-state-bucket"
    key    = "ec2-instance/terraform.tfstate"
    region = "us-east-1"

    # The S3 backend is initialized before the AWS provider, so MiniStack's
    # endpoint and placeholder credentials must be configured here too.
    access_key = "test"
    secret_key = "test"

    endpoints = {
      s3 = "http://localhost:4566"
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

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

locals {
  is_ministack = var.target == "ministack"
}

provider "aws" {
  region  = var.aws_region
  profile = local.is_ministack ? null : var.aws_profile

  # MiniStack accepts placeholder credentials. Real AWS credentials are used
  # only when target = "aws".
  access_key = local.is_ministack ? "test" : null
  secret_key = local.is_ministack ? "test" : null

  # Prevent the AWS provider from contacting real AWS while using MiniStack.
  skip_credentials_validation = local.is_ministack
  skip_metadata_api_check     = local.is_ministack
  skip_requesting_account_id  = local.is_ministack

  endpoints {
    ec2 = local.is_ministack ? "http://localhost:4566" : null
    sts = local.is_ministack ? "http://localhost:4566" : null
  }
}

resource "aws_instance" "app-server" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"

  tags = {
    Name      = "MyNewTerraformInstance"
    Target    = var.target
    AccountId = data.aws_caller_identity.current.account_id
  }
}

data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}
