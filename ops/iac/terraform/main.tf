terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region
}

# Default VPC + subnets (as you have)
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group (HTTP egress already wide open; keep as-is)
resource "aws_security_group" "app" {
  name        = "${var.name}-sg"
  description = "Allow HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- SSM role/profile (this is what enables Session Manager) ---
data "aws_iam_policy_document" "ssm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm" {
  name               = "${var.name}-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.name}-ssm-profile"
  role = aws_iam_role.ssm.name
}

# AL2023 AMI (keep)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# --- EC2 instance ---
resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 40
    delete_on_termination = true
  }

  # Ensure it gets a public IP 
  associate_public_ip_address = true

  # Pass image + ports to user_data template
  user_data = templatefile("${path.module}/user_data.sh", {
    IMAGE_REPO = var.image_repo
    IMAGE_TAG  = var.image_tag
    HTTP_PORT  = 80
    APP_PORT   = 4000
    NAME       = var.name
  })

  tags = { Name = var.name }
}


# Package the Lambda from the local folder into a ZIP
data "archive_file" "hello_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/hello"
  output_path = "${path.module}/lambda/hello.zip"
}

# IAM role for Lambda to write logs
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Attach AWS managed policy for basic CloudWatch logging
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# The Lambda function itself
resource "aws_lambda_function" "hello" {
  function_name = "${var.name}-hello"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "nodejs20.x"
  handler       = "index.handler"

  filename         = data.archive_file.hello_zip.output_path
  source_code_hash = data.archive_file.hello_zip.output_base64sha256
}


resource "random_id" "s3_suffix" {
  byte_length = 2
}

# S3 bucket (private, safe defaults)
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.s3_bucket_prefix}-${random_id.s3_suffix.hex}"
  force_destroy = true
  tags = {
    Name = "${var.name}-artifacts"
  }
}

# Enforce bucket-owner ownership and disable ACLs (modern S3 best practice)
resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Versioning
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption by default 
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


#let the EC2 instance role write logs to s3://.../logs/*
resource "aws_iam_role_policy" "ec2_s3_write" {
  role = aws_iam_role.ssm.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:PutObject"],
      Resource = "${aws_s3_bucket.artifacts.arn}/logs/*"
    }]
  })
}
