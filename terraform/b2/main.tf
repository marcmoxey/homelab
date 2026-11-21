data "b2_account_info" "this" {}

resource "b2_bucket" "restic" {
  bucket_name = var.bucket_name
  bucket_type = "allPrivate"

  default_server_side_encryption {
    algorithm = "AES256"
    mode      = "SSE-B2"
  }

  # restic deletes old data itself; this makes B2 actually remove hidden versions after 1 day
  lifecycle_rules {
    file_name_prefix             = ""
    days_from_hiding_to_deleting = 1
  }
}

resource "b2_application_key" "restic" {
  key_name     = "nas-restic"
  bucket_id    = b2_bucket.restic.bucket_id
  capabilities = ["listBuckets", "listFiles", "readFiles", "writeFiles", "deleteFiles"]
}
