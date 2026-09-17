# Samsung Xpress M2071 / M2070 Printer Driver (Apple Silicon arm64)

Native **Apple Silicon (arm64)** CUPS printer driver for Samsung Xpress M2071 / M2070 / M2020 series monochrome laser multifunction printers.

---

## 🎯 Features

* **100% Native ARM64**: Runs natively on Apple Silicon (M1/M2/M3/M4) with zero Rosetta / Intel translation layer dependencies. Ready for macOS 27 and 28.
* **QPDL v.3 with Algo 0x11 Compression**: Fully compliant with Samsung's proprietary compression protocol and band alignment.
* **Strict CUPS Sandboxing**: Passes macOS CUPS sandboxing requirements with proper `root:wheel` `0755` permissions and ad-hoc code signatures.
* **Validated PPDs**: Conforms 100% to Adobe PostScript Printer Description specification (verified via `cupstestppd`).
* **High Resolution**: 600 DPI standard and 1200 DPI enhanced output.
* **Toner Save**: Support for Samsung EconoMode toner save feature.

---

## 📦 Directory Structure

```
printer/
├── bin/
│   └── rastertoqpdl             # Native arm64 CUPS raster filter binary
├── include/                     # C++ headers for QPDL filter
├── src/                         # C++ source code (SpliX QPDL engine)
├── ppd/
│   ├── Samsung-Xpress-M2071.ppd # PPD for Samsung Xpress M2071 Series
│   └── Samsung-Xpress-M2070.ppd # PPD for Samsung Xpress M2070 Series
├── tools/
│   ├── samsung-print            # CLI print utility
│   └── generate_testpage.py     # Pure Python test page generator
├── Makefile                     # Compiles rastertoqpdl
├── test_print.sh                # Test page generation & pipeline verification script
├── install.sh                   # Standalone printer driver installer
├── uninstall.sh                 # Standalone printer driver uninstaller
└── README.md                    # This documentation
```

---

## 🚀 Installation

Open Terminal in this folder and run:

```bash
cd printer
sudo ./install.sh
```

This script:
1. Compiles `bin/rastertoqpdl` natively for `arm64`.
2. Installs the filter into `/Library/Printers/Samsung/Filter/rastertoqpdl`.
3. Installs PPD files to `/Library/Printers/PPDs/Contents/Resources/`.
4. Enforces strict `root:wheel` ownership and `0755`/`0644` permissions.
5. Codesigns the filter binary.
6. Automatically discovers any connected Samsung USB printer and creates the CUPS queue.
7. Installs the CLI tool `samsung-print` to `/usr/local/bin/samsung-print`.

---

## 🖨️ How to Print

### Option 1: macOS System Print Dialog (Recommended)
1. In any macOS app (Safari, Word, Pages, Preview), press **Cmd + P**.
2. Select your printer: **Samsung Xpress M2071 (Apple Silicon)**.
3. Configure resolution (600/1200 DPI), paper size, or toner save in the print dialog options.
4. Click **Print**.

### Option 2: Command Line (`samsung-print`)
```bash
# Print any PDF, image, or text file directly:
samsung-print document.pdf

# Print multiple copies:
samsung-print -c 2 invoice.pdf

# Convert document to raw Samsung QPDL stream:
samsung-print -o output.qpdl document.pdf
```

---

## 🧪 Testing and Verification

To verify the driver pipeline without needing physical hardware attached:

```bash
./test_print.sh --dry-run
```

If your printer is plugged in and powered on:
```bash
./test_print.sh
```
This generates an Apple Silicon diagnostic test page (with resolution grids, alignment markers, and gray gradient bars) and submits it to your Samsung print queue.

---

## 🗑️ Uninstallation

To cleanly remove all printer queues, PPDs, filters, and CLI tools:

```bash
sudo ./uninstall.sh
```
