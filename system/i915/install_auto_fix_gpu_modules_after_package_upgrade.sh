#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  install_auto_fix_gpu_modules_after_package_upgrade.sh
#
#  Installs:
#     • dpkg postinst hook  →  rebuild DKMS & re-apply i915 flags
#     • systemd oneshot     →  double-check at each boot
#
#  The hook points to *this* folder’s fix_gpu_modules.sh, so the whole
#  kit is portable across machines if you keep the two scripts together.
#
#  Usage:
#     sudo ./install_auto_fix_gpu_modules_after_package_upgrade.sh
# ---------------------------------------------------------------------------
#
set -euo pipefail
DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &>/dev/null && pwd )"
FIX="$DIR/fix_gpu_modules.sh"
[[ -x "$FIX" ]] || { echo "ERROR: $FIX not executable"; exit 1; }

echo "▶ Writing Apt hook → /etc/apt/apt.conf.d/99-fix-gpu"
sudo tee /etc/apt/apt.conf.d/99-fix-gpu >/dev/null <<EOF
// Rebuild NVIDIA/EVDI DKMS modules and re-apply i915 flags
// after each successful dpkg run triggered by APT.
DPkg::Post-Invoke-Success { "/usr/bin/env bash $FIX || true"; };
EOF

echo "▶ Installing / refreshing systemd boot checker"
sudo tee /etc/systemd/system/fix-gpu.service >/dev/null <<EOF
[Unit]
Description=Ensure NVIDIA/EVDI DKMS modules & i915 flags are correct
After=dkms.service
ConditionKernelCommandLine=!norepair

[Service]
Type=oneshot
ExecStart=$FIX
RemainAfterExit=yes
SuccessExitStatus=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now fix-gpu.service
echo "✅ Hook and service installed."

