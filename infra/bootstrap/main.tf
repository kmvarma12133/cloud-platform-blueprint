locals {
  # Must match the bucket name computed in infra/live/root.hcl.
  bucket_name = "cpb-tfstate-${var.account_id}-${var.region}"
}

data "aws_partition" "current" {}

# --- Encryption key ------------------------------------------------------------

data "aws_iam_policy_document" "state_kms" {
  #checkov:skip=CKV_AWS_109:In a key policy "*" means this key only; the account root statement is the AWS default that delegates access to IAM.
  #checkov:skip=CKV_AWS_111:Same as above: key policies cannot name the key ARN they are attached to.
  #checkov:skip=CKV_AWS_356:Same as above.
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "state" {
  description             = "Terraform state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.state_kms.json
}

resource "aws_kms_alias" "state" {
  name          = "alias/cpb-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

# --- State bucket --------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:Access logging needs a second bucket; CloudTrail S3 data events are the better audit trail for a handful of state objects.
  #checkov:skip=CKV_AWS_144:Single-region reference. Versioning plus prevent_destroy cover accidental deletion; add replication for regional DR.
  #checkov:skip=CKV2_AWS_62:Nothing consumes state-change events.
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is what makes a corrupted or bad state write recoverable.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  # The public access block must exist first or the policy call can race it.
  depends_on = [aws_s3_bucket_public_access_block.state]
}
