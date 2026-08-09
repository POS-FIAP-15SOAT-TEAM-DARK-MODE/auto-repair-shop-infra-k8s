output "state_bucket" {
  description = "Use this as the `bucket` in the shared/aws backend blocks"
  value       = aws_s3_bucket.tfstate.id
}
