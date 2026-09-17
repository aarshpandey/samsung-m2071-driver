# Samsung Xpress M2071 / M2070 Scanner Driver & Application Suite (Apple Silicon arm64)

Native **Apple Silicon (arm64)** scanner driver engine and multi-interface scanning suite for **Samsung Xpress M2071 and M2070 series** multifunction devices.

---

## 🎯 Features

* **Native Swift & SwiftUI Desktop App**: Modern macOS native interface (`Samsung Scanner.app`) written in Swift with Cupertino styling, SF Symbols, interactive canvas, real-time zoom, and CoreImage enhancements.
* **100% Native ARM64**: Pure Apple Silicon binary with zero Rosetta / Intel compatibility layers.
* **Samsung MFP Protocol**: Full implementation of Samsung SCSI-over-USB (USB Interface 1, Bulk Endpoints).
* **CoreImage Real-Time Adjustments**: Live brightness, contrast, saturation, and rotation controls.
* **Multi-Format Export**: Generates PDF, PNG, JPEG, and TIFF directly.
* **Multiple Interfaces**:
  1. **Native Swift macOS App**: `Samsung Scanner.app` (SwiftUI + AppKit + CoreImage)
  2. **Browser Web Interface**: `samsung-scan-web.py` accessible from Safari, Chrome, or mobile devices.
  3. **Command-Line Interface**: `samsung-scan` for terminal users and automations.
* **Completely Independent**: Can be installed and used without the printer driver.

---

## 📦 Directory Structure

```
scanner/
├── gui-swift/                   # Native Swift / SwiftUI macOS App source code
│   └── Sources/
│       ├── main.swift           # Application entry point & native menus
│       ├── ScannerViewModel.swift# Reactive state & engine process pipeline
│       ├── SidebarView.swift    # Cupertino settings sidebar (presets, sliders, format)
│       ├── CanvasView.swift     # Interactive document preview with zoom and pan
│       ├── ContentView.swift    # Split-view workspace layout
│       └── ImageFilters.swift   # CoreImage filters & multi-format export
├── bin/
│   └── samsung-scan-engine      # Native arm64 SCSI-over-USB scanner engine
├── src/                         # C++ scanner engine source code
├── Samsung Scanner.app/         # Standalone double-clickable native macOS Application
├── tools/
│   ├── samsung-scan             # CLI launcher and tool
│   └── generate_icon.py         # AppIcon generator
├── samsung-scan-web.py          # Local browser-based Web interface (http://localhost:8080)
├── Makefile                     # Compiles both C++ engine and native Swift App
├── test_scan.sh                 # Scanner test & verification script
├── install.sh                   # Standalone scanner driver installer
├── uninstall.sh                 # Standalone scanner driver uninstaller
└── README.md                    # This documentation
```

---

## 🚀 Installation

Open Terminal in this folder and run:

```bash
cd scanner
sudo ./install.sh
```

This script:
1. Compiles `bin/samsung-scan-engine` natively for `arm64`.
2. Installs the engine and scripts into `/Library/Printers/Samsung/Scanner/`.
3. Installs `Samsung Scanner.app` to `/Applications/Samsung Scanner.app`.
4. Codesigns all binaries and application bundles.
5. Installs the CLI command `samsung-scan` into `/usr/local/bin/samsung-scan`.

---

## 📸 How to Scan

### Option 1: Native Desktop Application (`Samsung Scanner.app`)
Open **Samsung Scanner.app** from `/Applications` or run:
```bash
./tools/samsung-scan --gui
```
* **Live Connection Status**: Visual indicator for USB scanner connection.
* **Color Modes**: Color (24-bit RGB), Grayscale (8-bit), and LineArt (Black & White).
* **Resolutions**: 75, 150, 300, 600 DPI.
* **Canvas Preview**: Fast 75 DPI preview scan before final capture.
* **One-Click Open**: Automatically opens your scanned document in Apple Preview.

---

### Option 2: Browser Web Interface (`samsung-scan-web.py`)
Scan from any web browser on `http://localhost:8080`:
```bash
python3 samsung-scan-web.py
# or:
./tools/samsung-scan --web
```
* Provides a clean, modern web interface.
* Live scan progress bar and immediate document download.
* Accessible from phones or tablets on the same local network!

---

### Option 3: Command-Line Interface (`samsung-scan`)
```bash
# Scan to PDF (default 300 DPI A4)
samsung-scan -o scan.pdf

# High-resolution color photo scan
samsung-scan -m color -d 600 -o photo.png

# Fast grayscale scan
samsung-scan -m gray -d 150 -o notes.pdf

# Detect attached Samsung USB scanners
samsung-scan --detect
```

---

## 🧪 Testing and Verification

To verify that the scanning engine and PDF/image export pipeline works without needing the physical scanner connected:

```bash
./test_scan.sh
```

---

## 🗑️ Uninstallation

To cleanly remove all scanner binaries, the desktop application, and CLI tools:

```bash
sudo ./uninstall.sh
```
