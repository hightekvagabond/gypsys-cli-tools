#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting extension rebuild process...${NC}"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_EXTENSION_DIR="$SCRIPT_DIR/cursor-git-extension"

# Check if source extension directory exists
if [ ! -d "$SOURCE_EXTENSION_DIR" ]; then
    echo -e "${RED}Source extension directory not found: $SOURCE_EXTENSION_DIR${NC}"
    exit 1
fi

# Kill any running Cursor instances
echo -e "${YELLOW}Killing any running Cursor instances...${NC}"
pkill -f Cursor || true

# Wait a moment for processes to clean up
sleep 2

# Navigate to source extension directory
cd "$SOURCE_EXTENSION_DIR"

# Verify package.json
echo -e "${YELLOW}Verifying package.json...${NC}"
if ! grep -q '"activationEvents": \[".*"\]' package.json; then
    echo -e "${RED}Adding activation events to package.json...${NC}"
    # Add activation events if missing
    sed -i 's/"activationEvents": \[\]/"activationEvents": ["*"]/' package.json
fi

# Clean the extension
echo -e "${YELLOW}Cleaning extension...${NC}"
rm -rf out/
rm -rf node_modules/
rm -f debug.log
npm install

# Rebuild the extension
echo -e "${YELLOW}Rebuilding extension...${NC}"
npm run compile

# Check if compilation was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Compilation failed!${NC}"
    exit 1
fi

# Find the installed extension directory
INSTALLED_EXTENSION_DIR=$(find ~/.cursor/extensions/ -name "*cursor-git-extension*" -type d | head -1)

if [ -n "$INSTALLED_EXTENSION_DIR" ]; then
    echo -e "${YELLOW}Found installed extension at: $INSTALLED_EXTENSION_DIR${NC}"
    echo -e "${YELLOW}Copying compiled files to installed extension...${NC}"
    
    # Copy the compiled files
    cp -r out/ "$INSTALLED_EXTENSION_DIR/"
    cp package.json "$INSTALLED_EXTENSION_DIR/"
    
    echo -e "${GREEN}Extension files updated successfully!${NC}"
else
    echo -e "${YELLOW}No installed extension found, reinstalling...${NC}"
    # Navigate back to cursor directory and reinstall
    cd "$SCRIPT_DIR"
    ./install-cursor-extension.sh
fi

echo -e "${GREEN}Extension rebuild complete!${NC}"
echo -e "${YELLOW}You can now start Cursor. The extension should be active.${NC}"

# Instructions for checking logs
if [ -n "$INSTALLED_EXTENSION_DIR" ]; then
    echo -e "${YELLOW}Check the debug log at:${NC}"
    echo -e "${GREEN}$INSTALLED_EXTENSION_DIR/debug.log${NC}" 
fi 