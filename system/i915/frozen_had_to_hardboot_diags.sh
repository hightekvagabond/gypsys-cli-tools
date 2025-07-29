#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  gather_gpu_diagnostics.sh
#
#  Collects logs & system state for post-freeze analysis on Kubuntu/Ubuntu.
#  Run it ONCE, *after* rebooting from a lock-up (no additional reboot needed).
#
#  OUTPUT
#    /tmp/gpu_diag_<date>.tar.gz   ← attach or share as needed.
#
# To share with a LLM for diagnosis.
#
# ---------------------------------------------------------------------------

set -euo pipefail

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="/tmp/gpu_diag_${TS}"
mkdir -p "$OUTDIR"

echo "Collecting diagnostics in $OUTDIR …"

# 1. Kernel & journal logs (current and previous boot)
journalctl -b   > "$OUTDIR/journal_this_boot.log"
journalctl -b -1 > "$OUTDIR/journal_prev_boot.log" || true   # may not exist
dmesg -T        > "$OUTDIR/dmesg_this_boot.log"

# 2. High-priority errors (easier to skim)
journalctl -b --priority=3..0 > "$OUTDIR/journal_errors_this_boot.log" || true
journalctl -b -1 --priority=3..0 > "$OUTDIR/journal_errors_prev_boot.log" || true

# 3. GPU / DisplayLink specifics
lsmod | grep -E 'i915|nvidia|evdi'  > "$OUTDIR/loaded_modules.txt"
dkms status                         > "$OUTDIR/dkms_status.txt"
systemctl list-units --type=service | grep -E 'displaylink|nvidia' \
                                    > "$OUTDIR/services_status.txt" || true

# 4. Hardware snapshot
lspci -nnk | grep -A3 -E 'VGA|3D|Display' > "$OUTDIR/pci_gpus.txt"
lsusb                                     > "$OUTDIR/usb_devices.txt"
xrandr --listmonitors                     > "$OUTDIR/monitors.txt" || true

# 5. GRUB flags & kernel cmdline
grep ^GRUB_CMDLINE_LINUX= /etc/default/grub > "$OUTDIR/grub_cmdline.txt"
cat /proc/cmdline                         > "$OUTDIR/current_cmdline.txt"

# 6. Basic resource info
free -h               > "$OUTDIR/meminfo.txt"
uptime                >> "$OUTDIR/meminfo.txt"

# 7. Pack it up
TARBALL="/tmp/gpu_diag_${TS}.tar.gz"
tar -czf "$TARBALL" -C /tmp "gpu_diag_${TS}"

echo "Diagnostics bundle created: $TARBALL"
echo "Attach that tarball in our chat and we can dig in."

