#include "scanner_engine.h"
#include "transport_usb.h"
#include "image_writer.h"
#include <iostream>
#include <string>
#include <vector>
#include <cstring>
#include <cstdlib>
#include <memory>
#include <unistd.h>
#include <csignal>
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>

// Lock-free, async-signal-safe interruption flags.
static std::atomic<bool> g_interrupted(false);
static std::atomic<int>  g_signal_count(0);

static void handle_signal(int sig) {
    (void)sig;
    int count = ++g_signal_count;
    if (count >= 2) {
        _exit(1);
    }
    g_interrupted.store(true, std::memory_order_relaxed);
}

static void show_help(const char *prog) {
    std::cout << "Samsung Xpress M2071 / M2070 Native Scanner Engine (Apple Silicon arm64)\n"
              << "Usage: " << prog << " [options]\n\n"
              << "Options:\n"
              << "  -o, --output <file>       Output file path (.pdf, .png, .jpg, .pnm) [default: scan.pdf]\n"
              << "  -m, --mode <mode>         Scan mode: color, gray, lineart [default: color]\n"
              << "  -d, --dpi <dpi>           Resolution: 75, 100, 150, 200, 300, 600, 1200 [default: 300]\n"
              << "  -s, --size <size>         Page size: a4, letter, legal [default: a4]\n"
              << "      --preview             Quick low-res preview scan (75 DPI)\n"
              << "      --detect              List detected Samsung USB scanners\n"
              << "      --json-progress       Emit machine-readable JSON progress updates\n"
              << "      --test-pattern        Generate synthetic scan test image (no hardware required)\n"
              << "  -h, --help                Show this help message\n\n"
              << "Examples:\n"
              << "  " << prog << " -o document.pdf\n"
              << "  " << prog << " -m color -d 600 -o photo.png\n";
}

static void generate_test_pattern(const ScanParameters &params, ScannedImage &out_img) {
    int dpi = params.dpi;
    int w = (int)(params.width_mm / 25.4 * dpi);
    int h = (int)(params.length_mm / 25.4 * dpi);
    if (w <= 0) w = 600;
    if (h <= 0) h = 800;

    out_img.width = w;
    out_img.height = h;
    out_img.dpi = dpi;
    out_img.channels = (params.mode == ScanMode::Color) ? 3 : 1;
    out_img.bits_per_channel = (params.mode == ScanMode::LineArt) ? 1 : 8;
    out_img.data.resize(w * h * out_img.channels, 255);

    // Draw header box and gradients
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            size_t idx = (y * w + x) * out_img.channels;
            if (y < 80) {
                // Header bar
                if (out_img.channels == 3) {
                    out_img.data[idx + 0] = 30;
                    out_img.data[idx + 1] = 60;
                    out_img.data[idx + 2] = 120;
                } else {
                    out_img.data[idx] = 70;
                }
            } else if (y >= 100 && y < 180) {
                // Gradient ramp
                uint8_t g = (uint8_t)((x * 255) / w);
                if (out_img.channels == 3) {
                    out_img.data[idx + 0] = g;
                    out_img.data[idx + 1] = g;
                    out_img.data[idx + 2] = g;
                } else {
                    out_img.data[idx] = g;
                }
            } else if (x == 20 || x == w - 21 || y == 90 || y == h - 21) {
                // Border
                if (out_img.channels == 3) {
                    out_img.data[idx + 0] = 0;
                    out_img.data[idx + 1] = 0;
                    out_img.data[idx + 2] = 0;
                } else {
                    out_img.data[idx] = 0;
                }
            }
        }
    }

    if (params.mode == ScanMode::LineArt) {
        for (size_t i = 0; i < out_img.data.size(); i++) {
            out_img.data[i] = (out_img.data[i] >= 128) ? 1 : 0;
        }
    }
}

int main(int argc, char *argv[]) {
    std::string output_file = "scan.pdf";
    ScanParameters params;
    bool detect_only = false;
    bool json_progress = false;
    bool test_pattern = false;

    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "-h" || arg == "--help") {
            show_help(argv[0]);
            return 0;
        } else if ((arg == "-o" || arg == "--output") && i + 1 < argc) {
            output_file = argv[++i];
        } else if ((arg == "-m" || arg == "--mode") && i + 1 < argc) {
            std::string m = argv[++i];
            if (m == "gray" || m == "grayscale") params.mode = ScanMode::Grayscale;
            else if (m == "lineart" || m == "bw") params.mode = ScanMode::LineArt;
            else params.mode = ScanMode::Color;
        } else if ((arg == "-d" || arg == "--dpi") && i + 1 < argc) {
            int d = std::atoi(argv[++i]);
            if (d == 75 || d == 100 || d == 150 || d == 200 || d == 300 || d == 600 || d == 1200) {
                params.dpi = d;
            } else {
                std::cerr << "[-] Warning: Unsupported DPI " << d
                          << ". Allowed: 75, 100, 150, 200, 300, 600, 1200. Defaulting to 300 DPI." << std::endl;
                params.dpi = 300;
            }
        } else if ((arg == "-s" || arg == "--size") && i + 1 < argc) {
            std::string s = argv[++i];
            if (s == "letter") {
                params.width_mm = 215.9;
                params.length_mm = 279.4;
            } else if (s == "legal") {
                params.width_mm = 215.9;
                params.length_mm = 355.6;
            } else {
                params.width_mm = 210.0;
                params.length_mm = 297.0;
            }
        } else if (arg == "--preview") {
            params.dpi = 75;
            params.mode = ScanMode::Color;
        } else if (arg == "--detect") {
            detect_only = true;
        } else if (arg == "--json-progress") {
            json_progress = true;
        } else if (arg == "--test-pattern") {
            test_pattern = true;
        }
    }

    if (detect_only) {
        std::cout << "=== Scanning for Samsung Devices ===" << std::endl;
        auto devices = USBTransport::enumerate_samsung_devices();
        if (devices.empty()) {
            std::cout << "No Samsung USB scanners detected." << std::endl;
            std::cout << "Tip: Ensure the scanner is plugged in and turned on via USB." << std::endl;
        } else {
            for (size_t i = 0; i < devices.size(); i++) {
                char vid_buf[8], pid_buf[8];
                std::snprintf(vid_buf, sizeof(vid_buf), "%04x", devices[i].vid);
                std::snprintf(pid_buf, sizeof(pid_buf), "%04x", devices[i].pid);
                std::cout << "[" << (i + 1) << "] " << devices[i].manufacturer << " "
                          << devices[i].product << " (VID: 0x" << vid_buf
                          << " PID: 0x" << pid_buf
                          << ", Bus: " << (int)devices[i].bus << ", Addr: " << (int)devices[i].address << ")\n";
            }
        }
        return 0;
    }

    ScannedImage img;

    if (test_pattern) {
        std::cout << "[*] Running in test pattern mode (generating synthetic scan)..." << std::endl;
        for (int p = 10; p <= 100; p += 20) {
            if (json_progress) {
                std::cout << "{\"event\": \"progress\", \"percent\": " << p << "}" << std::endl;
            } else {
                std::cout << "Progress: " << p << "%" << std::endl;
            }
            usleep(50000);
        }
        generate_test_pattern(params, img);
        if (!ImageWriter::save(img, output_file)) {
            return 1;
        }
        if (json_progress) {
            std::cout << "{\"event\": \"complete\", \"file\": \"" << output_file << "\", \"width\": "
                      << img.width << ", \"height\": " << img.height << "}" << std::endl;
        }
        return 0;
    }

    // Connect to device
    std::cout << "[*] Searching for connected Samsung USB scanner..." << std::endl;
    std::unique_ptr<ITransport> transport(new USBTransport(0x04e8, 0));

    if (!transport->open()) {
        std::cerr << "[-] Error: Samsung USB scanner could not be opened." << std::endl;
        std::cerr << "    Ensure the USB cable is firmly connected and the printer is powered on." << std::endl;
        std::cerr << "    You can run with '--test-pattern' to test software without hardware." << std::endl;
        return 1;
    }

    // Register signal handlers for clean hardware stop
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_signal;
    sigaction(SIGINT, &sa, nullptr);
    sigaction(SIGTERM, &sa, nullptr);

    auto engine = std::make_shared<ScannerEngine>(transport.get());
    engine->set_cancel_flag(&g_interrupted);

    // Background listener for CANCEL on stdin from GUI.
    // Captures a weak_ptr so if the scan completes and engine is destroyed,
    // subsequent input on stdin will safely no-op without use-after-free.
    std::weak_ptr<ScannerEngine> weak_engine = engine;
    auto stdin_stop = std::make_shared<std::atomic<bool>>(false);

    std::thread stdin_thread([weak_engine, stdin_stop]() {
        std::string line;
        while (!stdin_stop->load() && std::getline(std::cin, line)) {
            if (line == "CANCEL" || line == "cancel" || line == "STOP" || line == "abort") {
                if (auto eng = weak_engine.lock()) {
                    eng->cancel();
                }
                break;
            }
        }
    });
    stdin_thread.detach();

    auto progress_cb = [json_progress](int percent, int lines, int total) {
        if (json_progress) {
            std::cout << "{\"event\": \"progress\", \"percent\": " << percent
                      << ", \"lines\": " << lines << ", \"total\": " << total << "}" << std::endl;
        } else {
            std::cout << "\rProgress: " << percent << "% (" << lines << "/" << total << " lines)" << std::flush;
        }
    };

    std::cout << "[*] Initializing scan (Mode: " << (params.mode == ScanMode::Color ? "Color" : "Grayscale")
              << ", DPI: " << params.dpi << ", Size: " << params.width_mm << "x" << params.length_mm << " mm)..." << std::endl;

    bool success = engine->scan(params, img, progress_cb);

    stdin_stop->store(true);
    engine.reset();

    if (!success) {
        if (json_progress) {
            std::cout << "{\"event\": \"cancelled\"}" << std::endl;
        } else {
            std::cerr << "\n[-] Scan aborted by user." << std::endl;
        }
        return 2;
    }
    std::cout << std::endl;

    if (!ImageWriter::save(img, output_file)) {
        return 1;
    }

    if (json_progress) {
        std::cout << "{\"event\": \"complete\", \"file\": \"" << output_file << "\", \"width\": "
                  << img.width << ", \"height\": " << img.height << "}" << std::endl;
    }

    return 0;
}
