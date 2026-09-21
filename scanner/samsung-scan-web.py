#!/usr/bin/env python3
"""
samsung-scan-web.py - Local Web Interface for Samsung Xpress M2071 / M2070 Scanner.
Zero external dependencies. Accessible via any browser (Safari, Chrome, etc.) on http://localhost:8080.
"""

import os
import sys
import json
import time
import subprocess
import tempfile
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
import webbrowser
import threading

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def find_engine_bin():
    candidates = [
        os.environ.get("SAMSUNG_SCAN_ENGINE"),
        os.path.join(SCRIPT_DIR, "bin", "samsung-scan-engine"),
        os.path.join(SCRIPT_DIR, "samsung-scan-engine"),
        os.path.join(SCRIPT_DIR, "..", "MacOS", "samsung-scan-engine"),
        "/Library/Printers/Samsung/Scanner/samsung-scan-engine",
        "/usr/local/bin/samsung-scan-engine",
    ]
    for c in candidates:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return os.path.abspath(c)
    return os.path.join(SCRIPT_DIR, "bin", "samsung-scan-engine")

ENGINE_BIN = find_engine_bin()
PORT = 8080

LAST_SCAN_LOCK = threading.Lock()
LAST_SCAN_PATH = None
LAST_SCAN_MIME = "application/pdf"
LAST_PREVIEW_PATH = None

HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Samsung Xpress Scanner</title>
<style>
  :root {
    --bg-color: #f5f5f7;
    --card-bg: #ffffff;
    --text-color: #1d1d1f;
    --primary: #0071e3;
    --primary-hover: #0077ed;
    --border: #d2d2d7;
    --success: #34c759;
  }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", Roboto, sans-serif;
    background-color: var(--bg-color);
    color: var(--text-color);
    margin: 0;
    padding: 24px;
    display: flex;
    justify-content: center;
  }
  .container {
    width: 100%;
    max-width: 860px;
    background: var(--card-bg);
    border-radius: 18px;
    box-shadow: 0 8px 30px rgba(0,0,0,0.08);
    overflow: hidden;
  }
  .header {
    background: linear-gradient(135deg, #0f2439, #1a3a5c);
    color: white;
    padding: 24px 28px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .header h1 {
    margin: 0;
    font-size: 22px;
    font-weight: 600;
  }
  .header .badge {
    font-size: 13px;
    background: rgba(255,255,255,0.15);
    padding: 6px 14px;
    border-radius: 20px;
    border: 1px solid rgba(255,255,255,0.25);
  }
  .content {
    display: grid;
    grid-template-columns: 340px 1fr;
    gap: 24px;
    padding: 28px;
  }
  @media(max-width: 720px) {
    .content { grid-template-columns: 1fr; }
  }
  .controls {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  .form-group {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  label {
    font-size: 13px;
    font-weight: 600;
    color: #6e6e73;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }
  select, input {
    padding: 10px 14px;
    border: 1px solid var(--border);
    border-radius: 10px;
    font-size: 15px;
    background: #fff;
    outline: none;
    transition: border-color 0.2s;
  }
  select:focus, input:focus {
    border-color: var(--primary);
  }
  .btn-group {
    display: flex;
    gap: 12px;
    margin-top: 10px;
  }
  button {
    padding: 14px;
    border-radius: 12px;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
    border: none;
    transition: all 0.2s;
  }
  .btn-primary {
    background: var(--primary);
    color: white;
    flex: 2;
  }
  .btn-primary:hover { background: var(--primary-hover); }
  .btn-secondary {
    background: #e8e8ed;
    color: #1d1d1f;
    flex: 1;
  }
  .btn-secondary:hover { background: #dcdce2; }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
  .progress-wrap {
    margin-top: 10px;
    display: none;
  }
  .progress-bar {
    width: 100%;
    height: 8px;
    background: #e8e8ed;
    border-radius: 4px;
    overflow: hidden;
  }
  .progress-fill {
    height: 100%;
    width: 0%;
    background: var(--primary);
    transition: width 0.2s;
  }
  .progress-text {
    font-size: 13px;
    color: #6e6e73;
    margin-top: 6px;
    text-align: center;
  }
  .preview-area {
    background: #fbfbfd;
    border: 2px dashed #d2d2d7;
    border-radius: 14px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    min-height: 400px;
    position: relative;
    padding: 16px;
  }
  .preview-area img {
    max-width: 100%;
    max-height: 480px;
    border-radius: 8px;
    box-shadow: 0 4px 15px rgba(0,0,0,0.1);
  }
  .download-btn {
    margin-top: 16px;
    display: none;
    background: var(--success);
    color: white;
    text-decoration: none;
    padding: 10px 20px;
    border-radius: 10px;
    font-weight: 600;
    font-size: 14px;
  }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <h1>Samsung Xpress Scanner</h1>
    <div class="badge" id="connStatus">Detecting...</div>
  </div>
  <div class="content">
    <div class="controls">
      <div class="form-group">
        <label>Color Mode</label>
        <select id="mode">
          <option value="color" selected>Full Color (24-bit RGB)</option>
          <option value="gray">Grayscale (8-bit)</option>
          <option value="lineart">Black & White (LineArt)</option>
        </select>
      </div>

      <div class="form-group">
        <label>Resolution</label>
        <select id="dpi">
          <option value="75">75 DPI (Draft / Preview)</option>
          <option value="150">150 DPI (Fast)</option>
          <option value="300" selected>300 DPI (Recommended Document)</option>
          <option value="600">600 DPI (High Definition Photo)</option>
        </select>
      </div>

      <div class="form-group">
        <label>Page Size</label>
        <select id="size">
          <option value="a4" selected>A4 (210 x 297 mm)</option>
          <option value="letter">US Letter (8.5 x 11 in)</option>
          <option value="legal">US Legal (8.5 x 14 in)</option>
        </select>
      </div>

      <div class="form-group">
        <label>Format</label>
        <select id="format">
          <option value="pdf" selected>PDF Document</option>
          <option value="png">PNG Image</option>
          <option value="jpg">JPEG Photo</option>
        </select>
      </div>

      <div class="btn-group">
        <button class="btn-secondary" id="btnPreview" onclick="startScan(true)">👁 Preview</button>
        <button class="btn-primary" id="btnScan" onclick="startScan(false)">📥 Scan Document</button>
      </div>

      <div class="progress-wrap" id="progressWrap">
        <div class="progress-bar"><div class="progress-fill" id="progressFill"></div></div>
        <div class="progress-text" id="progressText">Initializing scan...</div>
      </div>
    </div>

    <div class="preview-area" id="previewArea">
      <div id="placeholderText" style="color: #86868b; text-align: center;">
        <svg width="48" height="48" fill="none" stroke="currentColor" viewBox="0 0 24 24" style="margin-bottom: 8px;">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
        </svg><br>
        Scanned preview will appear here
      </div>
      <img id="previewImg" style="display:none;" />
      <a href="/download" class="download-btn" id="downloadBtn" download>Download Scanned File</a>
    </div>
  </div>
</div>

<script>
  function checkStatus() {
    fetch('/status')
      .then(r => r.json())
      .then(data => {
        const b = document.getElementById('connStatus');
        if (data.connected) {
          b.textContent = '● ' + data.model;
          b.style.color = '#34c759';
        } else {
          b.textContent = '○ Scanner Not Connected (Demo Mode Ready)';
          b.style.color = '#ff9f0a';
        }
      });
  }
  checkStatus();

  function startScan(isPreview) {
    const btnScan = document.getElementById('btnScan');
    const btnPreview = document.getElementById('btnPreview');
    const pWrap = document.getElementById('progressWrap');
    const pFill = document.getElementById('progressFill');
    const pText = document.getElementById('progressText');
    const dlBtn = document.getElementById('downloadBtn');

    btnScan.disabled = true;
    btnPreview.disabled = true;
    pWrap.style.display = 'block';
    pFill.style.width = '10%';
    pText.textContent = isPreview ? 'Generating preview scan...' : 'Scanning document...';
    dlBtn.style.display = 'none';

    const payload = {
      mode: document.getElementById('mode').value,
      dpi: isPreview ? 75 : document.getElementById('dpi').value,
      size: document.getElementById('size').value,
      format: isPreview ? 'png' : document.getElementById('format').value,
      preview: isPreview
    };

    fetch('/scan', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    .then(r => r.json())
    .then(data => {
      pFill.style.width = '100%';
      pText.textContent = 'Scan complete!';
      btnScan.disabled = false;
      btnPreview.disabled = false;

      if (data.success) {
        const img = document.getElementById('previewImg');
        const placeholder = document.getElementById('placeholderText');
        img.src = '/preview?' + new Date().getTime();
        img.style.display = 'block';
        placeholder.style.display = 'none';

        if (!isPreview) {
          dlBtn.style.display = 'inline-block';
          dlBtn.setAttribute('download', 'Scan.' + payload.format);
        }
      } else {
        alert('Scan Error: ' + (data.error || 'Failed to scan'));
      }
    })
    .catch(e => {
      btnScan.disabled = false;
      btnPreview.disabled = false;
      alert('Error during scan: ' + e);
    });
  }
</script>
</body>
</html>
"""

class ScanRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global LAST_SCAN_PATH, LAST_SCAN_MIME
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path == "/" or parsed.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode("utf-8"))

        elif parsed.path == "/status":
            conn = False
            model = "Samsung M2070/M2071"
            try:
                res = subprocess.run([ENGINE_BIN, "--detect"], stdout=subprocess.PIPE, text=True)
                if "Samsung" in res.stdout and "No Samsung" not in res.stdout:
                    conn = True
            except Exception:
                pass

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"connected": conn, "model": model}).encode("utf-8"))

        elif parsed.path == "/preview":
            # Return preview image (PNG)
            with LAST_SCAN_LOCK:
                preview_png = LAST_PREVIEW_PATH
            if preview_png and os.path.exists(preview_png):
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.end_headers()
                with open(preview_png, "rb") as f:
                    self.wfile.write(f.read())
            else:
                self.send_error(404, "No preview available")

        elif parsed.path == "/download":
            with LAST_SCAN_LOCK:
                scan_path = LAST_SCAN_PATH
                scan_mime = LAST_SCAN_MIME
            if scan_path and os.path.exists(scan_path):
                self.send_response(200)
                self.send_header("Content-Type", scan_mime)
                self.send_header("Content-Disposition", f"attachment; filename={os.path.basename(scan_path)}")
                self.end_headers()
                with open(scan_path, "rb") as f:
                    self.wfile.write(f.read())
            else:
                self.send_error(404, "No scanned file available")
        else:
            self.send_error(404)

    def do_POST(self):
        global LAST_SCAN_PATH, LAST_SCAN_MIME
        if self.path == "/scan":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                params = json.loads(body.decode("utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                self.send_error(400, "Invalid JSON")
                return

            # VULN-2 fix: strict allowlists — reject anything not in these sets
            ALLOWED_MODES = {"color", "gray", "lineart"}
            ALLOWED_SIZES = {"a4", "letter", "legal"}
            ALLOWED_FMTS  = {"pdf", "png", "jpg"}
            ALLOWED_DPIS  = {75, 100, 150, 200, 300, 600, 1200}

            mode = params.get("mode", "color")
            size = params.get("size", "a4")
            fmt  = params.get("format", "pdf")
            is_preview = bool(params.get("preview", False))

            try:
                dpi = int(params.get("dpi", 300))
            except (TypeError, ValueError):
                dpi = 300

            # Reject invalid values immediately
            if mode not in ALLOWED_MODES:
                self.send_error(400, f"Invalid mode: {mode}")
                return
            if size not in ALLOWED_SIZES:
                self.send_error(400, f"Invalid size: {size}")
                return
            if fmt not in ALLOWED_FMTS:
                self.send_error(400, f"Invalid format: {fmt}")
                return
            if dpi not in ALLOWED_DPIS:
                dpi = 300  # silently reset to safe default

            # VULN-3 fix: use mkstemp (atomic, no race window) instead of mktemp
            fd, out_file = tempfile.mkstemp(suffix=f".{fmt}")
            os.close(fd)

            fd_prev, preview_png = tempfile.mkstemp(suffix=".png")
            os.close(fd_prev)

            cmd = [ENGINE_BIN, "-m", mode, "-d", str(dpi), "-s", size, "-o", out_file]

            # Try direct hardware scan
            proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

            if proc.returncode != 0:
                # If scanner offline, use synthetic test pattern
                demo_cmd = [ENGINE_BIN, "--test-pattern", "-m", mode, "-d", str(dpi), "-s", size, "-o", out_file]
                proc = subprocess.run(demo_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

            if proc.returncode == 0 and os.path.exists(out_file):
                if fmt == "pdf":
                    mime = "application/pdf"
                elif fmt == "png":
                    mime = "image/png"
                else:
                    mime = "image/jpeg"

                # Generate PNG preview for browser display
                if fmt == "png":
                    subprocess.run(["cp", out_file, preview_png])
                else:
                    subprocess.run(["/usr/bin/sips", "-s", "format", "png", out_file,
                                    "--resampleWidth", "700", "--out", preview_png],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                
                global LAST_SCAN_PATH, LAST_SCAN_MIME, LAST_PREVIEW_PATH
                with LAST_SCAN_LOCK:
                    LAST_SCAN_PATH = out_file
                    LAST_SCAN_MIME = mime
                    LAST_PREVIEW_PATH = preview_png

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "file": out_file}).encode("utf-8"))
            else:
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": proc.stderr}).encode("utf-8"))


def run_server():
    server = HTTPServer(("localhost", PORT), ScanRequestHandler)
    print(f"==> Samsung Scanner Web Interface running at: http://localhost:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()

if __name__ == "__main__":
    t = threading.Thread(target=run_server, daemon=True)
    t.start()
    time.sleep(0.5)
    webbrowser.open(f"http://localhost:{PORT}")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping web scanner interface.")
