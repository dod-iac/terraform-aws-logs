data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

#
# KMS
#

data "aws_iam_policy_document" "key_policy" {
  policy_id = "key-policy"
  statement {
    sid = "Enable IAM User Permissions"
    actions = [
      "kms:*"
    ]
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        format(
          "arn:%s:iam::%s:root",
          data.aws_partition.current.partition,
          data.aws_caller_identity.current.account_id
        )
      ]
    }
    resources = ["*"]
  }
  statement {
    sid = "Allow GuardDuty to use the key"
    actions = [
      "kms:GenerateDataKey"
    ]
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "guardduty.amazonaws.com"
      ]
    }
    resources = ["*"]
  }
}

resource "aws_kms_key" "guardduty" {
  description             = "Key used to encrypt GuardDuty findings."
  key_usage               = "ENCRYPT_DECRYPT"
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.key_policy.json
  enable_key_rotation     = true
  tags                    = {
    Automation = "Terraform"
    Usage = "GuardDuty"
  }
}

#
# Logs
#

module "aws_logs" {
  source = "../../"

  s3_bucket_name          = var.test_name
  guardduty_logs_prefixes = var.guardduty_logs_prefixes
  region                  = var.region
  allow_guardduty         = true
  default_allow           = false

  force_destroy = var.force_destroy
}

#
# GuardDuty
#

resource "aws_guardduty_detector" "test" {
  enable = true
  depends_on = [
    aws_kms_key.guardduty,
  ]
}

data "aws_s3_bucket" "main" {
  bucket = module.aws_logs.aws_logs_bucket
}

# GuardDuty expects a folder to exist, otherwise it throws an error.
resource "aws_s3_bucket_object" "test" {
  count  = length(var.guardduty_logs_prefixes)
  bucket = data.aws_s3_bucket.main.0.id
  acl    = "private"
  key    = format("%s/", var.guardduty_logs_prefixes[count.index])
  source = "/dev/null"
}

resource "aws_guardduty_publishing_destination" "test" {
  detector_id     = aws_guardduty_detector.test.id
  destination_arn = module.aws_logs
  kms_key_arn     = aws_kms_key.main.arn

  depends_on = [
    aws_s3_bucket_object.test,
  ]
}
