terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.36.0"
    }
  }
}

# ~~~~~~~~~~~~~~~~ Configure the AWS provider ~~~~~~~~~~~~~~~~

provider "aws" {
  region = var.region
}
 
# ~~~~~~~~~~~~~~~~ Configure the Network ~~~~~~~~~~~~~~~~~~~~~ 
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name             = var.name
  cidr             = var.VPC_cidr
  azs              = ["${var.AZ1}", "${var.AZ2}"]
  private_subnets  = ["${var.subnet_priv1_cidr}", "${var.subnet_priv2_cidr}"]
  public_subnets   = ["${var.subnet_pub1_cidr}", "${var.subnet_pub2_cidr}"]

  # One NAT gateway per subnet and a single NAT for all of them
  enable_nat_gateway = true
  single_nat_gateway = true

  # Enable DNS support and hostnames in the VPC
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# ~~~~~~~~~~~ Security group for Elastic LoadBalancer ~~~~~~~~~~

resource "aws_security_group" "alb_sg" {

  name        = "${var.name}-alb-sg"
  description = "Security group for ${var.name} ALB"
  vpc_id      = module.vpc.vpc_id
  ingress {
    description = "BACKEND"
    from_port   = var.backend_port
    to_port     = var.backend_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "FRONTEND"
    from_port   = var.frontend_port
    to_port     = var.frontend_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = var.name
  }
}

# ~~~~~~~~~~~ Security group for Elastic Container Service ~~~~~~~~~~

resource "aws_security_group" "ecs_sg" {

  name        = "${var.name}-ecs-sg"
  description = "Security group for ${var.name} ecs"
  vpc_id      = module.vpc.vpc_id
  ingress {
    description = "BACKEND"
    from_port   = var.backend_port
    to_port     = var.backend_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "FRONTEND"
    from_port   = var.frontend_port
    to_port     = var.frontend_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.name}-ecs-sg"
  }
}

# ~~~~~~~~~~~~~~~~ Create a Load Balancer for the app ~~~~~~~~~~~~~~~~

resource "aws_lb" "alb" {
  name            = "${var.name}-alb"
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.alb_sg.id]
}

# ~~~~~~~~~~~~~~~~ Create a target Group for the backend~~~~~~~~~~~~~~

resource "aws_lb_target_group" "backend" {

  name        = "${var.name}-backend"
  port        = var.backend_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
      healthy_threshold   = var.health_check["healthy_threshold"]
      interval            = var.health_check["interval"]
      unhealthy_threshold = var.health_check["unhealthy_threshold"]
      timeout             = var.health_check["timeout"]
      path                = var.health_check["path"]
      port                = var.health_check["port"]
  }
}

# ~~~~~~~~~~~~~~~~ Create a target Group for the frontend ~~~~~~~~~~~~~

resource "aws_lb_target_group" "frontend" {

  name        = "${var.name}-frontend"
  port        = var.frontend_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
      healthy_threshold   = var.health_check["healthy_threshold"]
      interval            = var.health_check["interval"]
      unhealthy_threshold = var.health_check["unhealthy_threshold"]
      timeout             = var.health_check["timeout"]
      path                = var.health_check["path"]
      port                = var.health_check["port"]
  }
}

# ~~~~~~~~~~~~~~~~ Create a listener for the backend ~~~~~~~~~~~~~~~~

resource "aws_lb_listener" "backend" {

  load_balancer_arn = aws_lb.alb.arn
  port              = var.backend_port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# ~~~~~~~~~~~~~~~~ Create a listener for the frontend ~~~~~~~~~~~~~

resource "aws_lb_listener" "frontend" {

  load_balancer_arn = aws_lb.alb.arn
  port              = var.frontend_port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ~~~~~~~~~~~~~~~~ Create a ecr repository ~~~~~~~~~~~~~~~~~~~~~~~~

resource "aws_ecr_repository" "image_repository" {
  name = "${var.name}-repo"

  image_scanning_configuration {
    scan_on_push = false
  }
  
  force_delete = true
}

# ~~~~~~~~~~~~~~~~ Create a ecr lifecycle policy ~~~~~~~~~~~~~~~~~~

resource "aws_ecr_lifecycle_policy" "policy" {
  repository = aws_ecr_repository.image_repository.name

  policy = jsonencode(
    {
      "rules" : [
        {
          "rulePriority" : 1,
          "selection" : {
            "tagStatus" : "tagged",
            "tagPrefixList" : ["backend"],
            "countType" : "imageCountMoreThan",
            "countNumber" : 1
          },
          "action" : {
            "type" : "expire"
          }

        },
        {
          "rulePriority" : 2,
          "selection" : {
            "tagStatus" : "tagged",
            "tagPrefixList" : ["frontend"],
            "countType" : "imageCountMoreThan",
            "countNumber" : 1
          },
          "action" : {
            "type" : "expire"
          }
        }
      ]
    }
  )
}

# ~~~~~~~~~~~~~~~~~~ Create ECS EXECUTION Role ~~~~~~~~~~~~~~~~~~~~

module "ecs_execution_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"

  create_role = true

  role_requires_mfa = false

  role_name = "${var.name}-ecs-execution-role"

  trusted_role_services = [
    "ecs-tasks.amazonaws.com"
  ]

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
     "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
  ]
}

# ~~~~~~~~~~~~~~~~~~~~~~~~ Create TASK Role ~~~~~~~~~~~~~~~~~~~~~~~~~

module "ecs_task_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"

  create_role  = true

  role_requires_mfa = false

  role_name  = "${var.name}-ecs-task-role"

  trusted_role_services = [
    "ecs-tasks.amazonaws.com"
  ]

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  ]
}

# ~~~~~~~~~~~~~~~~~~~~~ Creating ECS Cluster ~~~~~~~~~~~~~~~~~~~~~~~

resource "aws_ecs_cluster" "cluster" {
  name = "${var.name}-Cluster"
}

# ~~~~~~~~~~~~ Creating ECS Task Definition for the services~~~~~~~~~

resource "aws_ecs_task_definition" "service" {
  
  family                   = "${var.name}"
  execution_role_arn       = module.ecs_execution_role.iam_role_arn
  task_role_arn            = module.ecs_task_role.iam_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  container_definitions    = jsonencode([
    {
      name = "frontend"
      image = "${aws_ecr_repository.image_repository.repository_url}:frontend"
      essential = false
      cpu       = 10
      memory    = 512
      portMappings = [
        {
          containerPort = var.frontend_port
        }
      ]
      healthCheck = {
        command = ["CMD", "curl", "--fail", "http://localhost:${var.frontend_port}"]
        interval = 300
      }
      environment = [
        {
          name = "REACT_APP_API_URL"
          value = "http://${aws_lb.alb.dns_name}:${var.backend_port}"
        }
      ]

    },
    {
      name = "backend"
      image = "${aws_ecr_repository.image_repository.repository_url}:backend"
      cpu       = 10
      memory    = 256
      essential = true
      portMappings = [
        {
          containerPort = var.backend_port
        }
      ]
      healthCheck = {
        command = ["CMD", "curl", "--fail", "http://localhost:${var.backend_port}/_health"]
        interval = 300
      }
      environment = [
         {
          name = "REACT_APP_ORIGIN"
          value = "http://${aws_lb.alb.dns_name}:${var.backend_port}"
        },
      ]
      
    }
  ])

}

#~~~~~~~~~~~~ Creating ECS service for the backend ~~~~~~~~~

resource "aws_ecs_service" "backend" {
  name            = "backend"
  cluster         = aws_ecs_cluster.cluster.id
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.service.arn

  network_configuration {
    security_groups  = [aws_security_group.ecs_sg.id]
    subnets          = module.vpc.private_subnets
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = var.backend_port
  }

}

#~~~~~~~~~~~~ Creating ECS service for the frontend ~~~~~~~~~

resource "aws_ecs_service" "frontend" {
  name            = "frontend"
  desired_count   = 1
  cluster         = aws_ecs_cluster.cluster.id
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.service.arn

  network_configuration {
    security_groups  = [aws_security_group.ecs_sg.id]
    subnets          = module.vpc.private_subnets
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = var.frontend_port
  }
}