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
  region = "${var.region}"
  
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

# ~~~~~~~~~~~ Security group for the Frontend LoadBalancer ~~~~~~~~~~

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

# ~~~~~~~~~~~ Security group for the Backend LoadBalancer ~~~~~~~~~~

resource "aws_security_group" "backend_sg" {

  name        = "${var.backend_app_name}-sg"
  description = "Security group for ${var.backend_app_name} ecs"
  vpc_id      = module.vpc.vpc_id
  ingress {
    description = "allows inbound fron the front end"
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

# ~~~~~~~~~~~~~~~~~~~~~ Creating ECS Cluster ~~~~~~~~~~~~~~~~~~~~~~~

resource "aws_ecs_cluster" "cluster" {
  name = var.cluster_name
}

# ~~~~~~~~ Create the ECR Repository for the Frontend app ~~~~~~~~~

resource "aws_ecr_repository" "repository-frontend" {
  name = "${var.frontend_app_name}-repo"

  image_scanning_configuration {
    scan_on_push = false
  }
  
  force_delete = true
}

# ~~~~~~~~ Create the ECR Repository for the Backend app ~~~~~~~~~

resource "aws_ecr_repository" "repository-backend" {
  name = "${var.backend_app_name}-repo"

  image_scanning_configuration {
    scan_on_push = false
  }
  
  force_delete = true
}


# ~~~~~~~~~~~~~~~ Get the ID of the current aws account ~~~~~~~~~~~~~~

data "aws_caller_identity" "current" {}

# ~~~~~~~~ Set the command we will later as a locals variables ~~~~~~~

locals {
  ecr-login             = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  docker-build-frontend = "docker build -t ${aws_ecr_repository.repository-frontend.repository_url}:latest frontend"
  docker-push-frontend  = "docker push ${aws_ecr_repository.repository-frontend.repository_url}:latest"
  docker-build-backend  = "docker build -t ${aws_ecr_repository.repository-backend.repository_url}:latest frontend"
  docker-push-backend   = "docker push ${aws_ecr_repository.repository-backend.repository_url}:latest"
}

# ~~~~ Log in to the aws ECR service of the current account to have enough rights to push images in ecr ~~~~

resource "null_resource" "ecr-login" {
	
	  provisioner "local-exec" {

	    command = local.ecr-login

	  }
  depends_on = [ aws_ecr_repository.repository-backend , aws_ecr_repository.repository-frontend ]
}

# ~~~~~~~~~~~ Build The Frontend Image from the Dockerfile of the frontend ~~~~~~~~~~

resource "null_resource" "docker-build-frontend" {
	
	  provisioner "local-exec" {

	    command = local.docker-build-frontend

	  }
  depends_on = [ null_resource.ecr-login ]
}

# ~~~~~~~~~~~~~~~ Push The Frontend Image the frontend ECR repository ~~~~~~~~~~~~~~

resource "null_resource" "push-to-ecr-frontend" {
	
	  provisioner "local-exec" {

	    command = local.docker-push-frontend

	  }
  depends_on = [ null_resource.docker-build-frontend ]
}

# ~~~~~~~~~~~ Build The Backend Image from the Dockerfile of the backend ~~~~~~~~~~~

resource "null_resource" "docker-build-backend" {
	
	  provisioner "local-exec" {

	    command = local.docker-build-backend

	  }
  depends_on = [ null_resource.ecr-login ]
}

# ~~~~~~~~~~~~~~~ Push The Backend Image to the backend ECR Repository ~~~~~~~~~~~~~

resource "null_resource" "push-to-ecr-backend" {
	
	  provisioner "local-exec" {

	    command = local.docker-push-backend

	  }
  depends_on = [ null_resource.docker-build-backend ]
}

# ~~~~~~~~~~ Clean Up docker images too when the infrastructure is destoyed ~~~~~~~~~

resource "null_resource" "clean-up-images" {
	
	  provisioner "local-exec" {

        when = destroy
	    command =<<EOF
		          docker rmi `docker image ls | grep "end-repo" | awk '{print $1}'`
		          EOF
        interpreter = [
           "bash",
            "-c"
         ]
	  }
	
}

output "INFO" {
  value = "AWS Resources  has been provisioned. Go to ${aws_ecr_repository.repository-backend.repository_url} and ${aws_ecr_repository.repository-frontend.repository_url}"
}