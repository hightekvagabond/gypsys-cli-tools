#!/bin/bash
# Upgrade to the larger, more accurate Vosk model

set -e

VOSK_MODEL_DIR="$HOME/.local/share/vosk-models"
VOSK_MODEL="vosk-model-en-us-0.22"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Upgrading Vosk to larger, more accurate model"
echo "=============================================="
echo ""
echo "Model: $VOSK_MODEL"
echo "Size: ~1.8GB"
echo "Accuracy: Much better than the small model"
echo ""

# Check disk space
AVAILABLE_SPACE=$(df -BG "$VOSK_MODEL_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo "10")
if [[ $AVAILABLE_SPACE -lt 2 ]]; then
    echo "⚠️  Warning: Low disk space (${AVAILABLE_SPACE}GB available)"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

mkdir -p "$VOSK_MODEL_DIR"
cd "$VOSK_MODEL_DIR"

if [[ -d "$VOSK_MODEL" ]]; then
    echo "✓ Model already exists at: $VOSK_MODEL_DIR/$VOSK_MODEL"
    echo ""
    read -p "Re-download? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing model."
        exit 0
    fi
    rm -rf "$VOSK_MODEL"
fi

echo "Downloading $VOSK_MODEL..."
echo "This will take 5-10 minutes depending on your connection..."
echo ""

wget -q --show-progress "https://alphacephei.com/vosk/models/${VOSK_MODEL}.zip"

echo ""
echo "Extracting model..."
unzip -q "${VOSK_MODEL}.zip"
rm "${VOSK_MODEL}.zip"

echo ""
echo "✅ Upgrade complete!"
echo ""
echo "Model location: $VOSK_MODEL_DIR/$VOSK_MODEL"
echo ""
echo "The vosk-dictate command will now use this more accurate model."
echo ""
echo "Try it: vosk-dictate"

