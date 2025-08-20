#!/bin/bash

echo "=== BW Session Debug ==="
echo "1. Initial state:"
echo "   BW_SESSION: ${BW_SESSION:0:20}..."
echo "   Session file: $(cat ~/.bw_session 2>/dev/null | cut -c1-20)..."
echo ""

echo "2. Running bw-login.sh:"
source ~/dev/gypsys-cli-tools/bitwarden/bw-login.sh --auto
echo ""

echo "3. After bw-login.sh:"
echo "   BW_SESSION: ${BW_SESSION:0:20}..."
echo "   Session file: $(cat ~/.bw_session 2>/dev/null | cut -c1-20)..."
echo ""

echo "4. Checking bw status:"
bw status | jq -r '.status'
echo ""

echo "5. Final state:"
echo "   BW_SESSION: ${BW_SESSION:0:20}..."
echo "   Session file: $(cat ~/.bw_session 2>/dev/null | cut -c1-20)..."
echo ""

echo "6. Testing if they match:"
if [[ "$BW_SESSION" == "$(cat ~/.bw_session 2>/dev/null)" ]]; then
    echo "   ✓ Sessions match"
else
    echo "   ✗ Sessions DO NOT MATCH"
    echo "   BW_SESSION: $BW_SESSION"
    echo "   File content: $(cat ~/.bw_session 2>/dev/null)"
fi 