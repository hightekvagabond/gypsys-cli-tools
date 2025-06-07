#!/bin/bash

# Debug script to diagnose desktop lag in KDE/Ubuntu

LOG="lag_debug_$(date +%F_%T).log"
exec &> >(tee "$LOG")

echo "=== System Overview ==="
hostnamectl
uptime
free -h
swapon --show

echo -e "\n=== CPU Info ==="
lscpu | grep -E 'Model name|Socket|Thread|CPU\(s\)'
echo -e "\nTop 10 CPU consumers:"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 15

echo -e "\n=== Memory Info ==="
echo "Top 10 memory consumers:"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 15

echo -e "\n=== GPU Info ==="
inxi -Gxx || lspci | grep -i vga
glxinfo | grep -E "OpenGL renderer|OpenGL core" 2>/dev/null || echo "glxinfo not installed"

echo -e "\n=== Compositor Info ==="
qdbus org.kde.KWin /KWin supportInformation 2>/dev/null | grep -iE 'Compositing|Backend|Renderer'

echo -e "\n=== Disk I/O (Current snapshot) ==="
iostat -xz 1 3

echo -e "\n=== Disk I/O by Process ==="
if command -v iotop &> /dev/null; then
    sudo iotop -b -n 3 | head -n 30
else
    echo "iotop not installed"
fi

echo -e "\n=== Plasma Shell Info ==="
ps aux | grep plasmashell | grep -v grep

echo -e "\n=== Baloo File Indexer ==="
balooctl status 2>/dev/null || echo "balooctl not found"

echo -e "\n=== Journal Errors (last boot) ==="
journalctl -p 3 -b

echo -e "\n=== Network Info ==="
ip a
nmcli dev show | grep -E 'GENERAL.DEVICE|IP4.ADDRESS|WIRED-PROPERTIES|SIGNAL'

echo -e "\n=== Final Notes ==="
echo "If GPU shows llvmpipe instead of AMD/NVIDIA/Intel, you are in software rendering mode."
echo "Check compositor settings under KDE System Settings > Display and Monitor > Compositor"

echo -e "\n=== Done. Log saved to: $LOG ==="

