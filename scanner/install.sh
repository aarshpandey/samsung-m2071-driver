#!/usr/bin/env bash
#
# scanner/install.sh - Standalone Scanner Driver Installer for Samsung Xpress M2071 / M2070
# Native Apple Silicon (arm64) macOS Scanner Driver & Application Suite
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
APP_DIR="$SCRIPT_DIR/Samsung Scanner.app"
SYS_SCANNER_DIR="/Library/Printers/Samsung/Scanner"

echo "============================================================"
echo " Samsung Xpress M2071 / M2070 Scanner Driver Installer      "
echo " Native Apple Silicon (ARM64) macOS Scanner Suite           "
echo "============================================================"

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo "Warning: Current machine architecture is '$ARCH'. This driver is optimized for Apple Silicon (arm64)."
fi

# Ensure root privileges for system installation
if [ "$EUID" -ne 0 ]; then
    echo "==> Requesting administrative privileges (sudo) to install scanner driver..."
    exec sudo bash "$0" "$@"
fi

# Step 1: Compile native Apple Silicon scanner engine
echo "==> [1/4] Building native ARM64 scanner engine..."
make -C "$SCRIPT_DIR" all

if [ ! -f "$BIN_DIR/samsung-scan-engine" ]; then
    echo "Error: Scanner engine build failed. '$BIN_DIR/samsung-scan-engine' not found." >&2
    exit 1
fi

# Step 2: Install scanner subsystem to /Library/Printers/Samsung/Scanner
echo "==> [2/4] Installing scanner subsystem to $SYS_SCANNER_DIR..."
mkdir -p "$SYS_SCANNER_DIR"
cp "$BIN_DIR/samsung-scan-engine" "$SYS_SCANNER_DIR/"
cp "$SCRIPT_DIR/samsung-scan-web.py" "$SYS_SCANNER_DIR/"
chown -R root:wheel "$SYS_SCANNER_DIR"
chmod 755 "$SYS_SCANNER_DIR"
chmod 755 "$SYS_SCANNER_DIR/samsung-scan-engine" "$SYS_SCANNER_DIR/samsung-scan-web.py"
codesign -s - --force "$SYS_SCANNER_DIR/samsung-scan-engine" 2>/dev/null || true

# Step 3: Bundle and install Desktop Application
echo "==> [3/4] Installing Desktop Scanner Application..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/samsung-scan-engine" "$APP_DIR/Contents/MacOS/"
chmod +x "$APP_DIR/Contents/MacOS/Samsung Scanner"
chmod +x "$APP_DIR/Contents/MacOS/samsung-scan-engine"
codesign -s - --force --deep "$APP_DIR" 2>/dev/null || true

if [ -d "/Applications" ]; then
    rm -rf "/Applications/Samsung Scanner.app"
    cp -r "$APP_DIR" "/Applications/"
    chmod -R 755 "/Applications/Samsung Scanner.app"
    echo "    [✓] Installed: /Applications/Samsung Scanner.app"
fi

# Step 4: Install CLI utilities
echo "==> [4/4] Installing CLI utilities..."
mkdir -p /usr/local/bin 2>/dev/null || true
if [ -d "/usr/local/bin" ]; then
    cp "$SCRIPT_DIR/tools/samsung-scan" /usr/local/bin/samsung-scan 2>/dev/null || true
    ln -sf "$SYS_SCANNER_DIR/samsung-scan-engine" /usr/local/bin/samsung-scan-engine 2>/dev/null || true
    chmod 755 /usr/local/bin/samsung-scan 2>/dev/null || true
    echo "    [✓] Installed CLI command: /usr/local/bin/samsung-scan"
fi

echo ""
echo "============================================================"
echo " Scanner Suite Installation Complete!                       "
echo "============================================================"
echo " • Desktop App: /Applications/Samsung Scanner.app"
echo " • Web UI:      python3 $SCRIPT_DIR/samsung-scan-web.py"
echo " • CLI Tool:    samsung-scan -o scan.pdf"
echo " • Test Script: ./scanner/test_scan.sh"
echo "============================================================"
