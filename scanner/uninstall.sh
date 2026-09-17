#!/usr/bin/env bash
#
# scanner/uninstall.sh - Standalone Scanner Driver Uninstaller for Samsung Xpress M2071 / M2070
# macOS Apple Silicon (arm64)
#

set -e

if [ "$EUID" -ne 0 ]; then
    echo "==> Requesting administrative privileges (sudo) to uninstall scanner driver..."
    exec sudo bash "$0" "$@"
fi

echo "============================================================"
echo " Samsung Xpress M2071 / M2070 Scanner Driver Uninstaller    "
echo "============================================================"

# Remove scanner subsystem
echo "==> Removing scanner subsystem..."
rm -rf /Library/Printers/Samsung/Scanner
rmdir /Library/Printers/Samsung 2>/dev/null || true

# Remove Desktop App
echo "==> Removing Desktop Application..."
rm -rf "/Applications/Samsung Scanner.app" 2>/dev/null || true

# Remove CLI tools
echo "==> Removing CLI utilities..."
rm -f /usr/local/bin/samsung-scan /usr/local/bin/samsung-scan-engine 2>/dev/null || true

echo ""
echo "============================================================"
echo " [✓] Scanner Suite Uninstalled Successfully!                "
echo "============================================================"
