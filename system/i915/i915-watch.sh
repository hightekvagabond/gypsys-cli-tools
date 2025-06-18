#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  i915-watch.sh – lightweight watchdog for Intel-i915 GPU error storms
#
#  PURPOSE
#    Hybrid-GPU laptops (Intel iGPU + optional NVIDIA dGPU) running Linux
#    can occasionally freeze when the kernel’s i915 driver starts spamming
#    messages such as:
#      *ERROR* Atomic update failure on pipe A
#      workqueue: i915_hpd_poll_init_work hogged CPU
#    or when Dock/DisplayLink (evdi) hot-plug events cascade.
#
#    This script counts those errors in the current systemd-journal and
#    raises an alert if they exceed a configurable threshold.  It gives you
#    a heads-up *before* the machine reaches lock-up territory.
#
#  WHO SHOULD USE IT
#    • Any systemd-based distro (Ubuntu/Kubuntu 22.04, 24.04, Debian, Arch…)
#    • Hardware with Intel i915 graphics from Skylake → Alder Lake/Raptor
#    • Especially useful on:
#        – “Optimus” / hybrid laptops (Intel + NVIDIA)
#        – Set-ups that use DisplayLink / USB-C external-display adapters
#    • Safe to run on other rigs: if no i915 lines are present, the script
#      simply reports zero errors.
#
#  HOW TO DEPLOY
#    1. Save where ever you like I keep it in:  /home/gypsy/dev/gypsys-cli-tools/system/i915-watch.sh
#    2. `chmod +x` the file.
#    3. Add to root’s crontab or a systemd timer (hourly is fine) here is my example:
#         0 * * * * /home/gypsy/dev/gypsys-cli-tools/system/i915-watch.sh
#    4. Tune THRESHOLD below once you know your normal baseline.
#
#    The default alert uses `notify-send` (desktop) and also writes to syslog;
#    replace those lines if you’d rather email, Gotify-push, etc.
#
# -----------------------------------------------------------------------------
THRESHOLD=5          # maximum acceptable i915 errors per boot
ERRORS=$(journalctl -b | grep -cE "i915.*ERROR|workqueue: i915_hpd")

if (( ERRORS > THRESHOLD )); then
    notify-send -u critical "GPU watchdog: $ERRORS i915 errors this boot" || true
    logger -t i915-watch "High i915 error count: $ERRORS"
fi

