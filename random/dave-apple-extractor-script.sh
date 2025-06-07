#!/bin/bash
# =================================================================
# APPLE PHOTOS EXTRACTOR
# =================================================================
# This script extracts original image files from Apple Photos libraries,
# iPhone backups, and other Apple-specific formats, then organizes them
# in a standard folder structure for easy access in Linux.
#
# HOW TO USE:
# 1. Run after the initial backup is complete
# 2. Copy this script to your local machine
# 3. Run: ./extract_photos.sh YOUR_S3_BUCKET
# 
# The script will:
#  - Download relevant files from your S3 bucket
#  - Extract original photos from Apple formats
#  - Upload them to a new "extracted_photos" folder in your S3 bucket
#  - Organize photos by year/month
#  - Preserve metadata where possible
# =================================================================

# CONFIGURATION
S3_BUCKET="${1:-YOUR_S3_BUCKET_NAME}"  # Use command line arg or default value
LOG_PREFIX="LifeTimelineBackup"        # Same as in backup script
EXTRACT_PREFIX="extracted_photos"      # Where extracted photos will go
TEMP_DIR="/tmp/photo_extraction"       # Local temporary directory
LOG_FILE="/tmp/photo_extraction_log.txt"

# IMAGE FILE EXTENSIONS
IMAGE_EXTENSIONS=("jpg" "jpeg" "png" "gif" "tiff" "tif" "heic" "heif" "raw" "cr2" "nef" "arw" "dng")

# Create log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log "ERROR: AWS CLI not found. Please install it first."
    exit 1
fi

# Check bucket access
if ! aws s3 ls "s3://${S3_BUCKET}" &> /dev/null; then
    log "ERROR: Cannot access bucket '${S3_BUCKET}'. Check your AWS credentials."
    exit 1
fi

# Create working directories
mkdir -p "$TEMP_DIR"
mkdir -p "$TEMP_DIR/download"
mkdir -p "$TEMP_DIR/extracted"

# Check if backup is complete
log "Checking if backup is complete..."
if ! aws s3 ls "s3://${S3_BUCKET}/${LOG_PREFIX}/backup_completed" &> /dev/null; then
    log "WARNING: Backup completion marker not found. The backup may not be finished."
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Exiting. Please run this script after the backup is complete."
        exit 1
    fi
fi

# Function to extract original photos from Photos Library
extract_photos_library() {
    local library_path="$1"
    local extract_path="$2"
    
    log "Processing Photos Library at: $library_path"
    
    # Look for Masters or Originals folder (different macOS versions use different names)
    if [ -d "${library_path}/Masters" ]; then
        log "Found Masters folder (older Photos Library format)"
        cp -R "${library_path}/Masters/"* "$extract_path/"
    elif [ -d "${library_path}/Originals" ]; then
        log "Found Originals folder (newer Photos Library format)"
        cp -R "${library_path}/Originals/"* "$extract_path/"
    else
        log "WARNING: Could not find Masters or Originals folder in Photos Library"
        
        # Try alternative approach - search for image files recursively
        log "Searching for image files recursively in Photos Library..."
        
        for ext in "${IMAGE_EXTENSIONS[@]}"; do
            find "$library_path" -type f -iname "*.${ext}" -exec cp {} "$extract_path/" \;
        done
    fi
    
    # Count extracted files
    file_count=$(find "$extract_path" -type f | wc -l)
    log "Extracted $file_count files from Photos Library"
}

# Function to extract photos from iPhone backups
extract_iphone_backups() {
    local backup_path="$1"
    local extract_path="$2"
    
    log "Processing iPhone backup at: $backup_path"
    
    # Create a directory for extracted images
    mkdir -p "$extract_path/iphone_backup_photos"
    
    # Find all image files in the backup recursively
    for ext in "${IMAGE_EXTENSIONS[@]}"; do
        find "$backup_path" -type f -iname "*.${ext}" -exec cp {} "$extract_path/iphone_backup_photos/" \;
    done
    
    # Check for SQLite databases that might contain images
    log "Checking for media databases in iPhone backup..."
    
    # Look for Camera Roll database
    CAMERA_DB=$(find "$backup_path" -name "CameraRollDomain.sqlitedb" -o -name "Photos.sqlite" 2>/dev/null)
    
    if [ -n "$CAMERA_DB" ]; then
        log "Found camera database: $CAMERA_DB"
        # We'd need sqlite3 for more advanced extraction
        # For now, we'll just note its presence
    fi
    
    # Count extracted files
    file_count=$(find "$extract_path/iphone_backup_photos" -type f | wc -l)
    log "Extracted $file_count files from iPhone backup"
}

# Function to organize photos by date
organize_photos_by_date() {
    local source_dir="$1"
    local target_dir="$2"
    
    log "Organizing photos by date from: $source_dir"
    
    # Create organized directory structure
    mkdir -p "$target_dir"
    
    # Process each image file
    find "$source_dir" -type f | while read file; do
        # Get file extension
        filename=$(basename "$file")
        extension="${filename##*.}"
        
        # Skip non-image files
        if [[ ! " ${IMAGE_EXTENSIONS[*]} " =~ " ${extension,,} " ]]; then
            continue
        fi
        
        # Try to get creation date from EXIF data if available
        if command -v exiftool &> /dev/null; then
            # Use exiftool to get creation date
            date_taken=$(exiftool -DateTimeOriginal -d "%Y/%m" -s3 "$file" 2>/dev/null)
            
            if [ -z "$date_taken" ]; then
                # Fall back to file creation time
                date_taken=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1 | sed 's/-/\//g' | cut -d'/' -f1,2)
            fi
        else
            # Fall back to file creation time
            date_taken=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1 | sed 's/-/\//g' | cut -d'/' -f1,2)
        fi
        
        # If still no date, put in "unknown" folder
        if [ -z "$date_taken" ]; then
            date_taken="unknown"
        fi
        
        # Create target directory
        mkdir -p "${target_dir}/${date_taken}"
        
        # Copy file to organized location
        cp "$file" "${target_dir}/${date_taken}/"
    done
    
    # Count organized files
    file_count=$(find "$target_dir" -type f | wc -l)
    log "Organized $file_count files by date"
}

# Main process - Download Photos Library from S3
log "Starting extraction process..."

# Check if Photos Library exists in S3
log "Checking for Photos Library in S3 bucket..."
if aws s3 ls "s3://${S3_BUCKET}/${LOG_PREFIX}/PhotosLibrary/" &> /dev/null; then
    log "Found Photos Library in S3. Downloading masters folder only..."
    
    # Check for Masters or Originals folder
    if aws s3 ls "s3://${S3_BUCKET}/${LOG_PREFIX}/PhotosLibrary/Masters/" &> /dev/null; then
        aws s3 sync "s3://${S3_BUCKET}/${LOG_PREFIX}/PhotosLibrary/Masters/" "$TEMP_DIR/download/PhotosLibrary/Masters/"
    elif aws s3 ls "s3://${S3_BUCKET}/${LOG_PREFIX}/PhotosLibrary/Originals/" &> /dev/null; then
        aws s3 sync "s3://${S3_BUCKET}/${LOG_PREFIX}/PhotosLibrary/Originals/" "$TEMP_DIR/download/PhotosLibrary/Originals/"
    else
        log "WARNING: Could not find Masters or Originals folder. Downloading entire Photos Library (this might take a while)..."
        aws s3 sync "s3://${S3_BUCKET}/${LOG_PREFIX}/PhotosLibrary/" "$TEMP_DIR/download/PhotosLibrary/"
    fi
    
    # Extract photos from Photos Library
    extract_photos_library "$TEMP_DIR/download/PhotosLibrary" "$TEMP_DIR/extracted/from_photos_library"
else
    log "No Photos Library found in S3 bucket."
fi

# Check for iPhone backups
log "Checking for iPhone backups in S3 bucket..."
if aws s3 ls "s3://${S3_BUCKET}/${LOG_PREFIX}/DeviceBackups/" &> /dev/null; then
    log "Found iPhone backups in S3. Downloading..."
    aws s3 sync "s3://${S3_BUCKET}/${LOG_PREFIX}/DeviceBackups/" "$TEMP_DIR/download/DeviceBackups/"
    
    # Extract photos from iPhone backups
    extract_iphone_backups "$TEMP_DIR/download/DeviceBackups" "$TEMP_DIR/extracted/from_iphone_backups"
else
    log "No iPhone backups found in S3 bucket."
fi

# Check for Photos in DCIM folder
log "Checking for DCIM folder in S3 bucket..."
if aws s3 ls "s3://${S3_BUCKET}/${LOG_PREFIX}/DCIM/" &> /dev/null; then
    log "Found DCIM folder in S3. Downloading..."
    aws s3 sync "s3://${S3_BUCKET}/${LOG_PREFIX}/DCIM/" "$TEMP_DIR/extracted/from_dcim/"
else
    log "No DCIM folder found in S3 bucket."
fi

# Organize all extracted photos by date
log "Organizing all extracted photos by date..."
mkdir -p "$TEMP_DIR/organized"
organize_photos_by_date "$TEMP_DIR/extracted" "$TEMP_DIR/organized"

# Upload organized photos back to S3
log "Uploading organized photos to S3..."
aws s3 sync "$TEMP_DIR/organized/" "s3://${S3_BUCKET}/${EXTRACT_PREFIX}/"

# Create a summary file
SUMMARY_FILE="$TEMP_DIR/photo_extraction_summary.txt"
echo "===== PHOTO EXTRACTION SUMMARY =====" > "$SUMMARY_FILE"
echo "Date: $(date)" >> "$SUMMARY_FILE"
echo "S3 Bucket: ${S3_BUCKET}" >> "$SUMMARY_FILE"
echo "Original data: s3://${S3_BUCKET}/${LOG_PREFIX}/" >> "$SUMMARY_FILE"
echo "Extracted photos: s3://${S3_BUCKET}/${EXTRACT_PREFIX}/" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

total_extracted=$(find "$TEMP_DIR/organized" -type f | wc -l)
echo "Total photos extracted: $total_extracted" >> "$SUMMARY_FILE"

# List photo counts by folder
echo "" >> "$SUMMARY_FILE"
echo "Photos by date folder:" >> "$SUMMARY_FILE"
find "$TEMP_DIR/organized" -type d | while read dir; do
    if [ "$dir" != "$TEMP_DIR/organized" ]; then
        count=$(find "$dir" -type f | wc -l)
        if [ $count -gt 0 ]; then
            echo "- ${dir#$TEMP_DIR/organized/}: $count photos" >> "$SUMMARY_FILE"
        fi
    fi
done

# Upload summary to S3
aws s3 cp "$SUMMARY_FILE" "s3://${S3_BUCKET}/${EXTRACT_PREFIX}/extraction_summary.txt"

# Create completion marker
echo "Extraction completed on $(date)" > "$TEMP_DIR/extraction_completed"
aws s3 cp "$TEMP_DIR/extraction_completed" "s3://${S3_BUCKET}/${EXTRACT_PREFIX}/extraction_completed"

log "Photo extraction complete! Photos are organized in: s3://${S3_BUCKET}/${EXTRACT_PREFIX}/"
log "You can access the extraction summary at: s3://${S3_BUCKET}/${EXTRACT_PREFIX}/extraction_summary.txt"

# Cleanup
read -p "Clean up temporary files? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    log "Cleanup complete."
else
    log "Temporary files kept at: $TEMP_DIR"
fi

log "Process completed successfully."
