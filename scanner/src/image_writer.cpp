#include "image_writer.h"
#include <fstream>
#include <iostream>
#include <sstream>
#include <cstdlib>
#include <unistd.h>
#include <algorithm>
#include <vector>
#include <string>
#include <spawn.h>
#include <sys/wait.h>

extern char **environ;

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
        out << "P6\n" << img.width << " " << img.height << "\n255\n";
        out.write((const char*)img.data.data(), img.data.size());
    } else {
        out << "P5\n" << img.width << " " << img.height << "\n255\n";
        if (img.bits_per_channel == 1) {
            // LineArt (1-bit): map 0 -> 0, 1 -> 255 so pixels are not nearly solid black
            std::vector<uint8_t> expanded(img.data.size());
            for (size_t i = 0; i < img.data.size(); ++i) {
                expanded[i] = img.data[i] ? 255 : 0;
            }
            out.write((const char*)expanded.data(), expanded.size());
        } else {
            out.write((const char*)img.data.data(), img.data.size());
        }
    }
    out.close();

    return true;
}

bool ImageWriter::save(const ScannedImage &img, const std::string &filepath) {
    std::string ext = get_extension(filepath);

    if (ext == "pnm" || ext == "ppm" || ext == "pgm") {
        return save_pnm(img, filepath);
    }

    // Use mkstemps (not the racy mktemp) to atomically create a unique temp file.
    // suffix length for ".pnm" is 4.
    char tmp_template[] = "/tmp/samsung_scan_XXXXXX.pnm";
    int fd = mkstemps(tmp_template, 4);
    if (fd < 0) {
        std::cerr << "[-] Error: Failed to create temporary PNM file" << std::endl;
        return false;
    }
    close(fd);
    std::string tmp_pnm = tmp_template;

    if (!save_pnm(img, tmp_pnm)) {
        unlink(tmp_pnm.c_str());
        return false;
    }

    // Determine sips output format
    const char *sips_fmt = "png";
    if (ext == "jpg" || ext == "jpeg") {
        sips_fmt = "jpeg";
    } else if (ext == "pdf") {
        sips_fmt = "pdf";
    } else if (ext == "tif" || ext == "tiff") {
        sips_fmt = "tiff";
    }

    // Build argument list — posix_spawn bypasses the shell entirely,
    // eliminating the command-injection risk from filepath (VULN-1 fix).
    std::string dpi_str = std::to_string(img.dpi);
    std::vector<std::string> args_strs = { "/usr/bin/sips", "-s", "format", sips_fmt };
    if (img.dpi > 0) {
        args_strs.insert(args_strs.end(), { "-s", "dpiWidth", dpi_str, "-s", "dpiHeight", dpi_str });
    }
    args_strs.push_back(tmp_pnm);
    args_strs.insert(args_strs.end(), { "--out", filepath });

    std::vector<char*> argv_ptrs;
    for (auto &s : args_strs) argv_ptrs.push_back(const_cast<char*>(s.c_str()));
    argv_ptrs.push_back(nullptr);

    pid_t pid;
    int spawn_ret = posix_spawn(&pid, "/usr/bin/sips", nullptr, nullptr,
                                argv_ptrs.data(), environ);

    if (spawn_ret != 0) {
        unlink(tmp_pnm.c_str());
        std::cerr << "[-] Error: Failed to launch /usr/bin/sips (errno=" << spawn_ret << ")" << std::endl;
        return false;
    }

    int status = 0;
    waitpid(pid, &status, 0);
    unlink(tmp_pnm.c_str());

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        std::cerr << "[-] Error: /usr/bin/sips failed to convert image to " << ext << std::endl;
        return false;
    }

    std::cout << "[+] Saved scanned document: " << filepath
              << " (" << img.width << "x" << img.height << " px)" << std::endl;
    return true;
}
