#!/bin/bash
# Quick fix for permission issues from running with sudo

echo "Cleaning up root-owned files..."
sudo rm -f ./install.log
sudo chown -R $USER:$USER .

echo "Fixed! Now run:"
echo "  ./install.sh"

