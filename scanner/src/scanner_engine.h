#ifndef SCANNER_ENGINE_H
#define SCANNER_ENGINE_H

#include "transport.h"
#include <string>
#include <vector>
#include <functional>
#include <atomic>

enum class ScanMode {
    Color,      // 24-bit RGB (0x05)
    Grayscale,  // 8-bit Gray (0x03)
    LineArt     // 1-bit B&W (0x00)
};

struct ScanParameters {
    ScanMode mode = ScanMode::Color;
    int dpi = 300;
    double width_mm = 210.0;   // Default A4
    double length_mm = 297.0;  // Default A4
    double offset_x_mm = 0.0;
    double offset_y_mm = 0.0;
    int threshold = 128;       // For LineArt
};

struct ScannedImage {
    int width = 0;
    int height = 0;
    int dpi = 300;
    int channels = 3;          // 3 for RGB, 1 for Gray/LineArt
    int bits_per_channel = 8;
    std::vector<uint8_t> data; // Interleaved RGB or Gray bitmap
};

struct ScannerCaps {
    std::string vendor;
    std::string model;
    int max_width_points = 0;  // 1200 dpi points
    int max_length_points = 0; // 1200 dpi points
    int line_order = 0;
    std::vector<int> supported_dpis;
    bool has_color = true;
    bool has_adf = false;
    bool supports_jpeg = false;
};

typedef std::function<void(int percent, int lines_scanned, int total_lines)> ScanProgressCallback;

class ScannerEngine {
public:
    ScannerEngine(ITransport *transport);
    ~ScannerEngine();

    bool probe(ScannerCaps &caps);
    bool scan(const ScanParameters &params, ScannedImage &out_img, ScanProgressCallback progress_cb = nullptr);
    void cancel();

private:
    ITransport *_io;
    std::atomic<bool> _cancelled;

    bool send_cmd_wait(uint8_t cmd_code, uint8_t *resp, size_t resplen, int timeout_sec = 10);
    bool abort_and_release();
    bool release_unit();
    uint8_t dpi_to_code(int dpi);
    uint8_t mode_to_code(ScanMode mode);
    bool decode_jpeg_strip(const uint8_t *jpeg_data, size_t jpeg_len,
                           std::vector<uint8_t> &out_rgb, int &out_w, int &out_h);
};

#endif // SCANNER_ENGINE_H
