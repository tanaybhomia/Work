#!/usr/bin/env bash

set -e

echo "Starting Work Tracker installation..."

# Define paths
BIN_DIR="$HOME/.local/bin"
SCRIPT_URL="https://raw.githubusercontent.com/YOUR_USERNAME/worktracker/main/work"
DEST_FILE="$BIN_DIR/work"

# 1. Create local bin directory if it doesn't exist
if [ ! -d "$BIN_DIR" ]; then
    echo "Creating directory: $BIN_DIR"
    mkdir -p "$BIN_DIR"
fi

# 2. Download the script
echo "Downloading Work Tracker from GitHub..."
if command -v curl >/dev/null 2>&1; then
    curl -sSL "$SCRIPT_URL" -o "$DEST_FILE"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$DEST_FILE" "$SCRIPT_URL"
else
    echo "Error: Neither 'curl' nor 'wget' is installed. Please install one to continue."
    exit 1
fi

echo "Download complete. File saved to $DEST_FILE"

# 3. Ask the user to make it executable
echo ""
read -p "Do you want to make the script executable now? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    chmod +x "$DEST_FILE"
    echo "Permissions updated: $DEST_FILE is now executable."
else
    echo "Skipped making the file executable."
    echo "You will need to run 'chmod +x $DEST_FILE' manually before you can run it."
fi

# 4. PATH check and final instructions
echo ""
echo "========================================"
echo "Installation Finished!"
echo "========================================"

# Check if ~/.local/bin is actually in the user's PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "NOTE: $BIN_DIR is NOT currently in your system PATH."
    echo "To use the 'work' command from anywhere, add this line to your ~/.bashrc or ~/.zshrc:"
    echo ""
    echo '    export PATH="$HOME/.local/bin:$PATH"'
    echo ""
    echo "After adding it, restart your terminal or run: source ~/.bashrc"
else
    echo "Success! The directory is in your PATH."
    echo "You can now run 'work help' from anywhere in your terminal."
fi