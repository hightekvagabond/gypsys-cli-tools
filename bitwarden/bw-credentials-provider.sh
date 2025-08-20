#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Bitwarden-backed AWS credential_process provider
# ------------------------------------------------------------------------------
# Overview
#   This script prints AWS credentials as JSON (Version=1) by reading them from
#   the Bitwarden CLI, so the AWS CLI/SDKs can obtain keys *on demand* via
#   `credential_process` (no plain-text keys in ~/.aws/credentials).
#
# What it does
#   - Validates an unlocked Bitwarden session (BW_SESSION or ~/.bw_session).
#   - Looks up items in Bitwarden, then emits:
#       {"Version":1,"AccessKeyId":"...","SecretAccessKey":"...","SessionToken":"..."}
#   - Exits non-zero with a human-readable message if anything is missing/locked.
#
# Requirements
#   - AWS CLI v2+
#   - Bitwarden CLI (`bw`) installed
#   - You’re logged in and unlocked:
#       bw login                         # first time on a machine
#       bw unlock --raw > ~/.bw_session  # refresh after lock/reboot
#
# Bitwarden storage convention (default mode: separate items)
#   Create items named exactly:
#     aws-<account>-<iam>-access-key      (password = AccessKeyId)
#     aws-<account>-<iam>-secret-key      (password = SecretAccessKey)
#     aws-<account>-<iam>-session-token   (password = SessionToken)  [optional]
#   Notes:
#     • These can be Login or Secure Note items; the script uses `bw get password`.
#     • If you use temporary STS creds (recommended), store the SessionToken too.
#
# Alternate (“single item notes”) mode  [optional, requires tiny code change]
#   Prefer one item instead? Create `aws-<account>-<iam>` and put in **Notes**:
#       AccessKeyId=AKIA...
#       SecretAccessKey=...
#       SessionToken=...        # optional
#   Then replace the FETCH-FROM-BITWARDEN block in this script with the notes-mode
#   snippet included in the comments below.
#
# Installation
#   - Save as:       ~/<path-to-script->/bw-credential-provider.sh
#   - Make executable:  chmod +x ~/<path-to-script->/bw-credential-provider.sh
#   - Ensure on PATH or reference by absolute path in your AWS config.
#
# AWS configuration (use ~/.aws/config, not ~/.aws/credentials):
#   Example profile wired to Bitwarden:
#     [profile ig-admin]
#     region = us-west-2
#     output = json
#     credential_process = /home/<you>/<path-to-script->/bw-credential-provider.sh ig admin
#
#   More examples:
#     [profile ops-admin]
#     credential_process = /home/<you>/<path-to-script->/bw-credential-provider.sh ops admin
#     [profile acctA-ci]
#     credential_process = /home/<you>/<path-to-script->/bw-credential-provider.sh acctA ci
#     [profile acctB-ro]
#     credential_process = /home/<you>/<path-to-script->/bw-credential-provider.sh acctB readonly
#
# Usage
#   Called by AWS CLI/SDKs automatically, or directly for testing:
#     AWS_PROFILE=ig-admin aws sts get-caller-identity
#   Direct (debug) call:
#     ~/<path-to-script->/bw-credential-provider.sh ig admin
#
# Session handling
#   - The script uses $BW_SESSION if set; otherwise reads ~/.bw_session.
#   - To (re)unlock Bitwarden:
#       bw unlock --raw > ~/.bw_session
#   - Protect the session file:
#       chmod 600 ~/.bw_session
#
# Security notes
#   - Avoid long-lived root keys. Prefer STS/MFA session creds in Bitwarden.
#   - Lock down this script and your bin dir:
#       chmod 700 ~/bin && chmod 755 ~/<path-to-script->/bw-credential-provider.sh
#   - Don’t put static creds in ~/.aws/credentials when using credential_process.
#
# Error behavior & troubleshooting
#   - “Bitwarden is locked.” → Run:  bw unlock --raw > ~/.bw_session
#   - “Item not found” / empty output → Check item names match the convention.
#   - AccessDenied/UnrecognizedClient → Keys are wrong/expired; update Bitwarden.
#   - Still stuck? Run with trace:  bash -x ./bw-credential-provider.sh acct iam
#
# Compatibility
#   - Works with AWS CLI and SDKs that honor `credential_process` (boto3, Go, Node).
#   - Emits AWS JSON Credentials v1 (no Expiration field). If you store STS
#     session tokens, the CLI will keep calling this script as needed.
#
# Quick start (copy/paste)
#   bw login
#   bw unlock --raw > ~/.bw_session
#   # Create Bitwarden items:
#   #   aws-ig-admin-access-key      (password=AKIA...)
#   #   aws-ig-admin-secret-key      (password=...)
#   #   aws-ig-admin-session-token   (password=...)   [optional]
#   echo '[profile ig-admin]
# region=us-west-2
# output=json
# credential_process=/home/'"$USER"'/<path-to-script->/bw-credential-provider.sh ig admin' \
#   >> ~/.aws/config
#   AWS_PROFILE=ig-admin aws sts get-caller-identity
#
# ------------------------------------------------------------------------------




set -euo pipefail

ACCOUNT="${1:-}"; IAM="${2:-}"
if [[ -z "$ACCOUNT" || -z "$IAM" ]]; then
  echo "Usage: $0 <account-name> <iam-user-name>" >&2
  exit 1
fi

PREFIX="aws-${ACCOUNT}-${IAM}"
ACCESS_KEY_NAME="${PREFIX}-access-key"
SECRET_KEY_NAME="${PREFIX}-secret-key"
SESSION_TOKEN_NAME="${PREFIX}-session-token"  # optional

# Load BW session from env or file
if [[ -z "${BW_SESSION:-}" && -f "$HOME/.bw_session" ]]; then
  export BW_SESSION="$(cat "$HOME/.bw_session")"
fi

# Ensure Bitwarden is unlocked
if ! bw status --session "${BW_SESSION:-}" >/dev/null 2>&1; then
  echo "Bitwarden is locked. Run: bw login && bw unlock --raw > ~/.bw_session" >&2
  exit 1
fi

ACCESS_KEY="$(bw get password "$ACCESS_KEY_NAME" --session "$BW_SESSION")"
SECRET_KEY="$(bw get password "$SECRET_KEY_NAME" --session "$BW_SESSION")"
SESSION_TOKEN="$(bw get password "$SESSION_TOKEN_NAME" --session "$BW_SESSION" 2>/dev/null || true)"

if [[ -n "$SESSION_TOKEN" ]]; then
  printf '{"Version":1,"AccessKeyId":"%s","SecretAccessKey":"%s","SessionToken":"%s"}\n' \
    "$ACCESS_KEY" "$SECRET_KEY" "$SESSION_TOKEN"
else
  printf '{"Version":1,"AccessKeyId":"%s","SecretAccessKey":"%s"}\n' \
    "$ACCESS_KEY" "$SECRET_KEY"
fi
