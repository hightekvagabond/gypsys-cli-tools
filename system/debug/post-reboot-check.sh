#!/usr/bin/env bash
set -euo pipefail

echo "=== Ethernet removal check ==="
ls /sys/bus/pci/devices/0000:07:00.0 >/dev/null 2>&1 && echo "FAIL: Device still present" || echo "PASS: Device removed"

echo "=== Driver binding check ==="
if sudo lspci -nnk -s 07:00.0 2>/dev/null | grep -q "Kernel driver in use"; then
    sudo lspci -nnk -s 07:00.0
else
    echo "PASS: No lspci entry (device absent)"
fi

echo "=== Kernel log (alx/PCIe/AER) ==="
if journalctl -k -b | egrep -qi 'alx|BadTLP|BadDLLP|\[12\] Timeout'; then
    echo "FAIL: Found NIC/AER spam"
else
    echo "PASS: No NIC/AER spam"
fi

echo "=== Graphics log noise check ==="
if journalctl -k -b | egrep -qi 'i915.*atomic update failure'; then
    echo "WARN: i915 atomic update failures present"
else
    echo "PASS: No i915 atomic update failures"
fi

echo "=== IRQ table check ==="
grep -E 'CPU|alx|i915|nvidia|xhci|nvme' /proc/interrupts

echo
echo "=== Last Boot Crash Triage (if previous boot exists) ==="
echo "--- Kernel errors from last boot ---"
journalctl -k -b -1 -p err..alert 2>/dev/null || echo "No prior boot or no errors."

echo
echo "--- Graphics/hang-related messages from last boot ---"
journalctl -b -1 2>/dev/null | egrep -i 'i915|drm|nvidia|xwayland|kwin|kwin_wayland|atomic|flip|timeout|rcu|stall|lockup|softlockup|hardlockup' | tail -n 500

echo
echo "--- PCIe/AER/DPC messages from last boot ---"
journalctl -k -b -1 2>/dev/null | egrep -i 'pcie|aer|dpc|fatal|correctable|uncorrectable' | tail -n 200

echo
echo "--- Machine Check Events (last boot) ---"
journalctl -k -b -1 2>/dev/null | egrep -i 'mce|machine check|hardware error' || true

echo
echo "--- NVMe errors/timeouts (current boot dmesg) ---"
dmesg -T | egrep -i 'nvme.*(err|timeout|reset)' || echo "No NVMe errors."

# ---------- New quick health checks ----------
echo
echo "=== systemd health ==="
systemctl is-system-running || true
systemctl --failed --no-pager || true

echo
echo "=== Network/DNS quick check ==="
# NM overall state (if present)
if command -v nmcli >/dev/null 2>&1; then
  nmcli -t -f STATE general || true
fi
# Link-level reachability (no DNS)
if ping -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
  echo "OK: ICMP to internet (1.1.1.1)"
else
  echo "FAIL: No ICMP connectivity to 1.1.1.1"
fi
# DNS resolution via systemd-resolved if available
if command -v resolvectl >/dev/null 2>&1; then
  if resolvectl query example.com >/dev/null 2>&1; then
    echo "OK: DNS query (resolvectl) example.com"
  else
    echo "FAIL: DNS query (resolvectl) example.com"
  fi
else
  # Fallback: getent hosts uses libc/nss
  if getent hosts example.com >/dev/null 2>&1; then
    echo "OK: DNS query (getent) example.com"
  else
    echo "FAIL: DNS query (getent) example.com"
  fi
fi

# Optional: show recent resolver/NM timeouts without flooding output
echo
echo "=== Recent resolver/NM timeouts (last 2h) ==="
journalctl --since "2 hours ago" -u systemd-resolved -u NetworkManager 2>/dev/null | \
  egrep -i 'timeout|failed|dispatcher|dns' | tail -n 50 || echo "No recent resolver/NM issues."

