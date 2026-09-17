#!/usr/bin/env bash
#
# install.sh - Master Installer for Samsung Xpress M2071 / M2070
# Installs BOTH the Printer Driver and Scanner Driver.
#
# If you ONLY want the printer:
#   cd printer && sudo ./install.sh
#
# If you ONLY want the scanner:
#   cd scanner && sudo ./install.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo "==> Requesting administrative privileges (sudo) to install driver suite..."
    exec sudo bash "$0" "$@"
fi

echo "============================================================"
echo " Installing Samsung Xpress M2071 / M2070 Full Suite        "
echo " (Apple Silicon Native ARM64 macOS Drivers)                 "
echo "============================================================"
echo ""

echo ">>> [1/2] Installing PRINTER Driver..."
bash "$SCRIPT_DIR/printer/install.sh"
echo ""

echo ">>> [2/2] Installing SCANNER Driver & Application..."
bash "$SCRIPT_DIR/scanner/install.sh"
echo ""

echo "============================================================"
echo " All Drivers and Applications Installed Successfully!      "
echo "============================================================"
