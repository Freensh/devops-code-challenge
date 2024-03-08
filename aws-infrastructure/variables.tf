variable "region" {
  type = string
  default = "us-east-2"
}

variable "VPC_cidr" {
  type = string
  default = "10.10.0.0/16" 
}

variable "name" {
  type = string
  default = "stack1"
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

variable "backend_port" {
  type    = number
  default = 8080
}

variable "frontend_port" {
  type    = number
  default = 3000
}

variable "public_port" {
  type    = number
  default = 80
}

variable "health_check" {
   type = map(string)
   default = {
      "healthy_threshold"   = "3"
      "timeout"             = "20"
      "interval"            = "60"
      "path"                = "/_health"
      "port"                = "80"
      "protocol"            = "http"
      "unhealthy_threshold" = "2"
    }
}

variable "fargate_cpu" {
  description = "Fargate instance CPU units to provision (1 vCPU = 1024 CPU units)"
  default     = "1024"
}

variable "fargate_memory" {
  description = "Fargate instance memory to provision (in MiB)"
  default     = "2048"
}