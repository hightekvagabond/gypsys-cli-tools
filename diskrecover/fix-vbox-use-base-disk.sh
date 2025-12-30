#!/bin/bash
# Fix .vbox to use the base disk instead of the missing snapshot
# This is the CORRECT approach: change the current Hardware section to use the base disk
#
# Run with: sudo ./fix-vbox-use-base-disk.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECOVERY_DIR="${SCRIPT_DIR}/tmp"
VBOX_FILE="${RECOVERY_DIR}/CentOS 6/CentOS 6.vbox"

# Base disk UUID (the one that actually exists)
BASE_DISK_UUID="3a683d61-ada9-4d18-b8fb-2b2a69af4974"

# Snapshot disk UUID (the one that's missing)
SNAPSHOT_DISK_UUID="b68a3bc0-ea63-418f-8aaf-8caee5cb64b8"

# Detect the real user
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$USER"
fi

echo "=== Fix VirtualBox to Use Base Disk ==="
echo ""
echo "This will:"
echo "  1. Remove the snapshot disk reference from MediaRegistry"
echo "  2. Remove the Snapshot element"
echo "  3. Change current Hardware to use the base disk"
echo "  4. Remove currentSnapshot attribute"
echo ""

# Check if we have root
if [ "$EUID" -ne 0 ]; then
    echo "This script needs sudo to modify the files."
    echo "Relaunching with sudo..."
    echo ""
    exec sudo bash "$0" "$@"
fi

# Check if vbox file exists
if [ ! -f "$VBOX_FILE" ]; then
    echo "Error: .vbox file not found at $VBOX_FILE" >&2
    echo "Have you run the recovery script yet?" >&2
    exit 1
fi

echo "Working on: $VBOX_FILE"
echo ""

# Create backup
BACKUP_FILE="${VBOX_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
echo "Creating backup: $BACKUP_FILE"
cp "$VBOX_FILE" "$BACKUP_FILE"
chown "$REAL_USER:$REAL_USER" "$BACKUP_FILE"
echo "✓ Backup created"
echo ""

# Confirm
read -p "Proceed with fix? This will remove snapshot references. (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled by user"
    exit 0
fi

echo ""
echo "Fixing .vbox file..."

# Create a temporary file with the fixes
TMP_FILE=$(mktemp)

# Use Python to properly edit the XML
python3 - "$VBOX_FILE" "$TMP_FILE" "$BASE_DISK_UUID" "$SNAPSHOT_DISK_UUID" << 'PYTHON_SCRIPT'
import xml.etree.ElementTree as ET
import sys

vbox_file = sys.argv[1]
tmp_file = sys.argv[2]
base_disk_uuid = sys.argv[3]
snapshot_disk_uuid = sys.argv[4]

# Parse the XML with namespace preservation
ET.register_namespace('', 'http://www.virtualbox.org/')
tree = ET.parse(vbox_file)
root = tree.getroot()

# Define namespace
ns = {'vbox': 'http://www.virtualbox.org/'}

print("Step 1: Fixing MediaRegistry...")
# Find the base HardDisk and remove its child (the snapshot disk)
for harddisk in root.findall('.//vbox:HardDisk', ns):
    if harddisk.get('uuid') == '{' + base_disk_uuid + '}':
        # Remove child snapshot disk
        for child_disk in list(harddisk):
            if child_disk.get('uuid') == '{' + snapshot_disk_uuid + '}':
                print(f"  - Removing snapshot disk reference: {child_disk.get('location')}")
                harddisk.remove(child_disk)

print("\nStep 2: Removing Snapshot element...")
# Find and remove Snapshot elements
for machine in root.findall('.//vbox:Machine', ns):
    for snapshot in list(machine.findall('vbox:Snapshot', ns)):
        print(f"  - Removing snapshot: {snapshot.get('name')}")
        machine.remove(snapshot)
    
    # Remove currentSnapshot attribute
    if 'currentSnapshot' in machine.attrib:
        print(f"  - Removing currentSnapshot attribute")
        del machine.attrib['currentSnapshot']
    
    # Optional: Remove aborted attribute if present
    if 'aborted' in machine.attrib:
        print(f"  - Removing aborted attribute")
        del machine.attrib['aborted']

print("\nStep 3: Fixing current Hardware to use base disk...")
# Fix the current Hardware section (outside Snapshot) to use the base disk
# Find the Machine element
for machine in root.findall('.//vbox:Machine', ns):
    # Find the Hardware element that's a direct child of Machine (not inside Snapshot)
    hardware = machine.find('vbox:Hardware', ns)
    if hardware is not None:
        # Find the AttachedDevice in current Hardware
        for attached in hardware.findall('.//vbox:AttachedDevice', ns):
            image = attached.find('vbox:Image', ns)
            if image is not None:
                current_uuid = image.get('uuid')
                if current_uuid == '{' + snapshot_disk_uuid + '}':
                    print(f"  - Changing AttachedDevice from snapshot disk to base disk")
                    print(f"    Old: {current_uuid}")
                    print(f"    New: {'{' + base_disk_uuid + '}'}")
                    image.set('uuid', '{' + base_disk_uuid + '}')

# Write the modified XML
tree.write(tmp_file, encoding='utf-8', xml_declaration=True)
print("\n✓ XML modifications complete")

PYTHON_SCRIPT

# Check if Python script succeeded
if [ $? -ne 0 ]; then
    echo "Error: Python script failed" >&2
    rm -f "$TMP_FILE"
    exit 1
fi

# Replace the original file
if [ -s "$TMP_FILE" ]; then
    mv "$TMP_FILE" "$VBOX_FILE"
    chown "$REAL_USER:$REAL_USER" "$VBOX_FILE"
    chmod 644 "$VBOX_FILE"
    echo "✓ .vbox file updated"
else
    echo "Error: Failed to create modified file" >&2
    rm -f "$TMP_FILE"
    exit 1
fi

echo ""
echo "========================================="
echo "=== Fix Complete ==="
echo "========================================="
echo ""
echo "Changes made:"
echo "  ✓ Removed snapshot disk from MediaRegistry"
echo "  ✓ Removed Snapshot element"
echo "  ✓ Removed currentSnapshot attribute"
echo "  ✓ Changed current Hardware to use base disk"
echo ""
echo "Backup saved to:"
echo "  $BACKUP_FILE"
echo ""
echo "The VM is now configured to use the base disk directly."
echo "It will start in its current state (not the snapshot state)."
echo ""
echo "You can now import it into VirtualBox:"
echo "  1. Open VirtualBox"
echo "  2. Machine → Add"
echo "  3. Select: $VBOX_FILE"
echo ""


