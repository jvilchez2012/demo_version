output "public_ip" {
  value = aws_instance.app.public_ip
}

output "public_dns" {
  value = aws_instance.app.public_dns
}

output "app_url" {
  value = "http://${aws_instance.app.public_ip}"
}

output "lambda_function_name" {
  value = aws_lambda_function.hello.function_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.artifacts.arn
}
