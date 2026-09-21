#include "scanner_engine.h"
#include <iostream>
#include <cmath>
#include <cstring>
#include <unistd.h>
#include <algorithm>

#ifdef __APPLE__
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#endif

// Protocol Command Constants
static const uint8_t REQ_CODE_A       = 0x1b;
static const uint8_t REQ_CODE_B       = 0xa8;
static const uint8_t RES_CODE         = 0xa8;

static const uint8_t CMD_ABORT           = 0x06;
static const uint8_t CMD_INQUIRY         = 0x12;
static const uint8_t CMD_RESERVE_UNIT    = 0x16;
static const uint8_t CMD_RELEASE_UNIT    = 0x17;
static const uint8_t CMD_SET_WINDOW      = 0x24;
static const uint8_t CMD_READ            = 0x28;
static const uint8_t CMD_READ_IMAGE      = 0x29;
static const uint8_t CMD_OBJECT_POSITION = 0x31;

[[maybe_unused]] static const uint8_t STATUS_GOOD   = 0x00;
[[maybe_unused]] static const uint8_t STATUS_CHECK  = 0x02;
[[maybe_unused]] static const uint8_t STATUS_CANCEL = 0x04;
[[maybe_unused]] static const uint8_t STATUS_BUSY   = 0x08;

[[maybe_unused]] static const uint8_t MSG_PRODUCT_INFO   = 0x10;
[[maybe_unused]] static const uint8_t MSG_SCANNER_STATE  = 0x20;
[[maybe_unused]] static const uint8_t MSG_SCANNING_PARAM = 0x30;
[[maybe_unused]] static const uint8_t MSG_LINK_BLOCK     = 0x80;
[[maybe_unused]] static const uint8_t MSG_END_BLOCK      = 0x81;

static const int RES_DPI_CODES[] = {
    75, 0, 150, 0, 0, 300, 0, 600, 1200, 200, 100, 2400, 4800, 9600
};

static const int INQ_DPI_BITS[] = {
    75, 150, 0, 0,
    200, 300, 0, 0,
    600, 0, 0, 1200,
    100, 0, 0, 2400,
    0, 4800, 0, 9600
};

ScannerEngine::ScannerEngine(ITransport *transport)
    : _io(transport), _cancelled(false), _external_cancel(nullptr)
{
}

ScannerEngine::~ScannerEngine() {
}

void ScannerEngine::set_cancel_flag(std::atomic<bool> *flag) {
    _external_cancel = flag;
}

bool ScannerEngine::is_cancelled() const {
    return _cancelled.load() || (_external_cancel && _external_cancel->load());
}

void ScannerEngine::cancel() {
    bool already = _cancelled.exchange(true);
    if (!already) {
        std::cerr << "\n[*] Scan cancellation requested - aborting scanner carriage..." << std::endl;
    }
}

bool ScannerEngine::abort_and_release() {
    if (!_io || !_io->is_open()) return false;
    std::cerr << "[*] Halting scanner carriage motor and releasing unit..." << std::endl;

    // 1. Drain pending bulk/response data from EP IN
    _io->drain();

    // 2. Clear any stalled pipe
    _io->clear_halt();

    // 3. Send CMD_ABORT
    uint8_t cmd_abort[4] = { REQ_CODE_A, REQ_CODE_B, CMD_ABORT, 0x00 };
    uint8_t resp[128] = {0};
    size_t actual = 0;
    if (_io->send_cmd(cmd_abort, 4)) {
        _io->recv_resp(resp, sizeof(resp), &actual);
    }

    // 4. Drain again in case abort generated residual bulk data
    _io->drain();

    // 5. Send CMD_RELEASE_UNIT (parks carriage motor and frees reservation)
    uint8_t cmd_rel[4] = { REQ_CODE_A, REQ_CODE_B, CMD_RELEASE_UNIT, 0x00 };
    if (_io->send_cmd(cmd_rel, 4)) {
        _io->recv_resp(resp, sizeof(resp), &actual);
    }

    return true;
}

bool ScannerEngine::release_unit() {
    if (!_io || !_io->is_open()) return false;
    uint8_t cmd_rel[4] = { REQ_CODE_A, REQ_CODE_B, CMD_RELEASE_UNIT, 0x00 };
    uint8_t resp[128] = {0};
    size_t actual = 0;
    if (!_io->send_cmd(cmd_rel, 4)) return false;
    return _io->recv_resp(resp, sizeof(resp), &actual);
}

uint8_t ScannerEngine::dpi_to_code(int dpi) {
    for (size_t i = 0; i < sizeof(RES_DPI_CODES) / sizeof(int); i++) {
        if (RES_DPI_CODES[i] == dpi) return (uint8_t)i;
    }
    return 5; // Default 300 DPI
}

uint8_t ScannerEngine::mode_to_code(ScanMode mode) {
    switch (mode) {
        case ScanMode::Color:     return 0x05; // MODE_RGB24
        case ScanMode::Grayscale: return 0x03; // MODE_GRAY8
        case ScanMode::LineArt:   return 0x00; // MODE_LINEART
    }
    return 0x05;
}

bool ScannerEngine::decode_jpeg_strip(const uint8_t *jpeg_data, size_t jpeg_len,
                                     std::vector<uint8_t> &out_rgb, int &out_w, int &out_h) {
#ifdef __APPLE__
    if (!jpeg_data || jpeg_len < 4) return false;

    CFDataRef cf_data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, jpeg_data, jpeg_len, kCFAllocatorNull);
    if (!cf_data) return false;

    CGImageSourceRef src = CGImageSourceCreateWithData(cf_data, nullptr);
    CFRelease(cf_data);
    if (!src) return false;

    CGImageRef image = CGImageSourceCreateImageAtIndex(src, 0, nullptr);
    CFRelease(src);
    if (!image) return false;

    out_w = (int)CGImageGetWidth(image);
    out_h = (int)CGImageGetHeight(image);

    std::vector<uint8_t> rgba(out_w * out_h * 4);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(rgba.data(), out_w, out_h, 8, out_w * 4, cs,
                                            kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);

    if (!ctx) {
        CGImageRelease(image);
        return false;
    }

    CGContextDrawImage(ctx, CGRectMake(0, 0, out_w, out_h), image);
    CGContextRelease(ctx);
    CGImageRelease(image);

    // Convert RGBA to RGB in out_rgb
    out_rgb.resize(out_w * out_h * 3);
    for (int i = 0; i < out_w * out_h; i++) {
        out_rgb[i * 3 + 0] = rgba[i * 4 + 0];
        out_rgb[i * 3 + 1] = rgba[i * 4 + 1];
        out_rgb[i * 3 + 2] = rgba[i * 4 + 2];
    }
    return true;
#else
    return false;
#endif
}

bool ScannerEngine::send_cmd_wait(uint8_t cmd_code, uint8_t *resp, size_t resplen, int timeout_sec) {
    uint8_t cmd[4] = { REQ_CODE_A, REQ_CODE_B, cmd_code, 0x00 };
    int elapsed_ms = 0;
    int sleep_ms = 50;

    while (elapsed_ms < timeout_sec * 1000) {
        if (is_cancelled()) return false;

        if (!_io->send_cmd(cmd, 4)) {
            return false;
        }

        size_t actual_len = 0;
        if (!_io->recv_resp(resp, resplen, &actual_len)) {
            return false;
        }

        if (actual_len >= 2 && resp[0] == RES_CODE) {
            uint8_t status = resp[1];
            if (status == STATUS_GOOD) {
                return true;
            } else if (status == STATUS_BUSY) {
                usleep(sleep_ms * 1000);
                elapsed_ms += sleep_ms;
                if (sleep_ms < 500) sleep_ms *= 2;
                continue;
            } else if (status == STATUS_CHECK && actual_len >= 6) {
                uint16_t st = (resp[4] << 8) | resp[5];
                // 0x080 (STATE_WARMING), 0x400 (STATE_RESOURCE_BUSY), 0x008 (STATE_RESET), 0x100 (STATE_LOCKING)
                if ((st & 0x588) != 0 || st == 0) {
                    usleep(sleep_ms * 1000);
                    elapsed_ms += sleep_ms;
                    if (sleep_ms < 500) sleep_ms *= 2;
                    continue;
                }
                std::cerr << "[-] Scanner check condition: 0x" << std::hex << st << std::dec << std::endl;
                return false;
            } else {
                std::cerr << "[-] Scanner status error: 0x" << std::hex << (int)status << std::dec << std::endl;
                return false;
            }
        }

        usleep(sleep_ms * 1000);
        elapsed_ms += sleep_ms;
    }
    return false;
}

bool ScannerEngine::probe(ScannerCaps &caps) {
    if (!_io->is_open()) {
        if (!_io->open()) return false;
    }

    uint8_t cmd[4] = { REQ_CODE_A, REQ_CODE_B, CMD_INQUIRY, 0x00 };
    if (!_io->send_cmd(cmd, 4)) return false;

    uint8_t resp[70] = {0};
    size_t actual = 0;
    if (!_io->recv_resp(resp, sizeof(resp), &actual) || actual < 70) {
        std::cerr << "[-] Error: Failed to receive INQUIRY response from scanner" << std::endl;
        return false;
    }

    if (resp[0] != RES_CODE || resp[3] != MSG_PRODUCT_INFO) {
        std::cerr << "[-] Error: Invalid INQUIRY response format" << std::endl;
        return false;
    }

    // Parse vendor (bytes 4..0x23)
    char vendor_buf[32] = {0};
    char model_buf[32] = {0};
    int p = 4;
    int vi = 0;
    while (p < 0x24 && resp[p] && resp[p] != ' ' && vi < 31) {
        vendor_buf[vi++] = resp[p++];
    }
    while (p < 0x24 && (!resp[p] || resp[p] == ' ')) p++;
    int mi = 0;
    while (p < 0x24 && resp[p] && mi < 31) {
        model_buf[mi++] = resp[p++];
    }

    caps.vendor = vendor_buf[0] ? vendor_buf : "Samsung";
    caps.model = model_buf[0] ? model_buf : "Xpress M2070/M2071 Series";

    int res_bits = (resp[0x37] << 16) | (resp[0x24] << 8) | resp[0x25];
    for (size_t i = 0; i < sizeof(INQ_DPI_BITS) / sizeof(int); i++) {
        if (INQ_DPI_BITS[i] && (res_bits & (1 << i))) {
            caps.supported_dpis.push_back(INQ_DPI_BITS[i]);
        }
    }
    std::sort(caps.supported_dpis.begin(), caps.supported_dpis.end());
    if (caps.supported_dpis.empty()) {
        caps.supported_dpis = { 75, 100, 150, 200, 300, 600, 1200 };
    }

    caps.has_color = (resp[0x27] & 0x20) != 0; // bit 5 for RGB24
    caps.max_width_points = (resp[0x28] << 24) | (resp[0x29] << 16) | (resp[0x2a] << 8) | resp[0x2b];
    caps.max_length_points = (resp[0x2c] << 24) | (resp[0x2d] << 16) | (resp[0x2e] << 8) | resp[0x2f];
    caps.line_order = resp[0x31];
    caps.has_adf = (resp[0x26] & 0x03) != 0;
    caps.supports_jpeg = (resp[0x32] & (1 << 6)) != 0;

    if (caps.max_width_points == 0) caps.max_width_points = 10200; // ~8.5 inches
    if (caps.max_length_points == 0) caps.max_length_points = 14040; // ~11.7 inches

    return true;
}

bool ScannerEngine::scan(const ScanParameters &params, ScannedImage &out_img, ScanProgressCallback progress_cb) {
    _cancelled = false;

    if (!_io->is_open()) {
        if (!_io->open()) {
            std::cerr << "[-] Error: Could not open connection to scanner" << std::endl;
            return false;
        }
    }

    ScannerCaps caps;
    if (!probe(caps)) {
        std::cerr << "[-] Error: Scanner inquiry failed" << std::endl;
        return false;
    }

    std::cout << "[+] Connected to: " << caps.vendor << " " << caps.model << std::endl;

    // Step 1: Reserve scanner unit
    uint8_t resp_buf[128] = {0};
    if (!send_cmd_wait(CMD_RESERVE_UNIT, resp_buf, sizeof(resp_buf), 15)) {
        std::cerr << "[-] Error: Could not reserve scanner unit" << std::endl;
        return false;
    }

    // Step 2: Set window (scan parameters)
    double width_in = params.width_mm / 25.4;
    double length_in = params.length_mm / 25.4;
    double off_x_in = params.offset_x_mm / 25.4;
    double off_y_in = params.offset_y_mm / 25.4;

    int win_width = (int)std::round(width_in * 1200.0);
    int win_len   = (int)std::round(length_in * 1200.0);

    if (win_width > caps.max_width_points) win_width = caps.max_width_points;
    if (win_len > caps.max_length_points) win_len = caps.max_length_points;

    uint8_t res_code = dpi_to_code(params.dpi);
    uint8_t composition = mode_to_code(params.mode);
    uint8_t compression = 0x00;
    if (params.mode == ScanMode::Color && caps.supports_jpeg) {
        // Use Samsung onboard hardware JPEG compression to prevent ASIC buffer overflow
        compression = 0x06;
    }

    // Map threshold to protocol range 0..4 (default 2)
    uint8_t threshold_code = 2;
    if (params.threshold >= 0 && params.threshold <= 4) {
        threshold_code = (uint8_t)params.threshold;
    } else {
        int t = params.threshold;
        if (t > 70) t = (t * 40 / 255) + 30;
        if (t < 30) t = 30;
        if (t > 70) t = 70;
        threshold_code = (uint8_t)((t - 30) / 10);
    }

    uint8_t cmd_win[25] = {
        REQ_CODE_A, REQ_CODE_B, CMD_SET_WINDOW, 0x15, MSG_SCANNING_PARAM,
        (uint8_t)(win_width >> 24),
        (uint8_t)(win_width >> 16),
        (uint8_t)(win_width >> 8),
        (uint8_t)(win_width),
        (uint8_t)(win_len >> 24),
        (uint8_t)(win_len >> 16),
        (uint8_t)(win_len >> 8),
        (uint8_t)(win_len),
        res_code, // X resolution code
        res_code, // Y resolution code
        (uint8_t)std::floor(off_x_in),
        (uint8_t)((off_x_in - std::floor(off_x_in)) * 100.0),
        (uint8_t)std::floor(off_y_in),
        (uint8_t)((off_y_in - std::floor(off_y_in)) * 100.0),
        composition,
        compression,
        0x00,
        threshold_code,
        0x40, // DOC_FLATBED
        0x00
    };

    if (!_io->send_cmd(cmd_win, sizeof(cmd_win))) {
        std::cerr << "[-] Error: Failed to send SET_WINDOW command" << std::endl;
        release_unit();
        return false;
    }

    size_t actual = 0;
    if (!_io->recv_resp(resp_buf, sizeof(resp_buf), &actual) ||
        (resp_buf[1] != STATUS_GOOD && resp_buf[1] != STATUS_BUSY)) {
        std::cerr << "[-] Error: SET_WINDOW rejected by scanner (status: 0x"
                  << std::hex << (int)resp_buf[1] << std::dec << ")" << std::endl;
        release_unit();
        return false;
    }

    if (is_cancelled()) {
        abort_and_release();
        return false;
    }

    // Step 3: Move scanner head to object position
    if (!send_cmd_wait(CMD_OBJECT_POSITION, resp_buf, sizeof(resp_buf), 30)) {
        std::cerr << "[-] Error: OBJECT_POSITION failed" << std::endl;
        abort_and_release();
        return false;
    }

    if (is_cancelled()) {
        abort_and_release();
        return false;
    }

    // Calculate expected dimensions
    int channels = (params.mode == ScanMode::Color) ? 3 : 1;
    int expected_width = (int)std::round(width_in * params.dpi);
    int expected_height = (int)std::round(length_in * params.dpi);

    out_img.width = 0;
    out_img.height = 0; // will count scanned lines
    out_img.dpi = params.dpi;
    out_img.channels = channels;
    out_img.bits_per_channel = (params.mode == ScanMode::LineArt) ? 1 : 8;
    out_img.data.clear();

    // Step 4: Block read loop
    bool final_block = false;
    int total_lines_scanned = 0;
    int block_num = 0;

    std::vector<uint8_t> block_buffer;

    while (!final_block && !is_cancelled()) {
        // Query next block status (poll until ready or timeout)
        bool block_ready = false;
        int sleep_ms = 20;
        int wait_elapsed = 0;
        const int max_wait_ms = 35000;

        while (!block_ready && wait_elapsed < max_wait_ms && !is_cancelled()) {
            uint8_t cmd_read[4] = { REQ_CODE_A, REQ_CODE_B, CMD_READ, 0x00 };
            if (!_io->send_cmd(cmd_read, 4)) {
                std::cerr << "[-] Error: CMD_READ send failed" << std::endl;
                break;
            }

            size_t actual_len = 0;
            if (!_io->recv_resp(resp_buf, sizeof(resp_buf), &actual_len)) {
                std::cerr << "[-] Error: CMD_READ recv failed" << std::endl;
                break;
            }

            if (actual_len >= 2 && resp_buf[0] == RES_CODE) {
                if (resp_buf[1] == STATUS_GOOD) {
                    block_ready = true;
                    break;
                } else if (resp_buf[1] == STATUS_BUSY) {
                    usleep(sleep_ms * 1000);
                    wait_elapsed += sleep_ms;
                    if (sleep_ms < 100) sleep_ms += 10;
                } else {
                    std::cerr << "[-] Scanner status error on CMD_READ: 0x"
                              << std::hex << (int)resp_buf[1] << std::dec << std::endl;
                    break;
                }
            } else {
                usleep(50000);
                wait_elapsed += 50;
            }
        }

        if (!block_ready || is_cancelled()) {
            break;
        }

        final_block = (resp_buf[3] == MSG_END_BLOCK);
        uint32_t blocklen = (resp_buf[4] << 24) | (resp_buf[5] << 16) | (resp_buf[6] << 8) | resp_buf[7];
        int vert_lines = (resp_buf[8] << 8) | resp_buf[9];
        int horiz_pixels = (resp_buf[10] << 8) | resp_buf[11];

        // BUG-4 fix: cap blocklen to prevent std::bad_alloc crash on corrupted
        // scanner responses. 64 MB is well above any real scan block size.
        const uint32_t MAX_BLOCK_SIZE = 64u * 1024u * 1024u;
        if (blocklen > MAX_BLOCK_SIZE) {
            std::cerr << "[-] Warning: Implausible block size " << blocklen
                      << " bytes — aborting block read loop." << std::endl;
            break;
        }

        if (vert_lines <= 0 || horiz_pixels <= 0 || blocklen == 0) {
            if (final_block) break;
            usleep(20000);
            continue;
        }

        block_num++;

        // Command scanner to transmit the image block data
        uint8_t cmd_read_img[4] = { REQ_CODE_A, REQ_CODE_B, CMD_READ_IMAGE, 0x00 };
        if (!_io->send_cmd(cmd_read_img, 4)) {
            std::cerr << "[-] Error: CMD_READ_IMAGE send failed" << std::endl;
            break;
        }

        // Read bulk block data
        block_buffer.resize(blocklen);
        size_t total_received = 0;
        while (total_received < blocklen && !is_cancelled()) {
            size_t chunk_to_read = std::min((size_t)(blocklen - total_received), (size_t)65536);
            size_t bytes_read = 0;
            if (!_io->read_bulk(block_buffer.data() + total_received, chunk_to_read, &bytes_read) || bytes_read == 0) {
                break;
            }
            total_received += bytes_read;
        }

        if (total_received < blocklen && !is_cancelled()) {
            std::cerr << "[-] Warning: Incomplete block received (" << total_received << "/" << blocklen << ")" << std::endl;
        }

        // Process image data in this block
        if (compression == 0x06) {
            // Hardware JPEG strip
            std::vector<uint8_t> rgb_strip;
            int strip_w = 0, strip_h = 0;
            if (decode_jpeg_strip(block_buffer.data(), total_received, rgb_strip, strip_w, strip_h)) {
                if (out_img.width == 0) out_img.width = strip_w;
                out_img.data.insert(out_img.data.end(), rgb_strip.begin(), rgb_strip.end());
                total_lines_scanned += strip_h;
            } else {
                std::cerr << "[-] Warning: Failed to decode JPEG block #" << block_num << std::endl;
            }
        } else {
            // Uncompressed raw lines (Grayscale, LineArt, or uncompressed RGB)
            out_img.width = horiz_pixels;
            if (horiz_pixels <= 0) break;

            if (params.mode == ScanMode::Color && caps.line_order != 0) {
                // Planar color bands per line: RRR... GGG... BBB...
                size_t planar_line_size = (size_t)horiz_pixels * 3;
                for (int y = 0; y < vert_lines; y++) {
                    size_t line_offset = (size_t)y * planar_line_size;
                    if (line_offset + planar_line_size > total_received ||
                        line_offset + planar_line_size > block_buffer.size()) {
                        break;
                    }

                    const uint8_t *raw_line = block_buffer.data() + line_offset;
                    const uint8_t *r_band = raw_line;
                    const uint8_t *g_band = raw_line + horiz_pixels;
                    const uint8_t *b_band = raw_line + 2 * horiz_pixels;

                    for (int x = 0; x < horiz_pixels; x++) {
                        out_img.data.push_back(r_band[x]);
                        out_img.data.push_back(g_band[x]);
                        out_img.data.push_back(b_band[x]);
                    }
                    total_lines_scanned++;
                }
            } else {
                int bytes_per_pixel = channels;
                size_t raw_line_size = (size_t)horiz_pixels * bytes_per_pixel;

                for (int y = 0; y < vert_lines; y++) {
                    size_t line_offset = (size_t)y * raw_line_size;
                    if (line_offset + raw_line_size > total_received ||
                        line_offset + raw_line_size > block_buffer.size()) {
                        break;
                    }

                    const uint8_t *raw_line = block_buffer.data() + line_offset;
                    out_img.data.insert(out_img.data.end(), raw_line, raw_line + raw_line_size);
                    total_lines_scanned++;
                }
            }
        }

        if (progress_cb) {
            int pct = expected_height > 0 ? std::min(100, (int)(total_lines_scanned * 100 / expected_height)) : 50;
            progress_cb(pct, total_lines_scanned, expected_height);
        }
    }

    if (out_img.width == 0) out_img.width = expected_width;
    out_img.height = total_lines_scanned;

    // Step 5: Release unit cleanly
    if (is_cancelled()) {
        abort_and_release();
        std::cout << "[*] Scan cancelled by user." << std::endl;
        return false;
    }

    release_unit();

    std::cout << "[+] Scan complete! Scanned " << out_img.width << "x" << out_img.height
              << " pixels (" << total_lines_scanned << " lines) in "
              << (params.mode == ScanMode::Color ? "Color" : "Grayscale") << std::endl;

    return true;
}
