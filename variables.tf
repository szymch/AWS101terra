variable "user_prefix" {
  type    = string
  default = "sc"
}

variable "ami_id" {
  type    = string
  default = "ami-029c5088a566b385e"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "vpc_id" {
  type    = string
  default = "vpc-0fead40e24304ce5f"
}

variable "subnet_id" {
  type    = string
  default = "subnet-0c5ab4a1499db9f85"
}
