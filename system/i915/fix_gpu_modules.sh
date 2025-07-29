#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  fix_gpu_modules.sh  —  run at boot or after kernel install
#
#  • Ensures NVIDIA and EVDI DKMS modules are built for the running kernel
#  • Re-applies the four i915 kernel flags if /etc/default/grub lost them
#  • Notifies the user (wall + journal) if a reboot is required
# ---------------------------------------------------------------------------
#
# add so it auto runs after any package upgrade:
# sudo tee /etc/dpkg/dpkg.cfg.d/99-fix-gpu <<'EOF'
# #Rebuild NVIDIA & EVDI DKMS modules and re-apply i915 flags
# #every time dpkg finishes installing a package.
# postinst.d/fix-gpu   root   /usr/local/sbin/fix_gpu_modules.sh
# EOF
#
#

set -euo pipefail
KERNEL=$(uname -r)
NEED_REBOOT=0
log() { logger -t fix-gpu "$*"; echo "$*"; }


# --- 0. Ensure headers are present ------------------------------------------
if [[ ! -e /lib/modules/$KERNEL/build ]]; then
    log "Headers missing for $KERNEL – installing …"
    apt-get -y update
    if ! apt-get -y install "linux-headers-$KERNEL" "linux-modules-extra-$KERNEL"; then
        log "Failed to install headers; will try again on next apt run."
        exit 0        # leave quietly; next package run will retry
    fi
fi

# --- 1. Build DKMS modules ---------------------------------------------------
for mod in nvidia evdi virtualbox; do
    if ! dkms status | grep -q "$mod/.*,$KERNEL,.*installed"; then
        log "DKMS: building $mod for $KERNEL"
        dkms autoinstall -k "$KERNEL" || {
            log "DKMS build for $mod failed — will retry next apt run."; exit 0; }
    fi
done


# --- 2. Ensure the i915 flags survive --------------------------------------
REQ_FLAGS="i915.enable_psr=0 i915.enable_dc=0 i915.enable_fbc=0 i915.disable_power_well=0"
if ! grep -q "$REQ_FLAGS" /proc/cmdline; then
    sed -i -E "s|^GRUB_CMDLINE_LINUX=\".*\"|GRUB_CMDLINE_LINUX=\"$REQ_FLAGS\"|" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    log "i915 flags re-applied: $REQ_FLAGS"
    NEED_REBOOT=1
fi

# --- 3. If anything changed, prompt for reboot -----------------------------
if (( NEED_REBOOT )); then
    wall "GPU stack updated for kernel $KERNEL — please reboot."
fi
exit 0          # always succeed; systemd won’t mark unit failed

