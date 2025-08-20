#!/bin/bash

# =============================================================================
# Import VirtualBox VM (VMDK or OVA) as AWS AMI - Minimal, Safe, Self-Cleaning
# Usage: ./import-vm-to-aws.sh --vm-file <path> --profile <aws-profile>
# Requires: awscli v2, jq, uuidgen, tar
# =============================================================================

set -euo pipefail

# ---- Config & Checks --------------------------------------------------------

error_exit() { echo "❌ $1" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || error_exit "$1 required"; }
for c in aws jq uuidgen tar; do need_cmd "$c"; done

VM_FILE=""
PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vm-file) VM_FILE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    *) error_exit "Unknown arg: $1" ;;
  esac
done

[[ -z "$VM_FILE" ]] && error_exit "Missing --vm-file"
[[ -z "$PROFILE" ]] && error_exit "Missing --profile"
[[ ! -f "$VM_FILE" ]] && error_exit "File not found: $VM_FILE"

# ---- AWS CLI Profile Validation ---------------------------------------------

aws sts get-caller-identity --profile "$PROFILE" >/dev/null || error_exit "AWS profile '$PROFILE' not valid"

# ---- Handle OVA vs VMDK ----------------------------------------------------

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

VM_EXT="${VM_FILE##*.}"
if [[ "$VM_EXT" == "ova" ]]; then
  echo "📦 Extracting VMDK from OVA..."
  tar -xvf "$VM_FILE" -C "$TMPDIR"
  VMDK=$(find "$TMPDIR" -name '*.vmdk' | head -n1)
  [[ -z "$VMDK" ]] && error_exit "No VMDK found in OVA."
elif [[ "$VM_EXT" == "vmdk" ]]; then
  VMDK="$VM_FILE"
else
  error_exit "File must be .vmdk or .ova"
fi

# ---- S3 Bucket (Temp) -------------------------------------------------------

GUID=$(uuidgen | tr 'A-Z' 'a-z')
EPOCH=$(date +%s)
BUCKET="vmimport-${GUID}-${EPOCH}"
FILENAME=$(basename "$VMDK")
KEY="disk/${FILENAME}"

echo "🪣 Creating temp S3 bucket: $BUCKET"
aws s3 mb "s3://$BUCKET" --profile "$PROFILE"

echo "📤 Uploading $VMDK to s3://$BUCKET/$KEY"
aws s3 cp "$VMDK" "s3://$BUCKET/$KEY" --profile "$PROFILE"

# ---- IAM Role Check/Setup ---------------------------------------------------

ROLE_NAME="vmimport"
if ! aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" >/dev/null 2>&1; then
  echo "🔐 Creating IAM role $ROLE_NAME"
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://<(cat <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
  ) --profile "$PROFILE"
fi

aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "vmimport" \
  --policy-document file://<(cat <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"s3:GetObject","Resource":"arn:aws:s3:::$BUCKET/*"}]}
EOF
) --profile "$PROFILE"

# ---- Import Image -----------------------------------------------------------

CONTAINER_JSON="$TMPDIR/containers.json"
cat > "$CONTAINER_JSON" <<EOF
{
  "Description": "Imported VM image",
  "Format": "vmdk",
  "UserBucket": {
    "S3Bucket": "$BUCKET",
    "S3Key": "$KEY"
  }
}
EOF

echo "🚀 Starting AMI import..."
IMPORT_OUTPUT=$(aws ec2 import-image \
  --description "Imported VirtualBox VM" \
  --disk-containers "file://$CONTAINER_JSON" \
  --profile "$PROFILE")

IMPORT_TASK_ID=$(echo "$IMPORT_OUTPUT" | jq -r '.ImportTaskId')
echo "✅ Import started. Task ID: $IMPORT_TASK_ID"

# ---- Wait & Clean Up S3 -----------------------------------------------------

echo "⏳ Waiting for import to finish. This can take a while..."
while true; do
  sleep 60
  STATUS=$(aws ec2 describe-import-image-tasks --import-task-ids "$IMPORT_TASK_ID" --profile "$PROFILE" | jq -r '.ImportImageTasks[0].Status')
  echo "  Status: $STATUS"
  [[ "$STATUS" == "completed" || "$STATUS" == "deleted" || "$STATUS" == "deleting" ]] && break
done

echo "🗑️  Deleting S3 bucket and object..."
aws s3 rm "s3://$BUCKET/$KEY" --profile "$PROFILE"
aws s3 rb "s3://$BUCKET" --force --profile "$PROFILE"
echo "🎉 All done. Your AMI will be available in your account shortly."
