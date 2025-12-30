#!/bin/bash
# Recovery script for VirtualBox VMs from Backup directory
# The VMs are already accessible - just need to copy and skip corrupted files
#
# Run this with sudo: sudo ./diskrecover/recover-from-backup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# VirtualBox VMs are directly in the Backup directory (not inside extfat.img)
SOURCE_DIR="/media/gypsy/14d5b2d9-68a9-4444-85a1-c98a3e01122f/Backup/VirtualBox VMs"
RECOVERY_DIR="${SCRIPT_DIR}/tmp"

# Detect the real user (in case running with sudo)
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$USER"
fi

echo "=== VirtualBox VMs Recovery Script ==="
echo "Recovering from: $SOURCE_DIR"
echo "Recovery destination: $RECOVERY_DIR"
echo "Running as: $USER (real user: $REAL_USER)"
echo ""

# Check if we have root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo" >&2
    echo "Usage: sudo $0" >&2
    exit 1
fi

# Check if source exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory not found at $SOURCE_DIR" >&2
    exit 1
fi

# Check if already recovering
if [ -d "$RECOVERY_DIR" ] && [ "$(ls -A "$RECOVERY_DIR" 2>/dev/null)" ]; then
    echo "⚠️  Warning: Recovery directory already contains files:"
    ls -lh "$RECOVERY_DIR"
    echo ""
    read -p "Overwrite existing files? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Recovery cancelled by user"
        exit 0
    fi
    echo "Backing up existing recovery to ${RECOVERY_DIR}.bak..."
    rm -rf "${RECOVERY_DIR}.bak" 2>/dev/null || true
    mv "$RECOVERY_DIR" "${RECOVERY_DIR}.bak"
fi

mkdir -p "$RECOVERY_DIR"

# Step 1: Analyze source directory
echo "========================================="
echo "Step 1: Analyzing source directory"
echo "========================================="
echo ""

echo "VirtualBox VMs found:"
ls -lh "$SOURCE_DIR"
echo ""

# Check for corruption
echo "Analyzing filesystem for corruption..."
CORRUPT_COUNT=$(find "$SOURCE_DIR" -type f ! -newermt "2000-01-01" 2>/dev/null | wc -l)
if [ "$CORRUPT_COUNT" -gt 0 ]; then
    echo "⚠️  Found $CORRUPT_COUNT files with dates before 2000 (likely corrupted)"
    echo "   These files will be skipped during recovery"
    echo ""
fi

# Check important VM files
echo "Verifying critical VM files:"
for vm_dir in "$SOURCE_DIR"/*; do
    if [ -d "$vm_dir" ]; then
        vm_name=$(basename "$vm_dir")
        echo ""
        echo "VM: $vm_name"
        
        # Check for .vdi files
        find "$vm_dir" -maxdepth 1 -name "*.vdi" 2>/dev/null | while read -r vdi; do
            size=$(du -sh "$vdi" | cut -f1)
            fileinfo=$(file "$vdi")
            echo "  ✓ Virtual disk: $(basename "$vdi") - $size"
            if [[ "$fileinfo" =~ "VirtualBox Disk Image" ]]; then
                echo "    Status: Valid VDI file"
            else
                echo "    Status: Unknown format - $fileinfo"
            fi
        done
        
        # Check for .vbox files
        find "$vm_dir" -maxdepth 1 -name "*.vbox" 2>/dev/null | while read -r vbox; do
            fileinfo=$(file "$vbox")
            echo "  ✓ Configuration: $(basename "$vbox")"
            if [[ "$fileinfo" =~ "XML" ]]; then
                echo "    Status: Valid XML configuration"
            else
                echo "    Status: May be corrupted"
            fi
        done
    fi
done

echo ""

# Step 2: Check disk space
echo "========================================="
echo "Step 2: Checking disk space"
echo "========================================="
echo ""

echo "Calculating size of important files to recover..."
# Only count valid VM files
SIZE_BYTES=$(find "$SOURCE_DIR" \( -name "*.vdi" -o -name "*.vbox" -o -name "*.vbox-prev" -o -name "*.vmdk" -o -name "*.ovf" -o -name "*.nvram" \) -newermt "2010-01-01" -exec du -sb {} + 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$SIZE_BYTES" 2>/dev/null || echo "unknown")
echo "Size to recover (important files only): $SIZE_HUMAN"

AVAILABLE_BYTES=$(df -B1 "$RECOVERY_DIR" | tail -1 | awk '{print $4}')
AVAILABLE_HUMAN=$(numfmt --to=iec-i --suffix=B "$AVAILABLE_BYTES" 2>/dev/null || echo "unknown")
echo "Available space: $AVAILABLE_HUMAN"

if [ "$SIZE_BYTES" -gt "$AVAILABLE_BYTES" ]; then
    echo ""
    echo "⚠️  Warning: Not enough disk space!" >&2
    echo "   Required: $SIZE_HUMAN" >&2
    echo "   Available: $AVAILABLE_HUMAN" >&2
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Recovery cancelled by user"
        exit 0
    fi
fi

echo ""
read -p "Ready to start recovery. Press Enter to continue or Ctrl+C to cancel..."
echo ""

# Step 3: Recover files (skip corrupted logs)
echo "========================================="
echo "Step 3: Recovering files"
echo "========================================="
echo ""
echo "Strategy: Copy VM disk images and configuration files"
echo "          Skip corrupted log files"
echo ""

# Copy each VM
for vm_dir in "$SOURCE_DIR"/*; do
    if [ -d "$vm_dir" ]; then
        vm_name=$(basename "$vm_dir")
        echo "Processing VM: $vm_name"
        
        dest_vm_dir="$RECOVERY_DIR/$vm_name"
        mkdir -p "$dest_vm_dir"
        
        # Copy important files only (.vdi, .vbox, .vbox-prev, .vmdk, .ovf, .nvram)
        # Only copy files with dates after 2010 to avoid corrupted files
        echo "  Copying disk images..."
        find "$vm_dir" -maxdepth 1 -type f -name "*.vdi" -newermt "2010-01-01" 2>/dev/null | while read -r file; do
            echo "    $(basename "$file")"
            cp -v "$file" "$dest_vm_dir/" 2>&1 | sed 's/^/      /'
        done
        
        echo "  Copying configuration files..."
        find "$vm_dir" -maxdepth 1 -type f \( -name "*.vbox" -o -name "*.vbox-prev" \) -newermt "2010-01-01" 2>/dev/null | while read -r file; do
            echo "    $(basename "$file")"
            cp -v "$file" "$dest_vm_dir/" 2>&1 | sed 's/^/      /'
        done
        
        # Copy other important files if they exist
        for ext in vmdk ovf nvram; do
            find "$vm_dir" -maxdepth 1 -type f -name "*.$ext" -newermt "2010-01-01" 2>/dev/null | while read -r file; do
                echo "    $(basename "$file")"
                cp -v "$file" "$dest_vm_dir/" 2>&1 | sed 's/^/      /'
            done
        done
        
        # Copy Snapshots directory if it exists and is valid
        if [ -d "$vm_dir/Snapshots" ]; then
            echo "  Checking for snapshots..."
            snap_count=$(find "$vm_dir/Snapshots" -type f -name "*.vdi" -newermt "2010-01-01" 2>/dev/null | wc -l)
            if [ "$snap_count" -gt 0 ]; then
                echo "  Copying $snap_count snapshot(s)..."
                mkdir -p "$dest_vm_dir/Snapshots"
                find "$vm_dir/Snapshots" -type f -name "*.vdi" -newermt "2010-01-01" -exec cp -v {} "$dest_vm_dir/Snapshots/" \; 2>&1 | sed 's/^/    /'
            fi
        fi
        
        # Copy valid log files only (skip corrupted ones)
        if [ -d "$vm_dir/Logs" ]; then
            echo "  Checking for valid log files..."
            log_count=$(find "$vm_dir/Logs" -type f -name "*.log" -newermt "2010-01-01" 2>/dev/null | wc -l)
            if [ "$log_count" -gt 0 ]; then
                echo "  Copying $log_count valid log file(s)..."
                mkdir -p "$dest_vm_dir/Logs"
                find "$vm_dir/Logs" -type f -name "*.log" -newermt "2010-01-01" -exec cp -v {} "$dest_vm_dir/Logs/" \; 2>/dev/null | sed 's/^/    /' || true
            else
                echo "  No valid log files found (skipping corrupted logs)"
            fi
        fi
        
        echo ""
    fi
done

# Step 4: Fix ownership
echo "========================================="
echo "Step 4: Fixing file ownership"
echo "========================================="
echo ""

echo "Setting owner to: $REAL_USER:$REAL_USER"
chown -R "$REAL_USER:$REAL_USER" "$RECOVERY_DIR"
echo "✓ Ownership fixed"

# Step 5: Verify
echo ""
echo "========================================="
echo "Step 5: Verifying recovery"
echo "========================================="
echo ""

if [ -d "$RECOVERY_DIR" ] && [ "$(ls -A "$RECOVERY_DIR" 2>/dev/null)" ]; then
    echo "✓ Recovery successful!"
    echo ""
    echo "Recovered VMs:"
    ls -lh "$RECOVERY_DIR"
    echo ""
    
    # Show details for each VM
    for vm_dir in "$RECOVERY_DIR"/*; do
        if [ -d "$vm_dir" ]; then
            vm_name=$(basename "$vm_dir")
            echo "VM: $vm_name"
            vdi_count=$(find "$vm_dir" -name "*.vdi" 2>/dev/null | wc -l)
            vbox_count=$(find "$vm_dir" -name "*.vbox" 2>/dev/null | wc -l)
            echo "  VDI files: $vdi_count"
            echo "  Config files: $vbox_count"
            if command -v du >/dev/null 2>&1; then
                size=$(du -sh "$vm_dir" | cut -f1)
                echo "  Total size: $size"
            fi
            echo ""
        fi
    done
    
    if command -v du >/dev/null 2>&1; then
        RECOVERED_SIZE=$(du -sh "$RECOVERY_DIR" 2>/dev/null | cut -f1)
        echo "Total size recovered: $RECOVERED_SIZE"
    fi
    
    echo ""
    echo "Files recovered to: $RECOVERY_DIR"
else
    echo "✗ Warning: Recovery directory appears empty!" >&2
    exit 1
fi

echo ""
echo "========================================="
echo "=== RECOVERY COMPLETE ==="
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Verify the recovered VirtualBox VM files in: $RECOVERY_DIR"
echo "  2. Import VMs into VirtualBox:"
echo "     - Open VirtualBox"
echo "     - Machine → Add"
echo "     - Navigate to $RECOVERY_DIR"
echo "     - Select the .vbox file"
echo "  3. Test the imported VM to ensure it works"
echo ""
if [ -d "${RECOVERY_DIR}.bak" ]; then
    echo "Previous backup location: ${RECOVERY_DIR}.bak"
    echo ""
fi


