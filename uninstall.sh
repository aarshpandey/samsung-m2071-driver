#!/usr/bin/env bash
#
# uninstall.sh - Master Uninstaller for Samsung Xpress M2071 / M2070
# Uninstalls BOTH the Printer Driver and Scanner Driver.
#
# If you ONLY want to uninstall printer:
#   cd printer && sudo ./uninstall.sh
#
# If you ONLY want to uninstall scanner:
#   cd scanner && sudo ./uninstall.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo "==> Requesting administrative privileges (sudo) to uninstall driver suite..."
    exec sudo bash "$0" "$@"
fi

echo "============================================================"
echo " Uninstalling Samsung Xpress M2071 / M2070 Full Suite      "
echo "============================================================"
echo ""

echo ">>> [1/2] Uninstalling PRINTER Driver..."
bash "$SCRIPT_DIR/printer/uninstall.sh" || true
echo ""

echo ">>> [2/2] Uninstalling SCANNER Driver..."
bash "$SCRIPT_DIR/scanner/uninstall.sh" || true
echo ""

echo "============================================================"
echo " [✓] Complete Suite Uninstalled Successfully!               "
echo "============================================================"
