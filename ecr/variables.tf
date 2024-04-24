variable "region" {
  type = string
  default = "us-east-2"
}
variable "frontend_app_name" {
  type = string
  default = "node-frontend" 
}
variable "backend_app_name" {
  type = string
  default = "node-backend" 
}
variable "project_name" {
    type = string
    default = "Challenge-node-app"
}
variable "VPC_cidr" {
  type = string
  default = "10.10.0.0/16" 
}
variable "subnet_priv1_cidr" {
  type = string
  default = "10.10.0.0/20"
}
variable "subnet_priv2_cidr" {
  type = string
  default = "10.10.16.0/20"
}
variable "subnet_pub1_cidr" {
  type = string
  default = "10.10.32.0/20"
} 
variable "subnet_pub2_cidr" {
  type = string
  default = "10.10.80.0/20"
}  
variable "AZ1" {
  type = string
  default = "us-east-2a"
}
variable "AZ2" {
  type = string
  default = "us-east-2b"
}
variable "cpu" {
    type = number
    default = 1024
}
variable "memory" {
    type = number
    default = 2048  
}
variable "image_tag" {
    type = string
    default = "latest"
}
variable "cluster_name" {
    type = string
    default = "Challenge"
}
variable "backend_port" {
    description = "port of the backend app"
    type = number
    default = 8080
}
variable "frontend_port" {
    description = "port of the frontend app"
    type = number
    default = 3000 
}
