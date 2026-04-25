output "web_bucket_name" {
  value = aws_s3_bucket.this["web"].bucket
}

output "media_bucket_name" {
  value = aws_s3_bucket.this["media"].bucket
}

output "documents_bucket_name" {
  value = aws_s3_bucket.this["documents"].bucket
}

output "web_cloudfront_domain" {
  value = aws_cloudfront_distribution.this["web"].domain_name
}

output "media_cloudfront_domain" {
  value = aws_cloudfront_distribution.this["media"].domain_name
}

output "web_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this["web"].id
}
