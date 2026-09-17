#ifndef IMAGE_WRITER_H
#define IMAGE_WRITER_H

#include "scanner_engine.h"
#include <string>

class ImageWriter {
public:
    static bool save(const ScannedImage &img, const std::string &filepath);
    static bool save_pnm(const ScannedImage &img, const std::string &pnm_path);
};

#endif // IMAGE_WRITER_H
