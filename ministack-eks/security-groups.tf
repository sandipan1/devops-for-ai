resource "aws_security_group" "synchat_app" {
  name        = "synchat-app"
  description = "Security group for Synchat application workloads"
  vpc_id      = aws_vpc.eks.id

  tags = {
    Name    = "synchat-app"
    Project = "synchat"
  }
}

resource "aws_security_group" "postgres" {
  name        = "synchat-postgres"
  description = "Security group for PostgreSQL"
  vpc_id      = aws_vpc.eks.id

  tags = {
    Name    = "synchat-postgres"
    Project = "synchat"
  }
}

resource "aws_security_group" "load_balancer" {
  name        = "synchat-load-balancer"
  description = "Security group for the Synchat public load balancer"
  vpc_id      = aws_vpc.eks.id

  tags = {
    Name    = "synchat-load-balancer"
    Project = "synchat"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_load_balancer" {
  security_group_id            = aws_security_group.synchat_app.id
  referenced_security_group_id = aws_security_group.load_balancer.id

  ip_protocol = "tcp"
  from_port   = 8080
  to_port     = 8080
  description = "Allow the load balancer to reach Synchat Pod targets"
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = aws_security_group.synchat_app.id

  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432
  description = "Allow Synchat application workloads to reach PostgreSQL"
}
