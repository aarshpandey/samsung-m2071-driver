#!/usr/bin/env bash
#
# printer/install.sh - Standalone Printer Driver Installer for Samsung Xpress M2071 / M2070
# Native Apple Silicon (arm64) macOS CUPS Printer Driver
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
PPD_DIR="$SCRIPT_DIR/ppd"

FILTER_DEST_DIR="/Library/Printers/Samsung/Filter"
FILTER_DEST_BIN="$FILTER_DEST_DIR/rastertoqpdl"
PPD_DEST_DIR="/Library/Printers/PPDs/Contents/Resources"

echo "============================================================"
echo " Samsung Xpress M2071 / M2070 Printer Driver Installer     "
echo " Native Apple Silicon (ARM64) macOS CUPS Driver             "
echo "============================================================"

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo "Warning: Current machine architecture is '$ARCH'. This driver is optimized for Apple Silicon (arm64)."
fi

# Ensure root privileges for system installation
if [ "$EUID" -ne 0 ]; then
    echo "==> Requesting administrative privileges (sudo) to install printer driver..."
    exec sudo bash "$0" "$@"
fi

# Step 1: Compile native Apple Silicon printer filter
echo "==> [1/5] Building native ARM64 CUPS printer filter..."
make -C "$SCRIPT_DIR" all

if [ ! -f "$BIN_DIR/rastertoqpdl" ]; then
    echo "Error: Printer build failed. '$BIN_DIR/rastertoqpdl' not found." >&2
    exit 1
fi

# Step 2: Install printer filter executable to /Library/Printers/Samsung/Filter
echo "==> [2/5] Installing CUPS printer filter to $FILTER_DEST_DIR..."
mkdir -p "$FILTER_DEST_DIR"
cp "$BIN_DIR/rastertoqpdl" "$FILTER_DEST_BIN"
chown -R root:wheel "/Library/Printers/Samsung"
chmod 755 "$FILTER_DEST_DIR"
chmod 755 "$FILTER_DEST_BIN"
codesign -s - --force "$FILTER_DEST_BIN" 2>/dev/null || true

# Step 3: Install PPD files
echo "==> [3/5] Installing PPD descriptions to $PPD_DEST_DIR..."
mkdir -p "$PPD_DEST_DIR"
cp "$PPD_DIR/Samsung-Xpress-M2071.ppd" "$PPD_DEST_DIR/"
cp "$PPD_DIR/Samsung-Xpress-M2070.ppd" "$PPD_DEST_DIR/"
chown root:wheel "$PPD_DEST_DIR/Samsung-Xpress-M2071.ppd" "$PPD_DEST_DIR/Samsung-Xpress-M2070.ppd"
chmod 644 "$PPD_DEST_DIR/Samsung-Xpress-M2071.ppd" "$PPD_DEST_DIR/Samsung-Xpress-M2070.ppd"

# Validate installed PPD
cupstestppd -q "$PPD_DEST_DIR/Samsung-Xpress-M2071.ppd" && echo "    [✓] Samsung-Xpress-M2071.ppd: Conformance PASS"
cupstestppd -q "$PPD_DEST_DIR/Samsung-Xpress-M2070.ppd" && echo "    [✓] Samsung-Xpress-M2070.ppd: Conformance PASS"

# Step 4: Refresh CUPS daemon
echo "==> [4/5] Refreshing CUPS printing subsystem..."
launchctl kickstart -k system/org.cups.cupsd 2>/dev/null || killall -HUP cupsd 2>/dev/null || true
sleep 1

# Step 5: Check for connected USB Samsung printer & configure queue
echo "==> [5/5] Checking for connected Samsung USB hardware..."
DETECTED_URI=$(lpinfo -v 2>/dev/null | grep -E "Samsung.*(207|M20|Printer|Laser)" | awk '{print $2}' | head -n 1 || true)

if [ -n "$DETECTED_URI" ]; then
    echo "    Found printer at URI: $DETECTED_URI"
    PRINTER_NAME="Samsung_Xpress_M2071"
    lpadmin -p "$PRINTER_NAME" \
            -E \
            -v "$DETECTED_URI" \
            -P "$PPD_DEST_DIR/Samsung-Xpress-M2071.ppd" \
            -D "Samsung Xpress M2071 (Apple Silicon)" \
            -L "Local USB"
    cupsenable "$PRINTER_NAME" 2>/dev/null || true
    cupsaccept "$PRINTER_NAME" 2>/dev/null || true
    lpadmin -d "$PRINTER_NAME" 2>/dev/null || true
    echo "    [✓] Configured print queue '$PRINTER_NAME' and set as default!"
else
    echo "    Note: No Samsung USB printer currently plugged in."
    echo "    macOS will automatically offer this driver when the printer is connected."
fi

# Install CLI tool to /usr/local/bin
mkdir -p /usr/local/bin 2>/dev/null || true
if [ -d "/usr/local/bin" ]; then
    cp "$SCRIPT_DIR/tools/samsung-print" /usr/local/bin/samsung-print 2>/dev/null || true
    chmod 755 /usr/local/bin/samsung-print 2>/dev/null || true
    echo "==> Installed CLI tool: /usr/local/bin/samsung-print"
fi

echo ""
echo "============================================================"
echo " Printer Driver Installation Complete!                     "
echo "============================================================"
echo " • Raster Filter: $FILTER_DEST_BIN"
echo " • PPD:          $PPD_DEST_DIR/Samsung-Xpress-M2071.ppd"
echo " • CLI Tool:     samsung-print <file.pdf>"
echo " • Test Utility: ./printer/test_print.sh"
echo "============================================================"
