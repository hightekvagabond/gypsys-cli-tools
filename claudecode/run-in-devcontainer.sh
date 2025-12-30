#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory to work in (default to current directory)
WORK_DIR="${1:-.}"
WORK_DIR=$(realpath "$WORK_DIR")

echo -e "${GREEN}Checking for devcontainer in: $WORK_DIR${NC}"

# Check if .devcontainer folder exists
if [ ! -d "$WORK_DIR/.devcontainer" ]; then
    echo -e "${RED}Error: .devcontainer folder not found in $WORK_DIR${NC}"
    exit 1
fi

# Check if devcontainer.json exists
if [ ! -f "$WORK_DIR/.devcontainer/devcontainer.json" ]; then
    echo -e "${RED}Error: devcontainer.json not found in $WORK_DIR/.devcontainer/${NC}"
    exit 1
fi

# Check if Dockerfile exists
if [ ! -f "$WORK_DIR/.devcontainer/Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found in $WORK_DIR/.devcontainer/${NC}"
    exit 1
fi

# Get Claude Code config files/directories
CLAUDE_CONFIG_JSON="${HOME}/.claude.json"
CLAUDE_CONFIG_DIR="${HOME}/.claude"

# Check for Claude config
if [ ! -f "$CLAUDE_CONFIG_JSON" ] && [ ! -d "$CLAUDE_CONFIG_DIR" ]; then
    echo -e "${RED}Error: Claude Code config not found. Please run 'claude' once to authenticate.${NC}"
    exit 1
fi

# Find Claude Code binary on host
CLAUDE_BIN=$(which claude 2>/dev/null || echo "")
if [ -z "$CLAUDE_BIN" ]; then
    echo -e "${RED}Error: Claude Code binary not found on host. Please install Claude Code first.${NC}"
    exit 1
fi
echo -e "${GREEN}Found Claude Code at: $CLAUDE_BIN${NC}"

# Generate a unique container name based on the project directory
PROJECT_NAME=$(basename "$WORK_DIR")
CONTAINER_NAME="claudecode-${PROJECT_NAME}"
IMAGE_NAME="claudecode-devcontainer-${PROJECT_NAME}"

echo -e "${GREEN}Building devcontainer image: $IMAGE_NAME${NC}"

# Create a temporary Dockerfile that extends the devcontainer Dockerfile
TEMP_DOCKERFILE=$(mktemp)
trap "rm -f $TEMP_DOCKERFILE" EXIT

# Build the devcontainer image
echo -e "${GREEN}Building devcontainer image...${NC}"
docker build -t "$IMAGE_NAME" -f "$WORK_DIR/.devcontainer/Dockerfile" "$WORK_DIR/.devcontainer" || {
    # If context is wrong, try using the parent directory
    docker build -t "$IMAGE_NAME" -f "$WORK_DIR/.devcontainer/Dockerfile" "$WORK_DIR"
}

# Stop and remove existing container if it exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${YELLOW}Removing existing container: $CONTAINER_NAME${NC}"
    docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true
fi

# Parse devcontainer.json for additional mounts and settings
# Expand VS Code devcontainer variables to Docker mount format
EXTRA_MOUNTS=""
if command -v jq > /dev/null 2>&1; then
    # Try to extract mounts from devcontainer.json if jq is available
    MOUNTS=$(jq -r '.mounts[]? | select(. != null)' "$WORK_DIR/.devcontainer/devcontainer.json" 2>/dev/null || echo "")
    if [ -n "$MOUNTS" ]; then
        while IFS= read -r mount; do
            # Expand environment variables in the mount string
            # ${env:HOME} -> $HOME
            # ${localWorkspaceFolder} -> $WORK_DIR
            mount=$(echo "$mount" | sed "s/\${env:HOME}/$(echo $HOME | sed 's/\//\\\//g')/g")
            mount=$(echo "$mount" | sed "s/\${localWorkspaceFolder}/$(echo $WORK_DIR | sed 's/\//\\\//g')/g")

            # Only add mount if source exists (skip if file/dir doesn't exist)
            source_path=$(echo "$mount" | grep -oP 'source=\K[^,]+' || echo "")
            if [ -n "$source_path" ] && [ -e "$source_path" ]; then
                EXTRA_MOUNTS="$EXTRA_MOUNTS --mount $mount"
            else
                echo -e "${YELLOW}Skipping mount (source not found): $source_path${NC}"
            fi
        done <<< "$MOUNTS"
    fi
fi

# Determine the remote user from devcontainer.json (default to vscode)
REMOTE_USER="vscode"
if command -v jq > /dev/null 2>&1; then
    REMOTE_USER=$(jq -r '.remoteUser // "vscode"' "$WORK_DIR/.devcontainer/devcontainer.json" 2>/dev/null || echo "vscode")
fi

echo -e "${GREEN}Starting Claude Code in devcontainer...${NC}"
echo -e "${YELLOW}Container name: $CONTAINER_NAME${NC}"
echo -e "${YELLOW}Workspace: /workspace${NC}"
echo -e "${YELLOW}Remote user: $REMOTE_USER${NC}"
echo -e "${YELLOW}Claude binary: $CLAUDE_BIN -> /usr/local/bin/claude${NC}"
if [ -f "$CLAUDE_CONFIG_JSON" ]; then
    echo -e "${YELLOW}Config file: $CLAUDE_CONFIG_JSON -> /home/$REMOTE_USER/.claude.json${NC}"
fi
if [ -d "$CLAUDE_CONFIG_DIR" ]; then
    echo -e "${YELLOW}Config dir: $CLAUDE_CONFIG_DIR -> /home/$REMOTE_USER/.claude${NC}"
fi

# Build volume mounts for Claude config
CLAUDE_MOUNTS=""
if [ -f "$CLAUDE_CONFIG_JSON" ]; then
    CLAUDE_MOUNTS="$CLAUDE_MOUNTS -v $CLAUDE_CONFIG_JSON:/home/$REMOTE_USER/.claude.json"
fi
if [ -d "$CLAUDE_CONFIG_DIR" ]; then
    CLAUDE_MOUNTS="$CLAUDE_MOUNTS -v $CLAUDE_CONFIG_DIR:/home/$REMOTE_USER/.claude"
fi

# Run the container
docker run -it --rm \
    --name "$CONTAINER_NAME" \
    --user "$REMOTE_USER" \
    -v "$WORK_DIR:/workspace" \
    -v "$CLAUDE_BIN:/usr/local/bin/claude:ro" \
    $CLAUDE_MOUNTS \
    $EXTRA_MOUNTS \
    -w /workspace \
    "$IMAGE_NAME" \
    /usr/local/bin/claude "$@"
