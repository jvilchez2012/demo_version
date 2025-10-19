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
