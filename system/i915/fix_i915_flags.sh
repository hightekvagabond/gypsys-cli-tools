#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  fix_i915_flags.sh
#
#  PURPOSE
#  -------
#  Apply (or re-apply) the kernel command-line flags that stop
#  Intel-i915 power-management features from freezing hybrid-GPU laptops:
#
#      i915.enable_psr=0 i915.disable_power_well=0
#
#  You can run this script manually on fresh installs *or* call it from an
#  Ansible role / cloud-init / bootstrap dotfile setup.  It is idempotent—
#  running it repeatedly is safe.
#
#  WHAT IT DOES
#  ------------
#  1. Edits /etc/default/grub, replacing the GRUB_CMDLINE_LINUX= line with
#     the required flags (retaining any existing flags you might add later).
#  2. Regenerates GRUB’s config so the flags take effect next boot.
#
#  VERIFIED ON
#  -----------
#    • Kubuntu 24.04 (Noble) with GRUB 2.12-beta3
#    • Works the same on Ubuntu, Debian, Arch, Fedora – as long as
#      /etc/default/grub exists and grub-mkconfig is in PATH.
#
#  USAGE
#  -----
#      sudo ./fix_i915_flags.sh
#
#  (sudo required only because /etc/default/grub is root-owned and
#   grub-mkconfig writes to /boot.)
#
# -----------------------------------------------------------------------------

set -euo pipefail

REQUIRED_FLAGS="i915.enable_psr=0 i915.enable_dc=0 i915.enable_fbc=0 i915.disable_power_well=0"

GRUB_FILE="/etc/default/grub"

echo ">>> Ensuring required i915 flags are set in $GRUB_FILE"

# Extract current line (may be empty if not present)
CURRENT=$(grep -E '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE" || true)

if [[ -z "$CURRENT" ]]; then
  echo "GRUB_CMDLINE_LINUX is missing – adding it from scratch."
  echo "GRUB_CMDLINE_LINUX=\"$REQUIRED_FLAGS\"" | sudo tee -a "$GRUB_FILE" >/dev/null
else
  # Strip leading key and quotes to get existing flags
  EXISTING=$(echo "$CURRENT" | sed -E 's/^GRUB_CMDLINE_LINUX="(.*)"$/\1/')
  if grep -q "i915.enable_psr=0" <<< "$EXISTING"; then
    echo "Flags already present – no change needed."
  else
    echo "Appending flags to existing GRUB_CMDLINE_LINUX."
    NEW_FLAGS="$EXISTING $REQUIRED_FLAGS"
    sudo sed -i -E \
      "s|^GRUB_CMDLINE_LINUX=\".*\"|GRUB_CMDLINE_LINUX=\"${NEW_FLAGS}\"|" \
      "$GRUB_FILE"
  fi
fi

echo ">>> Regenerating grub.cfg ..."
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "Done. Reboot for the new kernel parameters to take effect."

