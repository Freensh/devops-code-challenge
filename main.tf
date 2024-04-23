terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.36.0"
    }
  }
}

# Configure the AWS provider

provider "aws" {
  region = var.region
  
}
# ~~~~~~~~~~~~~~~~ Configure the Network ~~~~~~~~~~~~~~~~~~~~~ 
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name             = var.project_name
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

  private_subnet_tags = {
    Tier = "Private"
  }
  public_subnet_tags = {
    Tier = "Public"
  }
  tags = {
    Project = "${var.project_name}"
  }
}

# ~~~~~~~~~~~ Create the Security group for the Frontend LoadBalancer ~~~~~~~~~~

resource "aws_security_group" "frontend_sg" {

  name        = "${var.frontend_app_name}-sg"
  description = "Security group for ${var.frontend_app_name} ecs"
  vpc_id      = module.vpc.vpc_id
  ingress {
    description = "allows connection from the internet"
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
    Name = "${var.frontend_app_name}-sg"
  }
}

# ~~~~~~~~~~~ Create the Security group for the Backend LoadBalancer ~~~~~~~~~~

resource "aws_security_group" "backend_sg" {

  name        = "${var.backend_app_name}-sg"
  description = "Security group for ${var.backend_app_name} ecs"
  vpc_id      = module.vpc.vpc_id
  ingress {
    description = "allows inbound fron the frontend"
    from_port   = var.backend_port
    to_port     = var.backend_port
    protocol    = "tcp"
    security_groups = [aws_security_group.frontend_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.backend_app_name}-sg"
  }
}
# ~~~~~~~~~~~~~~~~ Create a Load Balancer for the frontend app ~~~~~~~~~~~~~~~~

resource "aws_lb" "frontend_lb" {
  name            = "${var.frontend_app_name}-lb"
  subnets         = [module.vpc.public_subnets[0], module.vpc.public_subnets[1]]
  security_groups = [aws_security_group.frontend_sg.id]
}

# ~~~~~~~~~~~~~~~~ Create a Load Balancer for the backend app ~~~~~~~~~~~~~~~~

resource "aws_lb" "backend_lb" {
  name            = "${var.backend_app_name}-lb"
  subnets         = [module.vpc.public_subnets[0], module.vpc.public_subnets[1]]
  security_groups = [aws_security_group.backend_sg.id]
}

# ~~~~~~~~~~~~~~~~ Create a target Group for the backend~~~~~~~~~~~~~~

resource "aws_lb_target_group" "backend_target_group" {

  name        = "${var.backend_app_name}-targets-group"
  port        = var.backend_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"


}
# ~~~~~~~~~~~~~~~~ Create a listener for the backend ~~~~~~~~~~~~~~~~

resource "aws_lb_listener" "backend_listener" {

  load_balancer_arn = aws_lb.backend_lb.arn
  port              = var.backend_port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_target_group.arn
  }
}

# ~~~~~~~~~~~~~~~~ Create a target Group for the frontend ~~~~~~~~~~~~~

resource "aws_lb_target_group" "frontend_target_group" {

  name        = "${var.frontend_app_name}-targets-group"
  port        = var.frontend_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

}

# ~~~~~~~~~~~~~~~~ Create a listener for the frontend ~~~~~~~~~~~~~

resource "aws_lb_listener" "frontend_listener" {

  load_balancer_arn = aws_lb.frontend_lb.arn
  port              = var.frontend_port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_target_group.arn
  }
}

# ~~~~~~~~~~~~~~~~ Create a ecr repository ~~~~~~~~~~~~~~~~~~~~~~~~

resource "aws_ecr_repository" "backend_repository" {
  name = "${var.backend_app_name}-repo"

  image_scanning_configuration {
    scan_on_push = false
  }
  
  force_delete = true
}
resource "aws_ecr_repository" "frontend_repository" {
  name = "${var.frontend_app_name}-repo"

  image_scanning_configuration {
    scan_on_push = false
  }
  
  force_delete = true
}
# ~~~~~~~~~~~~~~~~~~ Create ECS EXECUTION Role ~~~~~~~~~~~~~~~~~~~~

module "ecs_execution_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"

  create_role = true

  role_requires_mfa = false

  role_name = "${var.project_name}-ecs-execution-role"

  trusted_role_services = [
    "ecs-tasks.amazonaws.com"
  ]

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
     "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
  ]
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~ Creating ECS Cluster ~~~~~~~~~~~~~~~~~~~~~~~~~~~

resource "aws_ecs_cluster" "cluster" {
  name = var.cluster_name
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~ Getting ecr repository ~~~~~~~~~~~~~~~~~~~~~~~~~~
data "aws_ecr_repository" "back_repo" {
    name = "${var.backend_app_name}-repo"
}
data "aws_ecr_repository" "front_repo" {
    name = "${var.frontend_app_name}-repo"
}
# ~~~~~~~~~~~~ Creating ECS Task Definition for the backend services ~~~~~~~~~
resource "aws_ecs_task_definition" "backend_task_definition" {
    family = var.backend_app_name
    network_mode = "awsvpc"
    execution_role_arn = module.ecs_execution_role.arn
    requires_compatibilities = ["FARGATE"]
    cpu = var.cpu
    memory = var.memory
    container_definitions = <<TASK_DEFINITION
    [
        {
            "name": "${var.backend_app_name}",
            "image": "${data.aws_ecr_repository.back_repo.repository_url}:${var.image_tag}",
            "essential": true,
            "cpu": ${var.cpu},
            "memory": ${var.memory},
            "portMappings": [
                {
                    "containerPort": ${var.backend_port},
                    "hostPort": ${var.backend_port}
                }
            ],
            "environment": [
                {
                    "name": "REACT_APP_ORIGIN",
                    "value": "http://${aws_lb.frontend_lb.dns_name}:${var.frontend_port}"
                }
            ]
        }
    ]
    TASK_DEFINITION
    runtime_platform {
      operating_system_family = "LINUX"
      cpu_architecture = "X86_64"
    }
}

resource "aws_ecs_service" "backend_svc" {
    name = "${var.backend_app_name}-svc"
    cluster = aws_ecs_cluster.cluster.id
    launch_type = "FARGATE"
    task_definition = aws_ecs_task_definition.backend_task_definition.arn
    desired_count = 4

    network_configuration {
      security_groups = [ aws_security_group.backend_sg.id]
      subnets = [module.vpc.public_subnets[0], module.vpc.public_subnets[1]]
      assign_public_ip = true
    }

    load_balancer {
      target_group_arn = aws_lb_target_group.backend_target_group.arn
      container_name = var.backend_app_name
      container_port = var.backend_port
      
    }
  
}

# ~~~~~~~~~~~~ Creating ECS Task Definition for the services~~~~~~~~~
resource "aws_ecs_task_definition" "frontend_task_definition" {
    family = var.frontend_app_name
    network_mode = "awsvpc"
    execution_role_arn = data.aws_iam_role.execution_role.arn
    requires_compatibilities = ["FARGATE"]
    cpu = var.cpu
    memory = var.memory
    container_definitions = <<TASK_DEFINITION
    [
        {
            "name": "${var.frontend_app_name}",
            "image": "${data.aws_ecr_repository.front_repo.repository_url}:${var.image_tag}",
            "essential": true,
            "cpu": ${var.cpu},
            "memory": ${var.memory},
            "portMappings": [
                {
                    "containerPort": ${var.frontend_port},
                    "hostPort": ${var.frontend_port}
                }
            ],
            "environment": [
                {
                    "name": "REACT_APP_API_URL",
                    "value": "http://${aws_lb.backend_lb.dns_name}:${var.backend_port}/"
                }
            ]
        }
    ]
    TASK_DEFINITION
    runtime_platform {
      operating_system_family = "LINUX"
      cpu_architecture = "X86_64"
    }
}

resource "aws_ecs_service" "frontend_svc" {
    name = var.frontend_app_name
    cluster = aws_ecs_cluster.cluster.id
    launch_type = "FARGATE"
    task_definition = aws_ecs_task_definition.frontend_task_definition.arn
    desired_count = 4

    network_configuration {
      security_groups = [ aws_security_group.frontend_sg.id ]
      subnets         = [module.vpc.public_subnets[0], module.vpc.public_subnets[1]]
    }

    load_balancer {
      target_group_arn = aws_lb_target_group.frontend_target_group.arn
      container_name   = var.frontend_app_name
      container_port   = 8080
    }
  
}

