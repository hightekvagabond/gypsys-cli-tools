# VirtualBox VM Recovery Scripts

## Overview

These scripts help recover VirtualBox VMs from a backup disk that may contain corrupted files. The scripts are designed to:
- **Only write to the `tmp/` directory** within this folder
- Filter out corrupted files (identified by dates before 2010)
- Only copy essential VM files (.vdi, .vbox) to save space
- Skip the massive amount of corrupted log files

## Important: Disk Space

### Source VM Analysis
- **Source location:** `/media/gypsy/14d5b2d9-68a9-4444-85a1-c98a3e01122f/Backup/VirtualBox VMs/`
- **VM found:** CentOS 6
- **Total directory size:** 1.8TB (mostly corrupted log files)
- **Actual VM data:** ~18GB (fits in available space)
  - CentOS 6-disk002.vdi: 18GB
  - CentOS 6.vbox: 13KB
  - CentOS 6.vbox-prev: 13KB
  - Logs/: 1.8TB (corrupted files with dates from 1902-2018, will be filtered out)

### Your Current Disk Space
- **Available:** 32GB free on /dev/nvme0n1p5
- **Required:** ~18GB for VM recovery
- **Status:** ✅ Sufficient space when using the recovery script (which filters out corrupted files)

## Scripts

### 1. `recover-from-backup.sh` - Main Recovery Script

**Purpose:** Recovers VirtualBox VMs from the backup disk, filtering out corrupted files.

**Usage:**
```bash
sudo ./recover-from-backup.sh
```

**What it does:**
1. Analyzes the source directory
2. Checks disk space requirements (only counts valid files)
3. Copies only essential files:
   - .vdi (disk images)
   - .vbox (VM configuration)
   - .vbox-prev (backup configuration)
   - Valid snapshots (if any)
   - Valid log files only (skips corrupted ones)
4. Filters files: Only copies files with dates after 2010 (skips corrupted files)
5. Saves everything to `./tmp/` directory
6. Fixes file ownership back to your user

**Output:** VMs recovered to `./tmp/`

### 2. `fix-vbox-remove-snapshot.sh` - Fix Snapshot Issues

**Purpose:** Removes broken snapshot references from .vbox files.

**Usage:**
```bash
sudo ./fix-vbox-remove-snapshot.sh
```

**What it does:**
1. Creates a backup of the original .vbox file
2. Removes broken snapshot references using Python XML parsing
3. Updates the configuration to use the base disk
4. Allows the VM to start without snapshot errors

**Note:** This script is pre-configured for the CentOS 6 VM snapshot issue. Edit the SNAPSHOT_GUID variable if you have different snapshot issues.

### 3. `1-recover-vms.sh` - Quick Start Script

**Purpose:** Convenience script to start the recovery process.

**Usage:**
```bash
./1-recover-vms.sh
```

**What it does:** Calls the main recovery script with proper parameters.

### 4. `2-fix-vbox-config.sh` - Quick Fix Script

**Purpose:** Convenience script to fix VirtualBox configurations.

**Usage:**
```bash
./2-fix-vbox-config.sh
```

**What it does:** Calls the snapshot fix script with proper parameters.

## Recovery Workflow

### Step 1: Recover VMs
```bash
cd /home/gypsy/dev/stable-dev/gypsys-cli-tools/diskrecover
sudo ./recover-from-backup.sh
```

This will:
- Copy the CentOS 6 VM (18GB) to `./tmp/CentOS 6/`
- Skip all corrupted log files (saving 1.8TB of space!)
- Take approximately 5-10 minutes depending on disk speed

### Step 2: Verify Recovery
```bash
ls -lh ./tmp/
ls -lh "./tmp/CentOS 6/"
```

Expected files:
- `CentOS 6-disk002.vdi` (18GB)
- `CentOS 6.vbox` (13KB)
- `CentOS 6.vbox-prev` (13KB)
- `Logs/` (only valid log files)

### Step 3: Fix Configuration (if needed)
If you encounter snapshot errors when importing the VM:
```bash
sudo ./fix-vbox-remove-snapshot.sh
```

### Step 4: Import into VirtualBox
1. Open VirtualBox
2. Machine → Add
3. Navigate to `./tmp/CentOS 6/`
4. Select `CentOS 6.vbox`
5. Click "Open"
6. Test the VM

### Step 5: Cleanup (after successful import)
Once you've verified the VM works in VirtualBox:
```bash
# The VM is now in VirtualBox's directory, safe to clean up
rm -rf ./tmp/
```

## Safety Features

### All scripts write ONLY to `./tmp/` directory
- The RECOVERY_DIR variable is set to `${SCRIPT_DIR}/tmp`
- No files are written to system directories
- No files are written outside the diskrecover folder
- Root ownership is changed back to your user automatically

### Corrupted File Filtering
- Uses `-newermt "2010-01-01"` to filter out corrupted files
- Skips files with invalid dates (1902, 1939, 1982, etc.)
- Only copies files that are likely valid

### Disk Space Checking
- Calculates required space before starting
- Warns you if there's not enough space
- Only counts valid files (not corrupted logs)

### Backup and Safety
- Creates backups before modifying .vbox files
- Shows confirmation prompts before major operations
- Can be safely interrupted with Ctrl+C

## Troubleshooting

### Disk Full Error
If you still run out of space:
1. Check what's using space: `du -sh ./tmp/`
2. The recovery should only use ~18GB
3. If more space is needed, clean up other directories first

### Permission Denied
All recovery scripts need sudo because:
- Source files are owned by root
- Need to copy files with proper permissions
- Will fix ownership back to your user at the end

### VM Won't Start
1. Try the fix-vbox-remove-snapshot.sh script
2. Check VirtualBox logs for specific errors
3. Verify the .vdi file is valid: `file "./tmp/CentOS 6/CentOS 6-disk002.vdi"`

### Missing Files
The recovery script only copies:
- Essential VM files (.vdi, .vbox)
- Valid configuration files
- Valid snapshots
- Valid log files (corrupted logs are skipped)

This is intentional to save space and time!

## Technical Details

### Source Backup Location
```
/media/gypsy/14d5b2d9-68a9-4444-85a1-c98a3e01122f/Backup/VirtualBox VMs/
└── CentOS 6/
    ├── CentOS 6-disk002.vdi (18GB)
    ├── CentOS 6.vbox (13KB)
    ├── CentOS 6.vbox-prev (13KB)
    └── Logs/ (1.8TB of mostly corrupted files)
```

### Recovery Destination
```
./tmp/
└── CentOS 6/
    ├── CentOS 6-disk002.vdi (18GB)
    ├── CentOS 6.vbox (13KB)
    ├── CentOS 6.vbox-prev (13KB)
    └── Logs/ (only valid log files, ~1MB)
```

### Why the Logs Directory is So Large
The source Logs directory contains massive amounts of corrupted data:
- Files with dates from 1902, 1907, 1939, 1982, 1994, etc.
- Filenames with corrupted Unicode characters
- Many 0-byte files
- Only a few valid log files from 2024-2025

The recovery script filters these out automatically!

## Notes

- The backup disk is mounted at: `/media/gypsy/14d5b2d9-68a9-4444-85a1-c98a3e01122f/`
- The backup disk is 100% full (3.6TB used)
- The recovery destination (your main drive) has 32GB free
- Recovery will use about 18GB of that 32GB available space
- After importing to VirtualBox, you can delete the `./tmp/` directory

## History

This recovery was needed because:
1. Backup disk contains VirtualBox VMs with some file corruption
2. Need to recover CentOS 6 VM to a working system
3. Original Logs directory has 1.8TB of corrupted data
4. Limited disk space on destination (32GB free)
5. Solution: Smart recovery that filters corrupted files and only copies essential VM data

## Author

Scripts created during VM recovery session on November 5-6, 2025.


