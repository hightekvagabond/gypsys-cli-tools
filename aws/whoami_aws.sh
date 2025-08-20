#!/usr/bin/env bash
# aws-whoami — consolidated IAM entity / account inventory
# USAGE:
#   aws-whoami               # all profiles
#   aws-whoami prod dev qa   # only these

set -euo pipefail
shopt -s lastpipe

########################################
# 1. Gather profile list
########################################
if (( $# )); then
    PROFILES=("$@")
else
    mapfile -t PROFILES < <(aws configure list-profiles)
fi

########################################
# 2. Data stores
########################################
declare -A ACCID IAMNAME STATUS ACCNAME
LIST_ACCOUNTS_DONE=0              # flips when org scan succeeds

########################################
# 3. Per-profile sweep
########################################
for P in "${PROFILES[@]}"; do
    if read -r AID ARN _ 2>/dev/null < <(
            aws sts get-caller-identity \
                --profile "$P" \
                --query '[Account, Arn, UserId]' --output text
        ); then
        STATUS[$P]="OK"
        ACCID[$P]=$AID
        IAMNAME[$P]=${ARN##*/}

        # ---- fill in / improve account name ----
        [[ -z ${ACCNAME[$AID]:-} || ${ACCNAME[$AID]} =~ ^(N/A|None)$ ]] && {
            if name=$(aws organizations describe-account \
                          --profile "$P" --account-id "$AID" \
                          --query 'Account.Name' --output text 2>/dev/null); then
                ACCNAME[$AID]=$name
            elif alias=$(aws iam list-account-aliases \
                             --profile "$P" \
                             --query 'AccountAliases[0]' --output text 2>/dev/null) \
                     && [[ $alias != "None" ]]; then
                ACCNAME[$AID]=$alias
            else
                ACCNAME[$AID]="N/A"
            fi
        }

        # ---- one-time full org enumeration (errors suppressed) ----
        if (( ! LIST_ACCOUNTS_DONE )); then
            if aws organizations list-accounts \
                   --profile "$P" \
                   --query 'Accounts[?Status==`ACTIVE`].[Id,Name]' \
                   --output text 2>/dev/null |
                   while read -r id nm; do
                       [[ $nm != "None" ]] && ACCNAME[$id]=$nm
                   done; then
                LIST_ACCOUNTS_DONE=1
            fi
        fi
    else
        STATUS[$P]="INVALID"
    fi
done

########################################
# 4. Report
########################################
printf "\n%-20s %-25s %-15s %-30s %-8s\n" \
       "Profile" "IAM entity" "Account ID" "Account name" "Status"
printf -- "-----------------------------------------------------------------------------------------------------------\n"

for P in "${PROFILES[@]}"; do
    aid=${ACCID[$P]:-"-"}
    printf "%-20s %-25s %-15s %-30s %-8s\n" \
           "$P" "${IAMNAME[$P]:-"-"}" "$aid" "${ACCNAME[$aid]:-"N/A"}" "${STATUS[$P]}"
done

