# ETHERNET_README – Killer E2500 (alx) on Predator PH315-52

## Background

This laptop has two wired Ethernet interfaces:
- **enx00e04c68039a** – USB Ethernet adapter (used for local LAN to Pi)
- **enp7s0** – Onboard Killer E2500 Gigabit Ethernet Controller (Qualcomm Atheros, PCI ID `1969:e0b1`), driven by the **alx** kernel module.

The onboard Killer NIC (`enp7s0`) was *not in use* but was causing:
- Massive IRQ and log spam (`[12] Timeout`, `BadTLP`, `BadDLLP`)
- PCIe AER (Advanced Error Reporting) floods
- Secondary `i915` "Atomic update failure" messages
- Occasional full system freezes under load

To stop this, we:
1. **Blacklisted the `alx` module** so the driver never loads.
2. **Added a systemd service** (`pci-remove-alx.service`) to hot-remove the PCI device at boot.
3. Verified the device is no longer bound to any driver and that logs are clean.

---

## Current Disable Configuration

**Blacklisting:**
```bash
/etc/modprobe.d/blacklist-alx.conf
blacklist alx
````

**Hot-remove service:**

```ini
# /etc/systemd/system/pci-remove-alx.service
[Unit]
Description=Hot-remove Killer E2500 (alx) at boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'test -e /sys/bus/pci/devices/0000:07:00.0/remove && echo 1 > /sys/bus/pci/devices/0000:07:00.0/remove || true'

[Install]
WantedBy=multi-user.target
```

---

## Quick Restore Command

If you need to re-enable the onboard Ethernet for something quick, run this **one-liner**:

```bash
sudo rm -f /etc/modprobe.d/blacklist-alx.conf /etc/systemd/system/pci-remove-alx.service && \
sudo systemctl disable pci-remove-alx.service 2>/dev/null || true && \
sudo update-initramfs -u && \
sudo systemctl daemon-reload && \
echo "=== Reboot required to restore Ethernet (enp7s0) ==="
```

After reboot, plug in a cable and bring it up:

```bash
sudo ip link set enp7s0 up
sudo dhclient enp7s0
```

Or just let **NetworkManager** handle it from the GUI.

---

## Full Manual Restore Steps

1. Remove blacklist and service:

```bash
sudo rm /etc/modprobe.d/blacklist-alx.conf
sudo systemctl disable pci-remove-alx.service
sudo rm /etc/systemd/system/pci-remove-alx.service
sudo update-initramfs -u
sudo systemctl daemon-reload
```

2. Reboot.

3. Check driver binding:

```bash
sudo lspci -nnk -s 07:00.0
# Should show: Kernel driver in use: alx
```

4. Bring up the interface:

```bash
sudo ip link set enp7s0 up
sudo dhclient enp7s0
```

---

## Optional Driver Tweaks (If Errors Return)

If you re-enable the port and start seeing AER or Timeout spam again:

* **Disable offloads:**

```bash
sudo ethtool -K enp7s0 tso off gso off gro off lro off rx off tx off
```

* **Disable Wake-on-LAN:**

```bash
sudo ethtool -s enp7s0 wol d
```

* **Disable EEE (Energy Efficient Ethernet):**

```bash
sudo ethtool --set-eee enp7s0 eee off
```

You can make these persistent with a NetworkManager dispatcher script.

---

## PCI Info

* Device: `07:00.0 Ethernet controller [0200]: Qualcomm Atheros Killer E2500 Gigabit Ethernet Controller [1969:e0b1] (rev 10)`
* Subsystem: Acer Incorporated \[ALI] \[1025:1343]
* Kernel module: `alx`

```

