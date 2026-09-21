/*
 * 	    bandplane.cpp             (C) 2006-2008, Aurélien Croc (AP²C)
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
#include "bandplane.h"
#include <unistd.h>

/*
 * Constructeur - Destructeur
 * Init - Uninit 
 */
BandPlane::BandPlane()
{
    _endian = Dependant;
    _size = 0;
    _data = NULL;
}

BandPlane::~BandPlane()
{
    if (_data)
        delete[] _data;
}


/*
 * Enregistrement des données
 * Set data
 */
void BandPlane::setData(unsigned char *data, unsigned long size)
{
    if (!data)
        size = 0;
    if (_data)
        delete[] _data;

    _data = data;
    _size = size;
    _checksum = 0;
    for (unsigned int i=0; i < _size; i++)
        _checksum += (unsigned char)_data[i];
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

bool BandPlane::swapToDisk(int fd)
{
    if (!safe_write(fd, &_colorNr, sizeof(_colorNr))) return false;
    if (!safe_write(fd, &_size, sizeof(_size))) return false;
    if (_size > 0 && !safe_write(fd, _data, _size)) return false;
    if (!safe_write(fd, &_checksum, sizeof(_checksum))) return false;
    if (!safe_write(fd, &_endian, sizeof(_endian))) return false;
    if (!safe_write(fd, &_compression, sizeof(_compression))) return false;
    return true;
}

BandPlane* BandPlane::restoreIntoMemory(int fd)
{
    unsigned char* data;
    BandPlane* plane;

    plane = new BandPlane();
    if (!safe_read(fd, &plane->_colorNr, sizeof(plane->_colorNr)) ||
        !safe_read(fd, &plane->_size, sizeof(plane->_size))) {
        delete plane;
        return NULL;
    }
    data = new unsigned char[plane->_size];
    if (plane->_size > 0 && !safe_read(fd, data, plane->_size)) {
        delete[] data;
        delete plane;
        return NULL;
    }
    plane->_data = data;
    if (!safe_read(fd, &plane->_checksum, sizeof(plane->_checksum)) ||
        !safe_read(fd, &plane->_endian, sizeof(plane->_endian)) ||
        !safe_read(fd, &plane->_compression, sizeof(plane->_compression))) {
        delete plane;
        return NULL;
    }

    return plane;
}

/* vim: set expandtab tabstop=4 shiftwidth=4 smarttab tw=80 cin enc=utf8: */

