#!/usr/bin/env bash
#
# package.sh - Create Distributable macOS Packages (.pkg & .dmg) for Samsung Xpress M2071 / M2070
# Native Apple Silicon (arm64) macOS
#
# Generates:
#   dist/Samsung-Xpress-Printer-Driver.pkg  (Double-click installer for Printer)
#   dist/Samsung-Scanner-Suite.pkg          (Double-click installer for Scanner)
#   dist/Samsung-Scanner.dmg                (Drag-and-Drop Disk Image for Scanner App)
#   dist/Samsung-Xpress-M2071-Full-Suite.dmg (Complete distribution bundle)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
BUILD_TMP="/tmp/samsung_package_build"
export COPYFILE_DISABLE=1

echo "============================================================"
echo " Building Distributable Packages for Samsung Xpress M2071   "
echo " Target Architecture: Apple Silicon (arm64)                 "
echo "============================================================"

# Ensure clean build of native binaries
echo "==> [1/5] Compiling native ARM64 binaries..."
make -C "$SCRIPT_DIR/printer" all
make -C "$SCRIPT_DIR/scanner" all

# Prepare distribution directory
rm -rf "$DIST_DIR" "$BUILD_TMP"
mkdir -p "$DIST_DIR" "$BUILD_TMP"

# ============================================================
# PACKAGE 1: Standalone Printer Driver (.pkg)
# ============================================================
echo "==> [2/5] Creating Standalone Printer Driver Package (.pkg)..."
PRINTER_ROOT="$BUILD_TMP/printer_root"
PRINTER_SCRIPTS="$BUILD_TMP/printer_scripts"
mkdir -p "$PRINTER_ROOT/Library/Printers/Samsung/Filter"
mkdir -p "$PRINTER_ROOT/Library/Printers/PPDs/Contents/Resources"
mkdir -p "$PRINTER_ROOT/usr/local/bin"
mkdir -p "$PRINTER_SCRIPTS"

# Copy payload files
cp "$SCRIPT_DIR/printer/bin/rastertoqpdl" "$PRINTER_ROOT/Library/Printers/Samsung/Filter/"
cp "$SCRIPT_DIR/printer/ppd/Samsung-Xpress-M2071.ppd" "$PRINTER_ROOT/Library/Printers/PPDs/Contents/Resources/"
cp "$SCRIPT_DIR/printer/ppd/Samsung-Xpress-M2070.ppd" "$PRINTER_ROOT/Library/Printers/PPDs/Contents/Resources/"
cp "$SCRIPT_DIR/printer/tools/samsung-print" "$PRINTER_ROOT/usr/local/bin/"
dot_clean -m "$PRINTER_ROOT" 2>/dev/null || true

# Create postinstall script
cat << 'EOF' > "$PRINTER_SCRIPTS/postinstall"
#!/bin/bash
set -e

FILTER_DIR="/Library/Printers/Samsung/Filter"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"

# Enforce CUPS permissions
chown -R root:wheel "/Library/Printers/Samsung"
chmod 755 "$FILTER_DIR"
chmod 755 "$FILTER_DIR/rastertoqpdl"
chown root:wheel "$PPD_DIR/Samsung-Xpress-M2071.ppd" "$PPD_DIR/Samsung-Xpress-M2070.ppd"
chmod 644 "$PPD_DIR/Samsung-Xpress-M2071.ppd" "$PPD_DIR/Samsung-Xpress-M2070.ppd"
chmod 755 /usr/local/bin/samsung-print 2>/dev/null || true

# Codesign filter
codesign -s - --force "$FILTER_DIR/rastertoqpdl" 2>/dev/null || true

# Reload CUPS daemon
launchctl kickstart -k system/org.cups.cupsd 2>/dev/null || killall -HUP cupsd 2>/dev/null || true

# Auto-configure if hardware plugged in
DETECTED_URI=$(lpinfo -v 2>/dev/null | grep -E "Samsung.*(207|M20|Printer|Laser)" | awk '{print $2}' | head -n 1 || true)
if [ -n "$DETECTED_URI" ]; then
    PRINTER_NAME="Samsung_Xpress_M2071"
    PPD_NAME="Samsung-Xpress-M2071.ppd"
    DESC_NAME="Samsung Xpress M2071 (Apple Silicon)"
    if echo "$DETECTED_URI" | grep -qi "2070"; then
        PRINTER_NAME="Samsung_Xpress_M2070"
        PPD_NAME="Samsung-Xpress-M2070.ppd"
        DESC_NAME="Samsung Xpress M2070 (Apple Silicon)"
    fi
    lpadmin -p "$PRINTER_NAME" -E -v "$DETECTED_URI" \
            -P "$PPD_DIR/$PPD_NAME" \
            -D "$DESC_NAME" \
            -L "Local USB" 2>/dev/null || true
    cupsenable "$PRINTER_NAME" 2>/dev/null || true
    cupsaccept "$PRINTER_NAME" 2>/dev/null || true
    lpadmin -d "$PRINTER_NAME" 2>/dev/null || true
fi
exit 0
EOF
chmod 755 "$PRINTER_SCRIPTS/postinstall"

pkgbuild --root "$PRINTER_ROOT" \
         --scripts "$PRINTER_SCRIPTS" \
         --identifier "com.samsung.driver.m2071.printer" \
         --version "2.0.2" \
         --install-location "/" \
         "$DIST_DIR/Samsung-Xpress-Printer-Driver.pkg"

# ============================================================
# PACKAGE 2: Standalone Scanner Suite (.pkg)
# ============================================================
echo "==> [3/5] Creating Standalone Scanner Suite Package (.pkg)..."
SCANNER_ROOT="$BUILD_TMP/scanner_root"
SCANNER_SCRIPTS="$BUILD_TMP/scanner_scripts"
mkdir -p "$SCANNER_ROOT/Applications"
mkdir -p "$SCANNER_ROOT/Library/Printers/Samsung/Scanner"
mkdir -p "$SCANNER_ROOT/usr/local/bin"
mkdir -p "$SCANNER_SCRIPTS"

# Prepare self-contained app bundle
cp -r "$SCRIPT_DIR/scanner/Samsung Scanner.app" "$SCANNER_ROOT/Applications/"
mkdir -p "$SCANNER_ROOT/Applications/Samsung Scanner.app/Contents/MacOS"
mkdir -p "$SCANNER_ROOT/Applications/Samsung Scanner.app/Contents/Resources"
cp "$SCRIPT_DIR/scanner/bin/samsung-scan-engine" "$SCANNER_ROOT/Applications/Samsung Scanner.app/Contents/MacOS/"

# Scanner system library components
cp "$SCRIPT_DIR/scanner/bin/samsung-scan-engine" "$SCANNER_ROOT/Library/Printers/Samsung/Scanner/"
cp "$SCRIPT_DIR/scanner/samsung-scan-web.py" "$SCANNER_ROOT/Library/Printers/Samsung/Scanner/"

# CLI tool
cp "$SCRIPT_DIR/scanner/tools/samsung-scan" "$SCANNER_ROOT/usr/local/bin/"
dot_clean -m "$SCANNER_ROOT" 2>/dev/null || true

cat << 'EOF' > "$SCANNER_SCRIPTS/postinstall"
#!/bin/bash
set -e

SCANNER_SYS="/Library/Printers/Samsung/Scanner"
APP_PATH="/Applications/Samsung Scanner.app"

chown -R root:wheel "$SCANNER_SYS" 2>/dev/null || true
chmod 755 "$SCANNER_SYS"
chmod 755 "$SCANNER_SYS"/* 2>/dev/null || true
chmod -R 755 "$APP_PATH" 2>/dev/null || true

# Codesign app and binaries
codesign -s - --force "$SCANNER_SYS/samsung-scan-engine" 2>/dev/null || true
codesign -s - --force --deep "$APP_PATH" 2>/dev/null || true

# Symlink CLI
ln -sf "$SCANNER_SYS/samsung-scan-engine" /usr/local/bin/samsung-scan-engine 2>/dev/null || true
chmod 755 /usr/local/bin/samsung-scan 2>/dev/null || true
exit 0
EOF
chmod 755 "$SCANNER_SCRIPTS/postinstall"

pkgbuild --root "$SCANNER_ROOT" \
         --scripts "$SCANNER_SCRIPTS" \
         --identifier "com.samsung.driver.m2071.scanner" \
         --version "1.0.0" \
         --install-location "/" \
         "$DIST_DIR/Samsung-Scanner-Suite.pkg"

# ============================================================
# PACKAGE 3: Drag-and-Drop Scanner DMG (.dmg)
# ============================================================
echo "==> [4/5] Creating Drag-and-Drop Scanner Disk Image (.dmg)..."
SCANNER_DMG_DIR="$BUILD_TMP/scanner_dmg"
mkdir -p "$SCANNER_DMG_DIR"

cp -r "$SCANNER_ROOT/Applications/Samsung Scanner.app" "$SCANNER_DMG_DIR/"
ln -s /Applications "$SCANNER_DMG_DIR/Applications"

cat << 'EOF' > "$SCANNER_DMG_DIR/Quick-Start.txt"
Samsung Scanner for macOS (Apple Silicon arm64)
==============================================

To Install:
1. Drag 'Samsung Scanner.app' into the 'Applications' folder shortcut.
2. Open 'Samsung Scanner' from Applications or Launchpad.

Features:
• Native Apple Silicon (M1/M2/M3/M4) performance.
• Color, Grayscale, and Text scanning (75 to 600 DPI).
• Real-time scan preview.
• Direct export to PDF, PNG, and JPEG.
EOF

dot_clean -m "$SCANNER_DMG_DIR" 2>/dev/null || true

hdiutil create -volname "Samsung Scanner" \
               -srcfolder "$SCANNER_DMG_DIR" \
               -ov -format UDZO \
               "$DIST_DIR/Samsung-Scanner.dmg"

# ============================================================
# PACKAGE 4: Complete All-in-One Distribution Bundle (.dmg)
# ============================================================
echo "==> [5/5] Creating Complete All-in-One Distribution Bundle (.dmg)..."
FULL_DMG_DIR="$BUILD_TMP/full_dmg"
mkdir -p "$FULL_DMG_DIR"

cp "$DIST_DIR/Samsung-Xpress-Printer-Driver.pkg" "$FULL_DMG_DIR/1-Install-Printer-Driver.pkg"
cp "$DIST_DIR/Samsung-Scanner-Suite.pkg" "$FULL_DMG_DIR/2-Install-Scanner-Suite.pkg"
cp -r "$SCANNER_ROOT/Applications/Samsung Scanner.app" "$FULL_DMG_DIR/"
ln -s /Applications "$FULL_DMG_DIR/Applications"

cat << 'EOF' > "$FULL_DMG_DIR/README-FIRST.txt"
Samsung Xpress M2071 / M2070 Driver Suite (Apple Silicon)
=========================================================

Supported Models:
• Samsung Xpress M2071, M2071W, M2071F, M2071FH, M2071HW
• Samsung Xpress M2070, M2070W, M2070F, M2070FW
• Samsung Xpress M2020, M2022, M2026 Series

How to Install:
1. Printer: Double-click '1-Install-Printer-Driver.pkg' and follow the prompt.
2. Scanner: Double-click '2-Install-Scanner-Suite.pkg' OR drag 'Samsung Scanner.app' to Applications.

Gatekeeper / Security Note:
If macOS displays "unidentified developer" on first open:
Right-click (Control-click) the installer or app, then choose "Open" > "Open Anyway".
EOF

dot_clean -m "$FULL_DMG_DIR" 2>/dev/null || true

hdiutil create -volname "Samsung M2071 Suite" \
               -srcfolder "$FULL_DMG_DIR" \
               -ov -format UDZO \
               "$DIST_DIR/Samsung-Xpress-M2071-Full-Suite.dmg"

# Cleanup temporary build dir
rm -rf "$BUILD_TMP"

echo ""
echo "============================================================"
echo " Packaging Complete! Distributable Files Generated in: dist/"
echo "============================================================"
ls -lh "$DIST_DIR"
echo "============================================================"
