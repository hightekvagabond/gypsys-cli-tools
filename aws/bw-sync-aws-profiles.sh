#!/bin/bash
# -----------------------------------------------------------------------------
# Script Name: bw-sync-aws-profiles.sh
#
# Purpose:
#   Search Bitwarden notes for lines beginning with `aws-` and ensure matching
#   AWS CLI profiles exist in ~/.aws/config using `credential_process`.
#
# How It Works:
#   - Searches all Bitwarden item `notes` fields (not just titles)
#   - Finds lines like: aws-{account}-{iam}-{credential-name}
#   - Extracts unique {account}-{iam} combos
#   - If a profile is missing in ~/.aws/config, appends a profile that uses
#     the `bw-credential-provider.sh` script for dynamic credential resolution
#
# -----------------------------------------------------------------------------

set -euo pipefail

AWS_CONFIG="$HOME/.aws/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVIDER_SCRIPT="$SCRIPT_DIR/bw-credential-provider.sh"

# -----------------------------------------------------------------------------
# Load Bitwarden session
# -----------------------------------------------------------------------------
if [[ -z "${BW_SESSION:-}" && -f "$HOME/.bw_session" ]]; then
  export BW_SESSION=$(cat "$HOME/.bw_session")
fi

if ! bw status --session "$BW_SESSION" | grep -q '"status":"unlocked"'; then
  echo "❌ Bitwarden is locked or the session is invalid." >&2
  exit 1
fi

echo "🔍 Scanning Bitwarden for AWS credentials stored in notes..."

# -----------------------------------------------------------------------------
# Extract unique aws-{account}-{iam} prefixes from any line in notes
# -----------------------------------------------------------------------------
bw list items --session "$BW_SESSION" |
  jq -r '.[] | select(.notes != null) | .notes' |
  grep '^aws-' |
  awk -F '-' 'NF >= 4 { print $(2)"-"$(3) }' | sort -u |
while read -r profile; do

  if grep -q "^\[profile ${profile}\]" "$AWS_CONFIG"; then
    echo "✅ Profile already exists: $profile"
  else
    echo "➕ Adding missing profile: $profile"

    ACCOUNT="${profile%%-*}"  # extract everything before the first dash
    IAM="${profile#*-}"       # extract everything after the first dash

    {
      echo ""
      echo "[profile ${profile}]"
      echo "region = us-west-2"  # default, can be overridden dynamically
      echo "credential_process = ${PROVIDER_SCRIPT} ${ACCOUNT} ${IAM}"
    } >> "$AWS_CONFIG"
  fi
done

