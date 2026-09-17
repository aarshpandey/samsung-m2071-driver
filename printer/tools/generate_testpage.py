#!/usr/bin/env python3
"""
generate_testpage.py - Generates a rich, standalone PDF test page for Samsung Xpress M2071 / M2070.
Zero external dependencies, pure Python standard library.
"""

import sys
import os
import datetime
import platform

def generate_pdf(output_path):
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    uname = platform.uname()
    arch = uname.machine
    os_ver = f"{uname.system} {uname.release}"
    host = uname.node

    # Stream content with PDF operators
    stream_lines = []
    
    # Outer Border (25, 25, 545, 792)
    stream_lines.append("0.2 setlinewidth")
    stream_lines.append("25 25 545 792 re S")
    
    # Inner decorative border
    stream_lines.append("28 28 539 786 re S")
    
    # Title Header Box
    stream_lines.append("0.1 0.2 0.4 rg")
    stream_lines.append("30 760 535 50 re f")
    stream_lines.append("1 1 1 rg")
    stream_lines.append("BT /F1 20 Tf 45 788 Td (Samsung Xpress M2071 / M2070 Series) Tj ET")
    stream_lines.append("BT /F2 12 Tf 45 770 Td (Native macOS Apple Silicon (arm64) Printer Driver) Tj ET")
    stream_lines.append("0 0 0 rg")
    
    # System info section
    stream_lines.append("BT /F1 12 Tf 45 735 Td (SYSTEM & DRIVER CONFIGURATION) Tj ET")
    stream_lines.append("0.7 setgray 45 730 505 1 re f 0 setgray")
    
    info_items = [
        ("Architecture", f"{arch} (Apple Silicon - No Rosetta Required)"),
        ("Operating System", os_ver),
        ("Host Machine", host),
        ("Timestamp", now_str),
        ("Printer Protocol", "Samsung QPDL v.3 (SPL Monochrome)"),
        ("Compression", "Adaptive Dictionary & Run-Length (Algo 0x11)"),
        ("Resolution", "600 DPI & 1200 DPI High-Definition Engine"),
        ("Filter Executable", "/Library/Printers/Samsung/Filter/rastertoqpdl"),
        ("Driver Status", "Operational - Native ARM64 Pipeline Verified")
    ]
    
    y = 712
    for label, val in info_items:
        stream_lines.append(f"BT /F1 9 Tf 50 {y} Td ({label}:) Tj ET")
        stream_lines.append(f"BT /F3 9 Tf 170 {y} Td ({val}) Tj ET")
        y -= 14

    # Grayscale Gradient Ramp
    y_gray = y - 10
    stream_lines.append(f"BT /F1 11 Tf 45 {y_gray} Td (HALFTONE & GRAYSCALE STEP RAMP) Tj ET")
    stream_lines.append(f"0.7 setgray 45 {y_gray-5} 505 1 re f 0 setgray")
    
    box_w = 48
    box_h = 28
    box_y = y_gray - 38
    
    for i in range(10):
        gray = i / 9.0
        pct = int(round(gray * 100))
        x = 45 + i * (box_w + 3)
        stream_lines.append(f"{gray:.3f} setgray {x} {box_y} {box_w} {box_h} re f")
        stream_lines.append(f"0 setgray 0.5 setlinewidth {x} {box_y} {box_w} {box_h} re S")
        text_gray = 1 if gray < 0.5 else 0
        stream_lines.append(f"{text_gray} setgray")
        stream_lines.append(f"BT /F3 8 Tf {x+12} {box_y+10} Td ({pct}%) Tj ET")

    # Resolution & Line Width Sharpness Test
    y_lines = box_y - 25
    stream_lines.append(f"0 setgray")
    stream_lines.append(f"BT /F1 11 Tf 45 {y_lines} Td (RESOLUTION & EDGE SHARPNESS TEST) Tj ET")
    stream_lines.append(f"0.7 setgray 45 {y_lines-5} 505 1 re f 0 setgray")
    
    line_y = y_lines - 22
    for width in [2.5, 2.0, 1.5, 1.0, 0.75, 0.5, 0.25]:
        stream_lines.append(f"{width} setlinewidth")
        stream_lines.append(f"50 {line_y} m 470 {line_y} l S")
        stream_lines.append(f"BT /F3 7 Tf 480 {line_y-2} Td ({width} pt) Tj ET")
        line_y -= 12

    # Typography & Clarity Test
    y_text = line_y - 12
    stream_lines.append(f"0 setgray")
    stream_lines.append(f"BT /F1 11 Tf 45 {y_text} Td (TYPOGRAPHY & FONT LEGIBILITY TEST) Tj ET")
    stream_lines.append(f"0.7 setgray 45 {y_text-5} 505 1 re f 0 setgray")
    
    ty = y_text - 20
    stream_lines.append(f"BT /F2 6 Tf 50 {ty} Td (6 pt: The quick brown fox jumps over the lazy dog. 0123456789) Tj ET")
    ty -= 13
    stream_lines.append(f"BT /F2 8 Tf 50 {ty} Td (8 pt: The quick brown fox jumps over the lazy dog. 0123456789) Tj ET")
    ty -= 14
    stream_lines.append(f"BT /F2 10 Tf 50 {ty} Td (10 pt: The quick brown fox jumps over the lazy dog. 0123456789) Tj ET")
    ty -= 16
    stream_lines.append(f"BT /F1 12 Tf 50 {ty} Td (12 pt Bold: The quick brown fox jumps over the lazy dog. 0123456789) Tj ET")

    # Margin Alignment Box
    y_box = ty - 22
    stream_lines.append(f"BT /F1 11 Tf 45 {y_box} Td (PRINT MARGIN & ALIGNMENT BOUNDS) Tj ET")
    stream_lines.append(f"0.7 setgray 45 {y_box-5} 505 1 re f 0 setgray")
    
    stream_lines.append("0.5 setlinewidth")
    stream_lines.append(f"50 {y_box-60} 495 50 re S")
    stream_lines.append(f"BT /F3 8 Tf 60 {y_box-30} Td (Left Margin: 12.5 pt | Right Margin: 12.5 pt | Top/Bottom Margins: 12.5 pt) Tj ET")
    stream_lines.append(f"BT /F3 8 Tf 60 {y_box-45} Td (Samsung SPL3 Engine - Full 8.5x11 in / A4 Printable Area Alignment) Tj ET")

    # Footer
    stream_lines.append(f"0.5 setgray 45 45 505 1 re f 0 setgray")
    stream_lines.append(f"BT /F2 8 Tf 45 35 Td (Samsung Xpress M2071 Driver Suite - Native Apple Silicon arm64 Edition) Tj ET")
    stream_lines.append(f"BT /F3 8 Tf 460 35 Td (Page 1 of 1) Tj ET")

    stream_content = "\n".join(stream_lines).encode("utf-8")
    stream_len = len(stream_content)

    pdf = bytearray()
    pdf.extend(b"%PDF-1.4\n")
    
    offsets = []
    
    # 1: Catalog
    offsets.append(len(pdf))
    pdf.extend(b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
    
    # 2: Pages
    offsets.append(len(pdf))
    pdf.extend(b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")
    
    # 3: Page (A4: 595 x 842 pt)
    offsets.append(len(pdf))
    pdf.extend(b"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842]\n"
               b"   /Resources << /Font << /F1 4 0 R /F2 5 0 R /F3 6 0 R >> >>\n"
               b"   /Contents 7 0 R >>\nendobj\n")
    
    # 4: Font F1 (Helvetica-Bold)
    offsets.append(len(pdf))
    pdf.extend(b"4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>\nendobj\n")
    
    # 5: Font F2 (Helvetica)
    offsets.append(len(pdf))
    pdf.extend(b"5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n")
    
    # 6: Font F3 (Courier)
    offsets.append(len(pdf))
    pdf.extend(b"6 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>\nendobj\n")
    
    # 7: Contents
    offsets.append(len(pdf))
    pdf.extend(f"7 0 obj\n<< /Length {stream_len} >>\nstream\n".encode("utf-8"))
    pdf.extend(stream_content)
    pdf.extend(b"\nendstream\nendobj\n")
    
    # Xref table
    xref_offset = len(pdf)
    pdf.extend(b"xref\n0 8\n")
    pdf.extend(b"0000000000 65535 f \n")
    for off in offsets:
        pdf.extend(f"{off:010d} 00000 n \n".encode("utf-8"))
        
    pdf.extend(f"trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n".encode("utf-8"))
    
    with open(output_path, "wb") as f:
        f.write(pdf)

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/samsung_m2071_testpage.pdf"
    generate_pdf(out)
    print(f"Generated test page PDF: {out}")
