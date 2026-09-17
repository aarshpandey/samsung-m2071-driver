#include "image_writer.h"
#include <fstream>
#include <iostream>
#include <sstream>
#include <cstdlib>
#include <unistd.h>
#include <algorithm>

static std::string get_extension(const std::string &path) {
    size_t idx = path.rfind('.');
    if (idx != std::string::npos) {
        std::string ext = path.substr(idx + 1);
        std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
        return ext;
    }
    return "";
}

bool ImageWriter::save_pnm(const ScannedImage &img, const std::string &pnm_path) {
    if (img.width <= 0 || img.height <= 0 || img.data.empty()) {
        std::cerr << "[-] Error: Empty image buffer, cannot save" << std::endl;
        return false;
    }

    std::ofstream out(pnm_path, std::ios::binary);
    if (!out.is_open()) {
        std::cerr << "[-] Error: Unable to open file for writing: " << pnm_path << std::endl;
        return false;
    }

    if (img.channels == 3) {
        // Color PPM (P6)
        out << "P6\n" << img.width << " " << img.height << "\n255\n";
    } else {
        // Grayscale PGM (P5)
        out << "P5\n" << img.width << " " << img.height << "\n255\n";
    }

    out.write((const char*)img.data.data(), img.data.size());
    out.close();

    return true;
}

bool ImageWriter::save(const ScannedImage &img, const std::string &filepath) {
    std::string ext = get_extension(filepath);

    if (ext == "pnm" || ext == "ppm" || ext == "pgm") {
        return save_pnm(img, filepath);
    }

    // For other formats (png, jpg, jpeg, pdf, tiff), use native macOS sips tool
    char tmp_template[] = "/tmp/samsung_scan_XXXXXX.pnm";
    int fd = mkstemp(tmp_template);
    if (fd < 0) {
        std::cerr << "[-] Error: Failed to create temporary PNM file" << std::endl;
        return false;
    }
    close(fd);
    std::string tmp_pnm = tmp_template;

    if (!save_pnm(img, tmp_pnm)) {
        unlink(tmp_template);
        return false;
    }

    std::string sips_fmt = "png";
    if (ext == "jpg" || ext == "jpeg") {
        sips_fmt = "jpeg";
    } else if (ext == "pdf") {
        sips_fmt = "pdf";
    } else if (ext == "tif" || ext == "tiff") {
        sips_fmt = "tiff";
    }

    std::ostringstream cmd;
    cmd << "/usr/bin/sips -s format " << sips_fmt;
    if (img.dpi > 0) {
        cmd << " -s dpiWidth " << img.dpi << " -s dpiHeight " << img.dpi;
    }
    cmd << " \"" << tmp_pnm << "\" --out \"" << filepath << "\" >/dev/null 2>&1";
    int ret = system(cmd.str().c_str());
    unlink(tmp_template);

    if (ret != 0) {
        std::cerr << "[-] Error: /usr/bin/sips failed to convert image to " << ext << std::endl;
        return false;
    }

    std::cout << "[+] Saved scanned document: " << filepath << " (" << img.width << "x" << img.height << " px)" << std::endl;
    return true;
}
