#!/usr/bin/env bash
#
# printer/uninstall.sh - Standalone Printer Driver Uninstaller for Samsung Xpress M2071 / M2070
# macOS Apple Silicon (arm64)
#

set -e

if [ "$EUID" -ne 0 ]; then
    echo "==> Requesting administrative privileges (sudo) to uninstall printer driver..."
    exec sudo bash "$0" "$@"
fi

echo "============================================================"
echo " Samsung Xpress M2071 / M2070 Printer Driver Uninstaller    "
echo "============================================================"

# Remove CUPS print queues
for queue in "Samsung_Xpress_M2071" "Samsung_Xpress_M2070" "Samsung_M2071" "Samsung_M2070" "Samsung_M2070_Series"; do
    if lpstat -p "$queue" >/dev/null 2>&1; then
        echo "==> Removing CUPS queue '$queue'..."
        lpadmin -x "$queue" 2>/dev/null || true
    fi
done

# Remove PPDs
echo "==> Removing PPD files..."
rm -f /Library/Printers/PPDs/Contents/Resources/Samsung-Xpress-M2071.ppd
rm -f /Library/Printers/PPDs/Contents/Resources/Samsung-Xpress-M2070.ppd

# Remove filter binary
echo "==> Removing driver filter binary..."
rm -rf /Library/Printers/Samsung/Filter
rmdir /Library/Printers/Samsung 2>/dev/null || true

# Remove CLI tool
rm -f /usr/local/bin/samsung-print 2>/dev/null || true

# Restart CUPS
echo "==> Refreshing CUPS printing subsystem..."
launchctl kickstart -k system/org.cups.cupsd 2>/dev/null || killall -HUP cupsd 2>/dev/null || true

echo ""
echo "============================================================"
echo " [✓] Printer Driver Uninstalled Successfully!               "
echo "============================================================"
