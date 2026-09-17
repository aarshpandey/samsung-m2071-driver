#!/usr/bin/env bash
#
# scanner/test_scan.sh - Scanner driver pipeline test utility
# macOS Apple Silicon (arm64)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAM_SCAN="$SCRIPT_DIR/tools/samsung-scan"
TEST_OUT="/tmp/samsung_scan_test.pdf"

echo "============================================================"
echo " Samsung Xpress M2071 / M2070 Scanner Test Utility         "
echo " Native Apple Silicon (ARM64) Driver Verification          "
echo "============================================================"

# Check if hardware attached
echo "==> Detecting Samsung scanner devices..."
"$SAM_SCAN" --detect || true
echo ""

echo "==> Running synthetic scanner pipeline verification test..."
"$SAM_SCAN" --test-pattern -o "$TEST_OUT"

if [ -f "$TEST_OUT" ]; then
    echo ""
    echo "============================================================"
    echo " [✓] Scanner pipeline verification PASSED!"
    echo " Test scan output: $TEST_OUT ($(wc -c < "$TEST_OUT" | tr -d ' ') bytes)"
    echo " You can open it in Preview with: open $TEST_OUT"
    echo "============================================================"
else
    echo "Error: Test scan failed to produce output." >&2
    exit 1
fi
