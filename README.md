# Samsung Xpress M2071 / M2070 Driver & Scanner Suite (Apple Silicon arm64)

[![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-brightgreen.svg)]()
[![macOS](https://img.shields.io/badge/macOS-Sonoma%20%7C%20Sequoia%20%7C%2027%20%7C%2028-blue.svg)]()
[![License](https://img.shields.io/badge/License-GPL%20v2-orange.svg)](LICENSE)

A complete, **native Apple Silicon (arm64)** driver and scanning suite for **Samsung Xpress M2071 and M2070 series** multifunction printers.

The printer driver and scanner driver are **100% modular and independent**. You can install only the printer driver, only the scanner driver, or both.

---

## 📁 Modular Directory Structure

```
driver/
│
├── printer/                     # Standalone Printer Driver
│   ├── bin/rastertoqpdl         # Native arm64 CUPS printer raster filter
│   ├── ppd/                     # PPD files (passed cupstestppd with 0 warnings)
│   ├── src/ & include/          # C++ source code (SpliX QPDL engine)
│   ├── tools/                   # Tools (samsung-print, generate_testpage.py)
│   ├── Makefile                 # Compiles rastertoqpdl
│   ├── test_print.sh            # Diagnostic test page & verification
│   ├── install.sh               # Independent printer installer
│   ├── uninstall.sh             # Independent printer uninstaller
│   └── README.md                # Standalone printer documentation
│
├── scanner/                     # Standalone Scanner Driver & Apps
│   ├── bin/samsung-scan-engine  # Native arm64 SCSI-over-USB scanner engine
│   ├── Samsung Scanner.app/     # Native Swift / SwiftUI macOS Desktop Application
│   ├── gui-swift/               # Swift app source code (SwiftUI + AppKit + CoreImage)
│   ├── samsung-scan-web.py      # Browser-based Web UI (http://localhost:8080)
│   ├── tools/                   # Tools (samsung-scan, generate_icon.py)
│   ├── src/                     # C++ scanner source code
│   ├── Makefile                 # Compiles samsung-scan-engine & Swift App
│   ├── test_scan.sh             # Scanner pipeline verification
│   ├── install.sh               # Independent scanner installer
│   ├── uninstall.sh             # Independent scanner uninstaller
│   └── README.md                # Standalone scanner documentation
│
├── install.sh                   # Master installer for both components
├── uninstall.sh                 # Master uninstaller for both components
├── package.sh                   # Builds .pkg & .dmg distributable installers
├── LICENSE                      # GNU General Public License v2.0
└── README.md                    # Project documentation
```

---

## 🖨️ 1. Printer Only: Installation & Usage

If you **only want to use the printer**:

```bash
cd printer
sudo ./install.sh
```

### Features:
* **Zero Rosetta / Intel dependencies**: 100% native `arm64` raster filter (`rastertoqpdl`).
* **Strict CUPS Permissions**: Proper `root:wheel` / `0755` ownership required by macOS CUPS sandboxing.
* **Validated PPDs**: `Samsung-Xpress-M2071.ppd` and `Samsung-Xpress-M2070.ppd` (passed `cupstestppd` with 0 warnings).
* **Test the printer**:
  ```bash
  # Test page conversion (dry-run without physical printer)
  ./test_print.sh --dry-run

  # Submit test print to physical printer
  ./test_print.sh
  ```
* **Print via CLI**:
  ```bash
  samsung-print document.pdf
  ```
* **Uninstall printer only**:
  ```bash
  cd printer
  sudo ./uninstall.sh
  ```

---

## 📸 2. Scanner Only: Installation & Usage

If you **only want to use the scanner**:

```bash
cd scanner
sudo ./install.sh
```

### Features & Interfaces:
* **Native C++ Engine**: Implements Samsung SCSI-over-USB on USB Interface 1 (VID `0x04e8`, PID `0x3469`).
* **Multiple Simple Interfaces**:
  1. **Native Desktop App**: Double-click `/Applications/Samsung Scanner.app` (or `scanner/Samsung\ Scanner.app`).
  2. **Browser Web UI**: Run `python3 scanner/samsung-scan-web.py` (or `samsung-scan --web`) and open `http://localhost:8080`.
  3. **Command Line (`samsung-scan`)**:
     ```bash
     # Scan to PDF
     samsung-scan -o scan.pdf

     # High-resolution color photo scan
     samsung-scan -m color -d 600 -o photo.png

     # Detect connected scanners
     samsung-scan --detect
     ```
* **Test the scanner**:
  ```bash
  cd scanner
  ./test_scan.sh
  ```
* **Uninstall scanner only**:
  ```bash
  cd scanner
  sudo ./uninstall.sh
  ```

---

## ⚡ 3. Installing Both (Complete Suite)

To install both printer and scanner drivers simultaneously:

```bash
sudo ./install.sh
```

To remove both:
```bash
sudo ./uninstall.sh
```

---

## 📦 4. Distributing to Other Users (.pkg & .dmg)

To build distributable native installers that other Mac users can double-click:

```bash
./package.sh
```

This generates:
* `dist/Samsung-Xpress-Printer-Driver.pkg`: Standalone installer for users who only want to print.
* `dist/Samsung-Scanner-Suite.pkg`: Standalone installer for users who only want to scan.
* `dist/Samsung-Scanner.dmg`: Drag-and-drop disk image for `Samsung Scanner.app`.
* `dist/Samsung-Xpress-M2071-Full-Suite.dmg`: Complete all-in-one distribution image with both packages, the desktop app, and instructions.

### Note on macOS Gatekeeper for Recipients:
When another user downloads `.pkg` or `.dmg` files from the internet (Safari, Chrome, AirDrop), macOS sets the quarantine attribute.
To open on a Mac without an Apple Developer ID signature:
1. **Right-click (Control-click)** the installer or app in Finder.
2. Select **Open**, then click **Open Anyway**.
*(Or run `xattr -cr <file>` in Terminal).*
