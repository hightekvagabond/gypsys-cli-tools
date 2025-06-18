# i915 Toolbox (for hybrid-GPU freeze mitigation)

This folder contains two small, self-contained utilities that harden
Intel i915-based laptops against the infamous *Atomic update failure* /
*workqueue hogged CPU* freeze and then keep an eye on the logs
afterwards.

| Script | Purpose | Typical usage |
|--------|---------|---------------|
| **`fix_i915_flags.sh`** | Adds the kernel flags<br>`i915.enable_psr=0 i915.disable_power_well=0`<br>to **/etc/default/grub** and regenerates GRUB. | Run once after a fresh install (or any time the flags disappear). <br>`sudo ./fix_i915_flags.sh` |
| **`i915-watch.sh`** | Hourly watchdog that counts i915 error lines in the current boot’s journal and pops a desktop notification / syslog entry if they exceed a threshold. | Installed via root cron: <br>`0 * * * * /path/to/i915-watch.sh` |

---

## Why these flags?

* **`i915.enable_psr=0`**  
  Disables Panel Self-Refresh, a power feature that frequently deadlocks the display engine on Coffee-/Comet-Lake hybrids.

* **`i915.disable_power_well=0`**  
  Keeps certain clocks powered during hot-plug polling; prevents the
  *workqueue: i915_hpd_poll_init_work hogged CPU* storm.

Both are safe on desktops and laptops alike; the only downside is a
negligible bump in idle power (~0.2 W).

---

## Installation quick-reference

```bash
# 1 – Apply kernel flags (idempotent)
cd ~/dev/gypsys-cli-tools/system/i915
sudo ./fix_i915_flags.sh
# reboot

# 2 – Deploy watchdog
sudo chmod +x i915-watch.sh
sudo crontab -e         # add the line below
0 * * * * /home/gypsy/dev/gypsys-cli-tools/system/i915/i915-watch.sh
````

Adjust the `THRESHOLD` variable in **`i915-watch.sh`** once you know your
stable baseline (5 works well on the Helios PH315-52).

---

## Tested on

* **Kubuntu 24.04** (kernel 6.11) with Intel UHD 630 + NVIDIA RTX 2060
* DisplayLink EVDI 1.14 and stock HDMI output

Both scripts are POSIX-shell compliant and should work on any
systemd-based distro as long as `/etc/default/grub` exists.

---

*Last updated 2025-06-17*


