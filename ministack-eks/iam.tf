data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}
## builds the trust-policy json

resource "aws_iam_role" "eks_cluster" {
  name               = "ministack-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json

  tags = {
    Project = "synchat"
  }
}
## creates the IAM role

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
## Gives the role permissions


output "eks_role_arn" {
  value = aws_iam_role.eks_cluster.arn
}