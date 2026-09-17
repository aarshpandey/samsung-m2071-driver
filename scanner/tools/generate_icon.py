#!/usr/bin/env python3
"""
generate_icon.py - Generate macOS AppIcon.icns for Samsung Scanner
Pure Python (standard library) + sips + iconutil.
"""

import os
import math
import struct
import subprocess
import shutil

def generate_icon_ppm(filename, size=1024):
    width = size
    height = size
    
    # We will write an RGB PPM file
    # Background: transparent or rounded squircle
    pixels = bytearray(width * height * 3)
    
    # Squircle radius & center
    cx, cy = width / 2.0, height / 2.0
    half = width * 0.44  # size of rounded rect
    corner_r = width * 0.22
    
    for y in range(height):
        ny = (y - cy) / half
        row_offset = y * width * 3
        
        for x in range(width):
            nx = (x - cx) / half
            
            # Check if inside squircle
            # Approximate superellipse / rounded rect
            dx = max(abs(x - cx) - (half - corner_r), 0)
            dy = max(abs(y - cy) - (half - corner_r), 0)
            dist = math.sqrt(dx*dx + dy*dy)
            
            idx = row_offset + x * 3
            
            if dist > corner_r:
                # Outside squircle: macOS dark transparent background simulation (or dark slate)
                pixels[idx] = 0
                pixels[idx+1] = 0
                pixels[idx+2] = 0
                continue
                
            # Inside squircle: vertical gradient from dark steel blue (#16324f) to (#081422)
            grad = y / height
            r = int(22 * (1 - grad) + 8 * grad)
            g = int(50 * (1 - grad) + 20 * grad)
            b = int(79 * (1 - grad) + 34 * grad)
            
            # Scanner bed border (inner rect)
            bed_x0, bed_y0 = int(width * 0.16), int(height * 0.18)
            bed_x1, bed_y1 = int(width * 0.84), int(height * 0.82)
            
            if bed_x0 <= x <= bed_x1 and bed_y0 <= y <= bed_y1:
                # Scanner body edge
                if x == bed_x0 or x == bed_x1 or y == bed_y0 or y == bed_y1:
                    r, g, b = 180, 190, 205
                elif x <= bed_x0 + 8 or x >= bed_x1 - 8 or y <= bed_y0 + 8 or y >= bed_y1 - 8:
                    r, g, b = 120, 130, 145
                else:
                    # Glass bed (dark glass #101a24)
                    r, g, b = 18, 28, 40
                    
                    # Document on glass (tilted or centered)
                    doc_x0, doc_y0 = int(width * 0.26), int(height * 0.24)
                    doc_x1, doc_y1 = int(width * 0.74), int(height * 0.76)
                    
                    if doc_x0 <= x <= doc_x1 and doc_y0 <= y <= doc_y1:
                        # Document shadow
                        r, g, b = 245, 247, 250
                        
                        # Document header bar
                        if doc_y0 + 20 <= y <= doc_y0 + 40 and doc_x0 + 30 <= x <= doc_x1 - 100:
                            r, g, b = 0, 113, 227
                            
                        # Document text lines
                        for line_y in range(doc_y0 + 70, doc_y1 - 40, 32):
                            if line_y <= y <= line_y + 8:
                                line_w = (doc_x1 - doc_x0 - 60)
                                if (line_y // 32) % 3 == 0:
                                    line_w = int(line_w * 0.65)
                                if doc_x0 + 30 <= x <= doc_x0 + 30 + line_w:
                                    r, g, b = 180, 185, 195

                    # Laser scan beam across the bed (at y ≈ 48% height)
                    beam_y = int(height * 0.50)
                    beam_dist = abs(y - beam_y)
                    if beam_dist < 18:
                        intensity = math.exp(-(beam_dist**2) / 36.0)
                        # Cyan glowing beam
                        r = int(r * (1 - intensity) + 0 * intensity)
                        g = int(g * (1 - intensity) + 240 * intensity)
                        b = int(b * (1 - intensity) + 255 * intensity)
                        
            # Edge highlight on squircle
            if corner_r - 2 <= dist <= corner_r:
                r = min(255, r + 60)
                g = min(255, g + 60)
                b = min(255, b + 60)
                
            pixels[idx] = max(0, min(255, r))
            pixels[idx+1] = max(0, min(255, g))
            pixels[idx+2] = max(0, min(255, b))
            
    header = f"P6\n{width} {height}\n255\n".encode("ascii")
    with open(filename, "wb") as f:
        f.write(header)
        f.write(pixels)

def make_icns():
    workdir = "/tmp/samsung_icon_build"
    iconset_dir = os.path.join(workdir, "AppIcon.iconset")
    ppm_path = os.path.join(workdir, "base_1024.ppm")
    png_path = os.path.join(workdir, "base_1024.png")
    
    if os.path.exists(workdir):
        shutil.rmtree(workdir)
    os.makedirs(iconset_dir, exist_ok=True)
    
    print("Generating base icon graphic (1024x1024)...")
    generate_icon_ppm(ppm_path, 1024)
    
    # Convert PPM to PNG with sips
    subprocess.run(["sips", "-s", "format", "png", ppm_path, "--out", png_path],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                   
    # Icon sizes required for Apple iconset
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    
    print("Generating iconset resolutions...")
    for sz, name in sizes:
        dest = os.path.join(iconset_dir, name)
        subprocess.run(["sips", "-z", str(sz), str(sz), png_path, "--out", dest],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                       
    icns_out = os.path.join(workdir, "AppIcon.icns")
    print("Building AppIcon.icns via iconutil...")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_out], check=True)
    
    dest_icns = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Samsung Scanner.app", "Contents", "Resources", "AppIcon.icns"))
    shutil.copyfile(icns_out, dest_icns)
    print(f"Successfully created: {dest_icns}")
    shutil.rmtree(workdir)

if __name__ == "__main__":
    make_icns()
