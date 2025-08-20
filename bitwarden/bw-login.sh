#!/bin/bash
#
# Bitwarden Session Auto-Loader
#
# This script ensures a usable Bitwarden CLI session is available in your current shell.
# It is designed to be safe for use in `.bashrc`, fast when already unlocked, and interactive only when required.
# 
# IMPORTANT: For best results, place your call to this script at the END of your .bashrc file.
# This prevents other scripts or environment files from overwriting the BW_SESSION variable.
# 
# Example .bashrc configuration:
#   # ... your other .bashrc content ...
#   source ~/dev/gypsys-cli-tools/bitwarden/bw-login.sh --auto
#
# Features:
# - Loads from session file or prompts if locked/expired
# - Avoids blocking shell startup unless prompting is required
# - Supports background syncing unless disabled via `--sync=0`
# - Can be quiet via `--auto` (for .bashrc)
# - Supports `BW_DEBUG=1` for verbose output
# - Override default session file via `BW_SESSION_FILE`

# Exit or return wrapper
finish() {
    if $SOURCED; then
        # For sourced scripts, we can't use return to exit early
        # Instead, we'll set a flag and check it throughout the script
        BW_EXIT_CODE="$1"
        return "$1"
    else
        exit "$1"
    fi
}

# Main function to handle early exits properly
bw_login_main() {
    # Early exit flag
    BW_EXIT_CODE=0

    # Check if Bitwarden CLI is installed
    if ! command -v bw &>/dev/null; then
        echo "[Bitwarden] CLI not found. Visit: https://bitwarden.com/help/cli/"
        echo "[Bitwarden] Or download from: https://github.com/bitwarden/cli/releases"
        return 1
    fi

    # Configurable session file
    SESSION_FILE="${BW_SESSION_FILE:-$HOME/.bw_session}"

    # Flags
    SOURCED=false
    AUTO_MODE=false
    SYNC_ENABLED=true

    # Detect if sourced
    [[ "${BASH_SOURCE[0]}" != "$0" ]] && SOURCED=true

    # Parse args
    for arg in "$@"; do
        case "$arg" in
            --auto) AUTO_MODE=true ;;
            --no-auto) AUTO_MODE=false ;;
            --sync=0) SYNC_ENABLED=false ;;
            --help)
                echo ""
                echo "Bitwarden Session Auto-Loader"
                echo ""
                echo "Usage:"
                echo "  source $REL_SCRIPT_PATH [--no-auto] [--sync=0]"
                echo "  ./bw-login.sh [--auto] [--sync=0]"
                echo ""
                echo "IMPORTANT: For best results, place your call to this script at the END of your .bashrc file."
                echo "This prevents other scripts or environment files from overwriting the BW_SESSION variable."
                echo ""
                echo "Flags:"
                echo "  --auto       Enable auto-mode (default when sourced)"
                echo "  --no-auto    Disable auto-mode (default when executed)"
                echo "  --sync=0     Disable background sync"
                echo ""
                echo "Environment Variables:"
                echo "  BW_SESSION_FILE  Override default ~/.bw_session location"
                echo "  BW_DEBUG=1       Enable verbose debug output"
                echo ""
                return 0
                ;;
        esac
    done

    # Skip in non-interactive shells when in auto mode
    if $AUTO_MODE && [[ $- != *i* ]]; then
        return 0
    fi

    # Step 1: Try loading session file
    if [[ -f "$SESSION_FILE" ]]; then
        export BW_SESSION=$(<"$SESSION_FILE")
        [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Loaded session ($SESSION_FILE) from file: ${BW_SESSION:0:10}..."

        # Check vault status with the session
        VAULT_STATUS=$(bw status --session "$BW_SESSION" 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unknown")
        
        if [[ "$VAULT_STATUS" == "unlocked" ]]; then
            # Double-check that bw status works correctly without the session parameter
            TEST_STATUS=$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unknown")
            if [[ "$TEST_STATUS" == "unlocked" ]]; then
                [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Valid session restored: ${BW_SESSION:0:10}..."

                if $SYNC_ENABLED; then
                    (
                        bw sync --session "$BW_SESSION" &>/dev/null || {
                            [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Sync retry..."
                            sleep 2
                            bw sync --session "$BW_SESSION" &>/dev/null
                        }
                    ) & disown
                fi

                return 0
            else
                [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Session validation failed (status: $TEST_STATUS)."
                # Clear invalid session
                unset BW_SESSION
            fi
        else
            [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Session exists but vault is locked (status: $VAULT_STATUS)."
            # Clear invalid session
            unset BW_SESSION
        fi
    else
        [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] No session file found."
    fi

    # Step 2: Only prompt in interactive shells
    if [[ $- != *i* ]]; then
        $AUTO_MODE && return 0 || {
            echo "[Bitwarden] Non-interactive shell. Cannot prompt."
            return 1
        }
    fi

    # Step 3: Check if already logged in and unlocked
    if bw login --check &>/dev/null; then
        # Already logged in, check if unlocked
        if bw unlock --check &>/dev/null; then
            # Already unlocked, but we need a session
            # If we have a valid session file, use it
            if [[ -f "$SESSION_FILE" ]]; then
                SAVED_SESSION=$(<"$SESSION_FILE")
                # Test if the saved session is still valid using status
                VAULT_STATUS=$(bw status --session "$SAVED_SESSION" 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unknown")
                if [[ "$VAULT_STATUS" == "unlocked" ]]; then
                    export BW_SESSION="$SAVED_SESSION"
                    [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Using saved session from file."
                    
                    if $SYNC_ENABLED; then
                        (
                            bw sync --session "$BW_SESSION" &>/dev/null || {
                                [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Post-unlock sync retrying..."
                                sleep 2
                                bw sync --session "$BW_SESSION" &>/dev/null
                            }
                        ) & disown
                    fi
                    
                    return 0
                fi
            fi
            
            # If we get here, we need to prompt for the master password
            # because we don't have a valid saved session
            [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Vault unlocked but no valid session found."
        fi
    else
        echo "[Bitwarden] Logging in..."
        bw login || { 
            echo "[Bitwarden] Login failed."; 
            return 1; 
        }
    fi

    # Step 4: Prompt for master password (only if not already unlocked)
    read -s -p "[Bitwarden] Enter master password: " BW_MASTER_PASS
    echo

    # Step 5: Unlock and export session
    export BW_SESSION=$(bw unlock "$BW_MASTER_PASS" --raw) || {
        echo "[Bitwarden] Invalid master password."
        unset BW_SESSION
        # Reprompt for password instead of exiting
        while true; do
            read -s -p "[Bitwarden] Enter master password: " BW_MASTER_PASS
            echo
            export BW_SESSION=$(bw unlock "$BW_MASTER_PASS" --raw) && break
            echo "[Bitwarden] Invalid master password."
            unset BW_SESSION
        done
    }

    # Always ensure session file and environment variable are in sync
    echo "$BW_SESSION" > "$SESSION_FILE"
    chmod 600 "$SESSION_FILE"

    echo "[Bitwarden] Vault unlocked and session exported."

    if $SYNC_ENABLED; then
        (
            bw sync --session "$BW_SESSION" &>/dev/null || {
                [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Post-unlock sync retrying..."
                sleep 2
                bw sync --session "$BW_SESSION" &>/dev/null
            }
        ) & disown
    fi

    # Final validation: ensure BW_SESSION env var and session file are in sync
    if [[ -n "$BW_SESSION" ]] && [[ -f "$SESSION_FILE" ]]; then
        SESSION_FILE_CONTENT=$(<"$SESSION_FILE")
        if [[ "$BW_SESSION" != "$SESSION_FILE_CONTENT" ]]; then
            [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Warning: Session mismatch detected, syncing..."
            export BW_SESSION="$SESSION_FILE_CONTENT"
        fi
    fi

    [[ "$BW_DEBUG" == "1" ]] && echo "[Bitwarden] Final session value: ${BW_SESSION:0:10}..."

    return 0
}

# Canonical path to this script
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
REL_SCRIPT_PATH="${SCRIPT_PATH/#$HOME/~}"

# Run the main function
bw_login_main "$@"
