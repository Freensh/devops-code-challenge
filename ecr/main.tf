
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