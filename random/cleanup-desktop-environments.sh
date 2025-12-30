#!/bin/bash
#
# Desktop Environment Cleanup Script
# 
# This script removes unused file managers and desktop environment components
# that are not needed when using Unity/GNOME Shell with Dolphin.
#
# SAFETY: Review the packages before running. Run with --dry-run first.
#
# Usage:
#   ./cleanup-desktop-environments.sh --dry-run    # Preview what would be removed
#   ./cleanup-desktop-environments.sh              # Actually remove packages
#

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🔍 DRY RUN MODE - No packages will be removed"
    echo ""
fi

echo "🧹 Desktop Environment Cleanup"
echo "Current DE: Unity (GNOME Shell)"
echo "Default File Manager: Dolphin"
echo ""

# Packages to remove
PACKAGES_TO_REMOVE=(
    # GNOME file manager (since we're using Dolphin)
    "nautilus"
    "nautilus-data"
    "nautilus-dropbox"
    "nautilus-extension-gnome-terminal"
    "nautilus-sendto"
    "gnome-sushi"
    
    # Cinnamon file manager
    "nemo"
    "nemo-data"
    "nemo-fileroller"
    
    # KDE Plasma desktop components (keep CLI tools if needed)
    "plasma-desktop"
    "plasma-desktop-data"
    
    # Apport KDE frontend (if not needed)
    "apport-kde"
)

# Packages that might have dependencies - be more careful
OPTIONAL_REMOVE=(
    # Cinnamon desktop data (might be needed by other apps)
    "cinnamon-desktop-data"
    "cinnamon-l10n"
    "libcinnamon-desktop4t64"
    
    # KDE CLI tools (useful even if not using full KDE)
    # "kde-cli-tools"
    # "kde-cli-tools-data"
)

echo "📦 Packages to remove:"
INSTALLED_PKGS=()
for pkg in "${PACKAGES_TO_REMOVE[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        echo "  ✓ $pkg"
        INSTALLED_PKGS+=("$pkg")
    else
        echo "  - $pkg (not installed)"
    fi
done

echo ""
echo "📦 Optional packages (review carefully):"
OPTIONAL_INSTALLED=()
for pkg in "${OPTIONAL_REMOVE[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        echo "  ⚠️  $pkg (might have dependencies)"
        OPTIONAL_INSTALLED+=("$pkg")
    else
        echo "  - $pkg (not installed)"
    fi
done

echo ""
echo "⚠️  WARNING: This will remove file managers and desktop components."
echo "   Make sure you want to keep only Dolphin as your file manager."
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    if [[ ${#INSTALLED_PKGS[@]} -eq 0 ]]; then
        echo "🔍 No packages to remove (all are already uninstalled)"
    else
        echo "🔍 DRY RUN: Would run: sudo apt-get remove --autoremove --purge ${INSTALLED_PKGS[*]}"
    fi
    echo ""
    echo "To actually remove, run: ./cleanup-desktop-environments.sh"
    exit 0
fi

if [[ ${#INSTALLED_PKGS[@]} -eq 0 ]]; then
    echo "✅ No packages to remove!"
    exit 0
fi

read -p "Continue with removal? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "🗑️  Removing packages..."
sudo apt-get remove --autoremove --purge "${INSTALLED_PKGS[@]}"

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Remaining file manager: Dolphin"
echo "You should now see only 'Dolphin' in your applications menu."
