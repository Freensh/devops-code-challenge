
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
  region = "us-east-2"
  
}
resource "aws_ecr_repository" "repository" {
  name = "test-repo"

  image_scanning_configuration {
    scan_on_push = false
  }
  
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "policy" {

  repository = aws_ecr_repository.repository.name
  policy = <<EOF
	{
	    "rules": [
	        {
	            "rulePriority": 1,
	            "description": "Keep only the last 1 untagged images.",
	            "selection": {
	                "tagStatus": "untagged",
	                "countType": "imageCountMoreThan",
	                "countNumber": 1
	            },
	            "action": {
	                "type": "expire"
	            }
	        }
	    ]
	}
	EOF
}

data "aws_caller_identity" "current" {}

locals {
  ecr-login = "aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-2.amazonaws.com"
  docker-build = "docker build -t ${aws_ecr_repository.repository.repository_url}:latest Restaurantly"
  docker-tag ="docker tag ${aws_ecr_repository.repository.repository_url}:latest ${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-2.amazonaws.com/${aws_ecr_repository.repository.repository_url}:latest"
  docker-push = "docker push ${aws_ecr_repository.repository.repository_url}:latest"
}

resource "null_resource" "ecr-login" {
	
	  provisioner "local-exec" {

	    command = local.ecr-login

	  }
  depends_on = [ aws_ecr_repository.repository ,aws_ecr_lifecycle_policy.policy ]
}

resource "null_resource" "docker-build" {
	
	  provisioner "local-exec" {

	    command = local.docker-build

	  }
  depends_on = [ null_resource.ecr-login ]
}

resource "null_resource" "push-to-ecr" {
	
	  provisioner "local-exec" {

	    command = local.docker-push

	  }
  depends_on = [ null_resource.docker-build ]
}

output "INFO" {
  value = "AWS Resources  has been provisioned. Go to ${aws_ecr_repository.repository.repository_url}"
}