/*
 * 	    page.cpp                  (C) 2006-2008, Aurélien Croc (AP²C)
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; version 2 of the License.
 * 
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the
 *  Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 *  $Id$
 * 
 */
#include "page.h"
#include <unistd.h>
#include <string.h>
#include "band.h"
#include "errlog.h"

/*
 * This magic formula reverse the bit of a byte. ie. the bit 1 becomes the 
 * bit 8, the bit 2 becomes the bit 7 etc.
 */
#define REVERSE_BITS(N) ((N * 0x0202020202ULL & 0x010884422010ULL) % 1023)

/*
 * Constructeur - Destructeur
 * Init - Uninit 
 */
Page::Page()
{
    _empty = true;
    _xResolution = 0;
    _yResolution = 0;
    _planes[0] = NULL;
    _planes[1] = NULL;
    _planes[2] = NULL;
    _planes[3] = NULL;
    _firstBand = NULL;
    _lastBand = NULL;
    _bandsNr = 0;
    _bih = NULL;
}

Page::~Page()
{
    flushPlanes();
    if (_firstBand)
        delete _firstBand;
    if (_bih)
        delete[] _bih;
}



/*
 * Enregistrement d'une nouvelle bande
 * Register a new band
 */
void Page::registerBand(Band *band)
{
    if (_lastBand)
        _lastBand->registerSibling(band);
    else
        _firstBand = band;
    _lastBand = band;
    band->registerParent(this);
    _bandsNr++;
}



/*
 * Rotation des couches
 * Rotate bitmaps planes
 */
void Page::rotate()
{
    unsigned long size, midSize;
    unsigned char tmp;

    size  = _width * _height / 8;
    midSize = size / 2;

    for (unsigned int i=0; i < _colors; i++) {
        for (unsigned long j=0; j < midSize; j++) {
            tmp = _planes[i][j];
            _planes[i][j] = REVERSE_BITS(_planes[i][size - j - 1]);
            _planes[i][size - j - 1] = REVERSE_BITS(tmp);
        }
    }
}



/*
 * Libération de la mémoire utilisée par les couches
 * Flush the planes
 */
void Page::flushPlanes()
{
    for (unsigned int i=0; i < 4; i++) {
        if (_planes[i]) {
            delete[] _planes[i];
            _planes[i] = NULL;
        }
    }
    _empty = false;
}



/*
 * Mise sur disque / Rechargement
 * Swapping / restoring
 */
static bool safe_write(int fd, const void *buf, size_t count) {
    const char *p = (const char *)buf;
    while (count > 0) {
        ssize_t ret = write(fd, p, count);
        if (ret <= 0) return false;
        p += ret;
        count -= (size_t)ret;
    }
    return true;
}

static bool safe_read(int fd, void *buf, size_t count) {
    char *p = (char *)buf;
    while (count > 0) {
        ssize_t ret = read(fd, p, count);
        if (ret <= 0) return false;
        p += ret;
        count -= (size_t)ret;
    }
    return true;
}

bool Page::swapToDisk(int fd)
{
    unsigned long i;
    Band* band;

    if (_planes[0] || _planes[1] || _planes[2] || _planes[3]) {
        ERRORMSG(_("Cannot swap page instance which still contains bitmap "
            "representation"));
        return false;
    }
    if (!safe_write(fd, &_xResolution, sizeof(_xResolution)) ||
        !safe_write(fd, &_yResolution, sizeof(_yResolution)) ||
        !safe_write(fd, &_width, sizeof(_width)) ||
        !safe_write(fd, &_height, sizeof(_height)) ||
        !safe_write(fd, &_colors, sizeof(_colors)) ||
        !safe_write(fd, &_pageNr, sizeof(_pageNr)) ||
        !safe_write(fd, &_copiesNr, sizeof(_copiesNr)) ||
        !safe_write(fd, &_compression, sizeof(_compression)) ||
        !safe_write(fd, &_empty, sizeof(_empty)) ||
        !safe_write(fd, &_bandsNr, sizeof(_bandsNr)))
        return false;
    /* Carefully check if there is BIH data and compression type is 0x15,
       before saving BIH data to file. */
    if (( 0x15 == _compression ) && ( _bandsNr > 0 ) && ( NULL != _bih )) {
        if (!safe_write(fd, _bih, 20))
            return false;
    }
    for (i=0, band = _firstBand; i < _bandsNr; i++) {
        if (!band || !band->swapToDisk(fd))
            return false;
        band = band->sibling();
    }

    return true;
}

Page* Page::restoreIntoMemory(int fd)
{
    unsigned long nr;
    Page* page;

    page = new Page();
    if (!safe_read(fd, &page->_xResolution, sizeof(page->_xResolution)) ||
        !safe_read(fd, &page->_yResolution, sizeof(page->_yResolution)) ||
        !safe_read(fd, &page->_width, sizeof(page->_width)) ||
        !safe_read(fd, &page->_height, sizeof(page->_height)) ||
        !safe_read(fd, &page->_colors, sizeof(page->_colors)) ||
        !safe_read(fd, &page->_pageNr, sizeof(page->_pageNr)) ||
        !safe_read(fd, &page->_copiesNr, sizeof(page->_copiesNr)) ||
        !safe_read(fd, &page->_compression, sizeof(page->_compression)) ||
        !safe_read(fd, &page->_empty, sizeof(page->_empty)) ||
        !safe_read(fd, &nr, sizeof(nr))) {
        delete page;
        return NULL;
    }
    /* Check if compression type is 0x15 and that there is at least one
       image band before reading BIH data. */
    if (( 0x15 == page->_compression ) && ( nr > 0 )) {
        unsigned char bih[20];
        if (!safe_read(fd, bih, 20)) {
            delete page;
            return NULL;
        }
        page->setBIH(bih);
    }
    for (unsigned int i=0; i < nr; i++) {
        Band *band = Band::restoreIntoMemory(fd);
        if (!band) {
            delete page;
            return NULL;
        }
        page->registerBand(band);
    }

    return page;
}

void Page::setBIH(const unsigned char *bih_data) {
    if (NULL == _bih)
        _bih = new unsigned char[20];
    memcpy(_bih, bih_data, 20);
}

/* vim: set expandtab tabstop=4 shiftwidth=4 smarttab tw=80 cin enc=utf8: */

