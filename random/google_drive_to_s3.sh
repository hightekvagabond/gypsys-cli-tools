#!/bin/bash

# Script to copy contents from Google Drive folder to S3 bucket
# Usage: ./google_drive_to_s3.sh <aws_profile> <s3_bucket_path>

# Check if required parameters are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <aws_profile> <s3_bucket_path>"
    echo "Example: $0 my-aws-profile s3://my-bucket/my-folder/"
    exit 1
fi

# Assign parameters to variables
AWS_PROFILE="$1"
S3_BUCKET_PATH="$2"

# Create a temporary directory to store files from Google Drive
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: $TEMP_DIR"

# Clean up function to remove temporary directory on exit
cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Starting transfer process..."
echo "AWS Profile: $AWS_PROFILE"
echo "S3 Destination: $S3_BUCKET_PATH"

# Download files from Google Drive folder to the temporary directory
echo "Downloading files from Google Drive..."
if ! rclone copy "gdrive:" "$TEMP_DIR" --progress; then
    echo "Error: Failed to download files from Google Drive."
    exit 1
fi

# Count the number of files downloaded
FILE_COUNT=$(find "$TEMP_DIR" -type f | wc -l)
echo "Downloaded $FILE_COUNT files from Google Drive."

# Upload files to S3 bucket using the specified AWS profile
echo "Uploading files to S3 bucket..."
if ! aws --profile "$AWS_PROFILE" s3 cp "$TEMP_DIR/" "$S3_BUCKET_PATH" --recursive; then
    echo "Error: Failed to upload files to S3 bucket."
    exit 1
fi

echo "Transfer completed successfully!"
echo "Files have been copied from Google Drive folder to $S3_BUCKET_PATH"
exit 0
