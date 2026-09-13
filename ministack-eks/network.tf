resource "aws_vpc" "eks" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "ministack-eks-vpc"
    Project = "synchat"
  }
}

resource "aws_subnet" "eks_a" {
  vpc_id            = aws_vpc.eks.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "ministack-eks-subnet-a"
  }
}

resource "aws_subnet" "eks_b" {
  vpc_id            = aws_vpc.eks.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "ministack-eks-subnet-b"
  }
}

output "vpc_id" {
  value = aws_vpc.eks.id
}

output "subnet_ids" {
  value = [
    aws_subnet.eks_a.id,
    aws_subnet.eks_b.id
  ]
}