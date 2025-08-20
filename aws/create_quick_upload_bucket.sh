#!/usr/bin/env bash
#
# quick-s3-upload.sh
# ------------------
# Interactively create an S3 bucket (in any region) using the AWS profile
# you specify, then set a *write-only* bucket policy so anyone can
# `curl --upload-file … https://BUCKET.s3.REGION.amazonaws.com/OBJECT`
#
# ⚠️  The policy below lets **anyone** upload objects.  They cannot *read*
#     or *list* them, but they *can* overwrite keys if they guess a name.
#     Use presigned URLs or an IAM user for production-grade security.

set -euo pipefail

read -rp "AWS profile to use: " PROFILE
read -rp "Bucket name (globally unique): " BUCKET
read -rp "AWS region (e.g. us-west-2): " REGION

# 1. Create the bucket
if [[ "$REGION" == "us-east-1" ]]; then
  aws --profile "$PROFILE" s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION"
else
  aws --profile "$PROFILE" s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
fi


# 2. Allow public PUTs (write-only)
cat > /tmp/public-put-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicWrite",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::$BUCKET/*"
    }
  ]
}
EOF

aws --profile "$PROFILE" \
    s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

aws --profile "$PROFILE" \
    s3api put-bucket-policy \
    --bucket "$BUCKET" \
    --policy file:///tmp/public-put-policy.json

echo
echo "✅  Bucket \"$BUCKET\" created with public write access."
echo
echo "Your client can now upload with a single command, no AWS credentials needed:"
echo "  curl --upload-file localfile.ext https://$BUCKET.s3.$REGION.amazonaws.com/remote/path/localfile.ext"

