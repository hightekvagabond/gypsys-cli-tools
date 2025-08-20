#!/bin/bash
# -----------------------------------------------------------------------------
# Script Name: bw-credential-provider.sh
#
# Purpose:
#   AWS credential_process-compatible script to retrieve credentials stored in
#   the Bitwarden "notes" field using a naming scheme:
#   aws-{account}-{iam}-{key}, e.g.:
#     aws-smartbroadcast-gypsy-access-key
#     aws-smartbroadcast-gypsy-secret-key
#     aws-smartbroadcast-gypsy-region
#
# Usage:
#   bw-credential-provider.sh <account-name> <iam-user-name>
#
# Requirements:
#   - Bitwarden session stored in ~/.bw_session
#   - Secrets must be stored in `notes` field of any Bitwarden item
#
# Output:
#   JSON credentials for AWS CLI (Version 1 format)
#
# -----------------------------------------------------------------------------

set -euo pipefail

ACCOUNT="$1"
IAM="$2"

if [[ -z "$ACCOUNT" || -z "$IAM" ]]; then
  echo "Usage: $0 <account-name> <iam-user-name>" >&2
  exit 1
fi

# Key prefix we'll be looking for inside Bitwarden notes
PREFIX="aws-${ACCOUNT}-${IAM}"

# Load Bitwarden session if needed
if [[ -z "${BW_SESSION:-}" && -f "$HOME/.bw_session" ]]; then
  export BW_SESSION=$(cat "$HOME/.bw_session")
fi

if ! bw status --session "$BW_SESSION" | grep -q '"status":"unlocked"'; then
  echo "❌ Bitwarden is locked or session is invalid." >&2
  exit 1
fi

# Get all note content from all items in Bitwarden
NOTES=$(bw list items --session "$BW_SESSION" | jq -r '.[].notes' | grep "^${PREFIX}" || true)

if [[ -z "$NOTES" ]]; then
  echo "❌ No matching notes found in Bitwarden for prefix: $PREFIX" >&2
  exit 1
fi

# Parse keys from matching lines
get_value() {
  echo "$NOTES" | grep "^${PREFIX}-$1" | awk -F '=' '{ gsub(/^[ \t]+/, "", $2); print $2 }'
}

ACCESS_KEY=$(get_value "access-key")
SECRET_KEY=$(get_value "secret-key")
REGION=$(get_value "region")
SESSION_TOKEN=$(get_value "session-token")

# Fallback defaults
REGION="${REGION:-us-west-2}"

# Fail if required keys are missing
if [[ -z "$ACCESS_KEY" || -z "$SECRET_KEY" ]]; then
  echo "❌ Missing required AWS credentials for $PREFIX" >&2
  exit 1
fi

# Output JSON
jq -n --arg key "$ACCESS_KEY" \
      --arg secret "$SECRET_KEY" \
      --arg token "$SESSION_TOKEN" \
      --arg region "$REGION" '
  {
    Version: 1,
    AccessKeyId: $key,
    SecretAccessKey: $secret,
    SessionToken: ($token | select(length > 0)),
    Region: $region
  }'
