#!/bin/bash
#
# bw-login.sh
#
# This script logs into Bitwarden and unlocks your vault,
# exporting the BW_SESSION token.
#
# It works in two modes:
# 1. Interactive Mode (standalone execution):
#    Run as: ./bw-login.sh
#    Note: BW_SESSION will only be available in the subshell.
#
# 2. Sourced Mode (recommended):
#    Run as: source ./bw-login.sh
#    This exports BW_SESSION to your current shell.
#
# Integration Instructions:
#
#   If you have another script that depends on a valid Bitwarden session,
#   you can incorporate this login script at the beginning. For example:
#
#       #!/bin/bash
#       # Ensure Bitwarden session is loaded before proceeding
#       source "$HOME/bin/bw-login.sh" || exit 1
#
#       # Now you can use $BW_SESSION in your script:
#       SECRET=$(bw get notes my-api-key --session "$BW_SESSION")
#
# Bash Profile Integration:
#   To automatically load your Bitwarden session in every new shell,
#   add the following snippet to your ~/.bash_profile or ~/.bashrc:
#
#       if [ -f "$HOME/.bw_session" ]; then
#           export BW_SESSION=$(cat "$HOME/.bw_session")
#           if ! bw list items --session "$BW_SESSION" &>/dev/null; then
#               echo "Your Bitwarden session appears to be expired. Please log in."
#               source "$HOME/bin/bw-login.sh"
#           else
#               echo "Bitwarden session loaded."
#           fi
#       else
#           echo "No Bitwarden session found. Please log in."
#           source "$HOME/bin/bw-login.sh"
#       fi
#
# Usage:
#   ./bw-login.sh [--help]
#   source ./bw-login.sh [--help]
#
# Options:
#   --help    Show this help message and exit.
#

# Function to display usage info
usage() {
    echo "Usage: $(basename "$0") [--help]"
    echo ""
    echo "This script logs into Bitwarden and unlocks your vault, exporting the BW_SESSION token."
    echo ""
    echo "Modes:"
    echo "  Interactive Mode (standalone execution):"
    echo "    Run as: ./bw-login.sh"
    echo "    Note: BW_SESSION will only be available in the subshell."
    echo ""
    echo "  Sourced Mode (recommended):"
    echo "    Run as: source ./bw-login.sh"
    echo "    This exports BW_SESSION to your current shell."
    echo ""
    echo "Integration with Other Scripts:"
    echo "  If you have a script that requires access to Bitwarden secrets, add the following"
    echo "  at the beginning of your script to ensure a valid session is loaded:"
    echo ""
    echo "# Check if BW_SESSION is already set"
    echo "if [ -z \"${BW_SESSION:-}\" ]; then"
    echo "    source "$HOME/bin/bw-login.sh" || exit 1"
    echo "else"
    echo "    echo \"Using existing Bitwarden session.\""
    echo "fi"
    echo ""
    echo "  This makes the BW_SESSION variable available in your script for use with the Bitwarden CLI."
    echo ""
    echo "Bash Profile Integration:"
    echo "  To automatically load your Bitwarden session on starting a new shell, add this snippet"
    echo "  to your ~/.bash_profile or ~/.bashrc:"
    echo ""
    echo '    if [ -f "$HOME/.bw_session" ]; then'
    echo '        export BW_SESSION=$(cat "$HOME/.bw_session")'
    echo '        if ! bw list items --session "$BW_SESSION" &>/dev/null; then'
    echo '            echo "Your Bitwarden session appears to be expired. Please log in."'
    echo '            source "$HOME/bin/bw-login.sh"'
    echo '        else'
    echo '            echo "Bitwarden session loaded."'
    echo '        fi'
    echo '    else'
    echo '        echo "No Bitwarden session found. Please log in."'
    echo '        source "$HOME/bin/bw-login.sh"'
    echo '    fi'
    echo ""
    echo "Options:"
    echo "  --help    Show this help message and exit"
}

# If --help is passed, display help and exit
if [[ "${1:-}" == "--help" ]]; then
    usage
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        exit 0
    else
        return 0 2>/dev/null || exit 0
    fi
fi

# Determine if the script is sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    SOURCED=false
else
    SOURCED=true
fi

SESSION_FILE="$HOME/.bw_session"

# Helper function to finish with proper exit or return
finish() {
    if [ "$SOURCED" = true ]; then
        return "$1"
    else
        exit "$1"
    fi
}

# Step 1: Check if already logged in
if ! bw login --check &>/dev/null; then
    echo "[Bitwarden] Not logged in. Starting login..."
    bw login || { echo "[Bitwarden] Login failed."; finish 1; }
fi

# Step 2: Check for an existing session file and test it
if [ -f "$SESSION_FILE" ]; then
    export BW_SESSION=$(cat "$SESSION_FILE")
    if bw list items --session "$BW_SESSION" &>/dev/null; then
        echo "[Bitwarden] Already unlocked with valid session."
        if [ "$SOURCED" = false ]; then
            echo "[Bitwarden] Note: Running standalone, BW_SESSION is not available outside of this script."
        fi
        finish 0
    else
        echo "[Bitwarden] Previous session expired or invalid."
    fi
fi

# Step 3: Prompt for the master password (silent input)
read -s -p "[Bitwarden] Enter master password: " BW_MASTER_PASS
echo

# Step 4: Unlock the vault and export BW_SESSION
export BW_SESSION=$(bw unlock "$BW_MASTER_PASS" --raw) || {
    echo "[Bitwarden] Unlock failed."
    unset BW_SESSION
    finish 1
}

# Step 5: Save the session token to the session file
echo "$BW_SESSION" > "$SESSION_FILE"
chmod 600 "$SESSION_FILE"

echo "[Bitwarden] Vault unlocked and session exported."

if [ "$SOURCED" = false ]; then
    echo "[Bitwarden] Note: BW_SESSION is only available in this subshell. To export it to your current shell, source this script:"
    echo "         source ./bw-login.sh"
fi

finish 0

