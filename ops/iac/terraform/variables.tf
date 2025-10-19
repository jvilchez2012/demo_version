variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "name" {
  type    = string
  default = "demo-version-app"
}

variable "image_repo" {
  type    = string
  default = "jvilchez2012/demo_version"
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "s3_bucket_prefix" {
  type    = string
  default = "demo-version-app-artifacts"
}

variable "key_name" {
  type        = string
  description = "Name of an existing EC2 key pair to attach (e.g., 'pem')"
}

variable "ssh_cidr" {
  type        = string
  description = "CIDR allowed to SSH (port 22). Use your public IP in CIDR form."
  default     = "0.0.0.0/0"
}
