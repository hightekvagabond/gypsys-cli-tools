#!/bin/bash

# Windows Repair Kit - Thumb Drive Setup Script
# This will format your thumb drive and set up the repair kit structure

set -e  # Exit on error

echo "=========================================="
echo "Windows Repair Kit - Setup Script"
echo "=========================================="
echo ""

# Get the username of the person running the script
CURRENT_USER=$(whoami)
USER_MEDIA_PATH="/media/$CURRENT_USER"

echo "Running as user: $CURRENT_USER"
echo "Media path: $USER_MEDIA_PATH"
echo ""

# Detect the USB drive - look for any mounted USB device in user's media directory
echo "Detecting USB drive..."
USB_MOUNT=$(find "$USER_MEDIA_PATH" -maxdepth 1 -type d ! -path "$USER_MEDIA_PATH" 2>/dev/null | head -n 1)

if [ -z "$USB_MOUNT" ]; then
    echo "Error: Could not detect any USB drive mounted in $USER_MEDIA_PATH"
    echo "Please make sure your USB drive is plugged in and mounted"
    echo ""
    echo "Available mounts:"
    ls -la "$USER_MEDIA_PATH" 2>/dev/null || echo "  None found"
    exit 1
fi

# Get the device from the mount point
USB_PARTITION=$(df "$USB_MOUNT" | tail -1 | awk '{print $1}')
USB_DEVICE=$(echo "$USB_PARTITION" | sed 's/[0-9]*$//')

echo "Found USB drive mounted at: $USB_MOUNT"
echo "Device: $USB_DEVICE"
echo "Partition: $USB_PARTITION"
echo ""

# Check current filesystem
CURRENT_FS=$(lsblk -no FSTYPE "$USB_PARTITION")
echo "Current filesystem: $CURRENT_FS"
echo ""

# Ask if they want to format
if [ "$CURRENT_FS" = "exfat" ]; then
    echo "✓ Drive is already formatted as exFAT"
    read -p "Do you want to reformat anyway? (type YES to reformat, anything else to skip): " format_confirm
    
    if [ "$format_confirm" != "YES" ]; then
        echo "Skipping format, using existing filesystem..."
        SKIP_FORMAT=true
        SKIP_REMOUNT=true
        DRIVE_PATH="$USB_MOUNT"
    else
        SKIP_FORMAT=false
        SKIP_REMOUNT=false
    fi
else
    echo "⚠️  Drive is formatted as: $CURRENT_FS (not exFAT)"
    echo "⚠️  WARNING: This will FORMAT the drive at: $USB_PARTITION"
    echo "⚠️  ALL DATA will be ERASED!"
    echo ""
    read -p "Format to exFAT? (type YES to proceed): " format_confirm
    
    if [ "$format_confirm" != "YES" ]; then
        echo "Aborted."
        exit 0
    fi
    SKIP_FORMAT=false
    SKIP_REMOUNT=false
fi

if [ "$SKIP_FORMAT" = false ]; then
    echo ""
    echo "Proceeding with format..."
    echo ""
    
    # Unmount if mounted
    echo "Unmounting drive..."
    sudo umount "$USB_MOUNT" 2>/dev/null || true
    sudo umount "$USB_PARTITION" 2>/dev/null || true
    
    # Format to exFAT
    echo "Formatting to exFAT..."
    sudo mkfs.exfat -n WINREPAIR "$USB_PARTITION"
    
    # Wait for the system to recognize it
    sleep 2
fi

# Only remount if we formatted or if it wasn't already mounted properly
if [ "$SKIP_REMOUNT" = false ]; then
    # Unmount to ensure clean state
    sudo umount "$USB_MOUNT" 2>/dev/null || true
    sudo umount "$USB_PARTITION" 2>/dev/null || true
    
    # Mount it properly with a subdirectory
    echo "Mounting drive..."
    MOUNT_POINT="$USER_MEDIA_PATH/WINREPAIR"
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount "$USB_PARTITION" "$MOUNT_POINT"
    
    # Wait a moment
    sleep 1
    
    # Fix permissions - make it writable by the user
    sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$MOUNT_POINT"
    sudo chmod -R 755 "$MOUNT_POINT"
    
    DRIVE_PATH="$MOUNT_POINT"
    
    echo ""
    echo "✓ Drive mounted at: $DRIVE_PATH"
fi
echo ""
echo "Setting up Windows Repair Kit structure..."
echo ""

# Create folder structure
echo "Creating folders..."
mkdir -p "$DRIVE_PATH/1-ANTIVIRUS"
mkdir -p "$DRIVE_PATH/2-CLEANUP"
mkdir -p "$DRIVE_PATH/3-SYSTEM-TOOLS"
mkdir -p "$DRIVE_PATH/4-ADVANCED"

# Copy README
echo "Creating README..."
cat > "$DRIVE_PATH/README.txt" << 'EOFREADME'
# Windows Repair Kit - Thumb Drive

## What's On This Drive

This is a portable Windows cleanup and repair toolkit. Use when dealing with infected or slow Windows machines.

---

## Download Links

### Antivirus/Malware Removal

1. **Malwarebytes Free**
   - Download: https://www.malwarebytes.com/mwb-download/
   - File: `MBSetup.exe` (~100MB)
   - What it does: Primary malware scanner and remover

2. **HitmanPro**
   - Download: https://www.hitmanpro.com/en-us/downloads
   - File: `HitmanPro_x64.exe` (~12MB)
   - What it does: Cloud-based scanner, catches what others miss (30-day free trial)

3. **AVG AntiVirus Free**
   - Download: https://www.avg.com/en-us/free-antivirus-download
   - File: `AVG_Antivirus_Free_Setup.exe`
   - What it does: Traditional antivirus, can install for ongoing protection

### Cleanup Tools

5. **BleachBit**
   - Download: https://www.bleachbit.org/download/windows
   - File: `BleachBit-portable.zip` (~15MB)
   - What it does: Open source disk cleaner, removes junk files
   - Note: Get the PORTABLE version

6. **CCleaner Free**
   - Download: https://www.ccleaner.com/ccleaner/download/standard
   - File: `ccsetup.exe` (~50MB)
   - What it does: Disk cleanup and registry cleaner
   - Warning: Decline any bundled software during install

### System Analysis Tools

7. **Autoruns** (Microsoft Sysinternals)
   - Download: https://download.sysinternals.com/files/Autoruns.zip
   - File: `Autoruns.zip` (~2MB)
   - What it does: Shows everything that starts with Windows
   - Note: No installation needed, just extract and run

8. **Process Explorer** (Microsoft Sysinternals)
   - Download: https://download.sysinternals.com/files/ProcessExplorer.zip
   - File: `ProcessExplorer.zip` (~2MB)
   - What it does: Advanced task manager replacement
   - Note: No installation needed, just extract and run

### Advanced (Optional)

9. **Tron Script**
   - Download: https://old.reddit.com/r/TronScript/
   - Look for the latest release thread (changes monthly)
   - File: `Tron vX.X.X.exe` (~500MB)
   - What it does: Automated cleanup script that runs many tools sequentially
   - Warning: Takes 2-6 hours to run, very thorough
   - Note: Read the documentation before using

10. **Revo Uninstaller Free**
    - Download: https://www.revouninstaller.com/start-freeware-download/
    - File: `revosetup.exe` (~7MB)
    - What it does: Completely remove stubborn programs

---

## Folder Structure on Thumb Drive

```
WINREPAIR/
├── README.txt (this file)
├── 1-ANTIVIRUS/
│   ├── MBSetup.exe
│   ├── KVRT.exe
│   ├── HitmanPro_x64.exe
│   └── AVG_Antivirus_Free_Setup.exe
├── 2-CLEANUP/
│   ├── BleachBit-portable.zip
│   └── ccsetup.exe
├── 3-SYSTEM-TOOLS/
│   ├── Autoruns.zip
│   └── ProcessExplorer.zip
└── 4-ADVANCED/
    ├── Tron vX.X.X.exe
    └── revosetup.exe
```

---

## Usage Instructions

### STEP 0: Boot into Safe Mode

**Method 1 - Shift + Restart (easiest):**
1. Hold Shift key
2. Click Start → Power → Restart (keep holding Shift)
3. At blue screen: Troubleshoot → Advanced Options → Startup Settings → Restart
4. Press F5 for "Safe Mode with Networking"

**Method 2 - Force it:**
1. Power on PC and force shutdown (hold power button) as Windows loads
2. Do this 2-3 times until Windows enters recovery mode automatically
3. Navigate: Troubleshoot → Advanced Options → Startup Settings → Restart
4. Press F5 for "Safe Mode with Networking"

### STEP 1: Run Malwarebytes (Primary Scan)

1. Run `1-ANTIVIRUS/MBSetup.exe`
2. Install (takes a few minutes)
3. Let it update definitions
4. Click "Scan" and wait (30-60 minutes typical)
5. Quarantine/Remove everything it finds
6. Restart if prompted

### STEP 2: Run Second Opinion Scanner

- **HitmanPro**: Run `1-ANTIVIRUS/HitmanPro_x64.exe` - 30 day free trial

Let it scan and remove anything found.

### STEP 3: Clean Up Junk Files

**Option A - BleachBit (recommended):**
1. Extract `2-CLEANUP/BleachBit-portable.zip`
2. Run `bleachbit.exe`
3. Check boxes for things to clean (stick to standard items)
4. Click "Clean"

**Option B - CCleaner:**
1. Run `2-CLEANUP/ccsetup.exe`
2. Install (DECLINE any bundled offers)
3. Go to "Cleaner" tab, click "Analyze" then "Run Cleaner"
4. Optional: Go to "Registry" tab, scan and fix issues

### STEP 4: Check Startup Items

1. Extract `3-SYSTEM-TOOLS/Autoruns.zip`
2. Run `Autoruns.exe` (or `Autoruns64.exe` for 64-bit)
3. Right-click → "Run as administrator"
4. Look for suspicious entries (unfamiliar names, misspellings)
5. Uncheck suspicious items to disable them
6. Don't disable things you recognize as Windows components

### STEP 5: Reboot Normally

1. Restart the computer normally (not Safe Mode)
2. Test everything works
3. Run `3-SYSTEM-TOOLS/ProcessExplorer.exe` to monitor what's running

---

## Advanced Options

### If Still Having Problems:

**Run Tron Script:**
- WARNING: This takes 2-6 hours
- Boot to Safe Mode
- Run `4-ADVANCED/Tron vX.X.X.exe` as administrator
- Let it run completely
- It will restart multiple times
- Visit r/TronScript for documentation

**Remove Stubborn Programs:**
- Run `4-ADVANCED/revosetup.exe`
- Install and use to fully remove problematic software

---

## Quick Reference Card

**Problem: Computer is slow**
→ Safe Mode → Malwarebytes → BleachBit → Autoruns

**Problem: Popup ads everywhere**
→ Safe Mode → Malwarebytes → HitmanPro → Autoruns

**Problem: Can't remove a program**
→ Normal Mode → Revo Uninstaller

**Problem: Everything is terrible**
→ Safe Mode → Tron Script (set it and forget it)

---

## Tips

- Always run scans in Safe Mode when possible
- "Safe Mode with Networking" (F5) lets tools update their definitions
- If one scanner finds nothing, try another - they catch different things
- Back up important files BEFORE running cleanup tools
- Some malware prevents booting to Safe Mode - if that happens, try multiple times or use installation media
- Update Windows after cleaning (Settings → Update & Security → Windows Update)

---

## Maintenance Schedule for the User

**Monthly:**
- Run Windows Update
- Run Malwarebytes scan
- Run BleachBit cleanup

**As Needed:**
- Check Autoruns if computer slows down
- Run full scan if suspicious behavior

---

## Notes

- All tools are free or have free versions
- Download fresh versions periodically (malware definitions change)
- This drive was created: [DATE]
- Last updated: [DATE]

---

## When to Give Up and Reinstall Windows

If after all this the computer is still:
- Running extremely slow
- Constantly getting reinfected
- Showing BSOD (Blue Screen of Death) errors
- Critical Windows files are corrupted

→ Time for a fresh Windows install or professional help

---

## Emergency Contacts

If you need help:
- Reddit r/techsupport
- Malwarebytes Forums
- BleachBit Forums

---

**Remember: This is for helping friends and family. You're a CTO, not a professional Windows repair person. Do what you can, but know when to hand it off.**
EOFREADME

# Create a download checklist
cat > "$DRIVE_PATH/DOWNLOAD_CHECKLIST.txt" << 'EOF'
DOWNLOAD CHECKLIST FOR WINDOWS REPAIR KIT
==========================================

Download these files and place them in the appropriate folders:

[ ] 1-ANTIVIRUS/MBSetup.exe
    https://www.malwarebytes.com/mwb-download/thankyou

[ ] 1-ANTIVIRUS/HitmanPro_x64.exe
    https://www.hitmanpro.com/en-us/downloads

[ ] 1-ANTIVIRUS/AVG_Antivirus_Free_Setup.exe
    https://www.avg.com/en-us/free-antivirus-download

[ ] 2-CLEANUP/BleachBit-portable.zip (GET PORTABLE VERSION)
    https://www.bleachbit.org/download/windows

[ ] 2-CLEANUP/ccsetup.exe
    https://www.ccleaner.com/ccleaner/download/standard

[ ] 3-SYSTEM-TOOLS/Autoruns.zip
    https://download.sysinternals.com/files/Autoruns.zip

[ ] 3-SYSTEM-TOOLS/ProcessExplorer.zip
    https://download.sysinternals.com/files/ProcessExplorer.zip

[ ] 4-ADVANCED/Tron (see Reddit r/TronScript for latest)
    https://old.reddit.com/r/TronScript/

[ ] 4-ADVANCED/revosetup.exe
    https://www.revouninstaller.com/start-freeware-download/

NOTES:
- You can download these directly on your Ubuntu machine
- Most will download as .exe files which is fine
- Just save them to the appropriate folders on the thumb drive
- Total size needed: ~1.5-2 GB
EOF

# Create a quick start guide
cat > "$DRIVE_PATH/QUICK_START.txt" << 'EOF'
WINDOWS REPAIR KIT - QUICK START
=================================

1. Boot Windows into Safe Mode (Hold Shift + Restart)
2. Navigate to Troubleshoot > Advanced Options > Startup Settings > Restart
3. Press F5 for "Safe Mode with Networking"

4. Run scans in this order:
   - 1-ANTIVIRUS/MBSetup.exe (install and scan)
   - 1-ANTIVIRUS/KVRT.exe (scan)
   
5. Clean up:
   - Extract and run 2-CLEANUP/BleachBit-portable.zip
   
6. Check startup:
   - Extract and run 3-SYSTEM-TOOLS/Autoruns.zip

7. Restart normally

See README.txt for detailed instructions.
EOF

echo ""
echo "✓ Folder structure created"
echo "✓ README.txt copied"
echo "✓ DOWNLOAD_CHECKLIST.txt created"
echo "✓ QUICK_START.txt created"
echo ""
echo "================================================"
echo "Thumb drive setup complete!"
echo "================================================"
echo ""
echo "Drive is mounted at: $DRIVE_PATH"
echo ""
echo "Next steps:"
echo "1. Open DOWNLOAD_CHECKLIST.txt on the thumb drive"
echo "2. Download each tool (links provided)"
echo "3. Place files in their respective folders"
echo "4. Keep this drive for emergencies"
echo ""
echo "To unmount safely when done:"
echo "  sudo umount $DRIVE_PATH"
echo ""
