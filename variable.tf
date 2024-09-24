variable "region" {
  type = string
  default = "us-east-1"
}
variable "AZ1" {
  type = string
  default = "us-east-2a"
}
variable "AZ2" {
  type = string
  default = "us-east-2b"
}
variable "frontend_app_name" {
  type = string
  default = "node-frontend" 
}
variable "backend_app_name" {
  type = string
  default = "node-backend" 
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
variable "project_name" {
    type = string
    default = "Challenge-node-app"
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