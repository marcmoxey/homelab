output "bucket_name" { value = b2_bucket.restic.bucket_name }
output "s3_endpoint" { value = data.b2_account_info.this.s3_api_url }
output "restic_key_id" { value = b2_application_key.restic.application_key_id }
output "restic_key" {
  value     = b2_application_key.restic.application_key
  sensitive = true
}
