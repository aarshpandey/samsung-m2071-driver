#include "transport_usb.h"
#include <iostream>
#include <iomanip>
#include <sstream>
#include <cstring>
#include <unistd.h>

static const int USB_TIMEOUT_CMD_MS = 10000;
static const int USB_TIMEOUT_DATA_MS = 500;

// Known Samsung MFP PIDs
static const uint16_t KNOWN_SAMSUNG_PIDS[] = {
    0x3469, // Samsung M2070 / M2071 Series
    0x3468, // Samsung C460 Series
    0x346b, // Samsung C1860FW
    0x3460, // Samsung M337x / 387x / 407x Series
    0x3461, // Samsung M267x / 287x Series
    0x344f, // Samsung SCX-3400 Series
    0x3441, // Samsung SCX-3200 Series
    0x3433, // Samsung SCX-4600 Series
    0x3434, // Samsung SCX-4623 Series
    0x342a, // Samsung CLX-3170 / 3175 Series
    0x341b, // Samsung SCX-4200 Series
    0x3413  // Samsung SCX-4100 Series
};

static bool is_known_samsung_pid(uint16_t pid) {
    for (size_t i = 0; i < sizeof(KNOWN_SAMSUNG_PIDS) / sizeof(KNOWN_SAMSUNG_PIDS[0]); i++) {
        if (KNOWN_SAMSUNG_PIDS[i] == pid) return true;
    }
    return false;
}

USBTransport::USBTransport(uint16_t vid, uint16_t pid)
    : _target_vid(vid), _target_pid(pid), _ctx(nullptr), _handle(nullptr),
      _interface_nr(-1), _ep_in(0), _ep_out(0), _claimed(false)
{
}

USBTransport::~USBTransport() {
    close();
}

std::vector<USBDeviceInfo> USBTransport::enumerate_samsung_devices() {
    std::vector<USBDeviceInfo> results;
    libusb_context *ctx = nullptr;
    if (libusb_init(&ctx) != 0) return results;

    libusb_device **devs = nullptr;
    ssize_t cnt = libusb_get_device_list(ctx, &devs);
    if (cnt > 0) {
        for (ssize_t i = 0; i < cnt; i++) {
            libusb_device *dev = devs[i];
            struct libusb_device_descriptor desc;
            if (libusb_get_device_descriptor(dev, &desc) == 0) {
                if (desc.idVendor == 0x04e8) {
                    USBDeviceInfo info;
                    info.vid = desc.idVendor;
                    info.pid = desc.idProduct;
                    info.bus = libusb_get_bus_number(dev);
                    info.address = libusb_get_device_address(dev);

                    libusb_device_handle *h = nullptr;
                    if (libusb_open(dev, &h) == 0) {
                        unsigned char buf[256];
                        if (desc.iManufacturer && libusb_get_string_descriptor_ascii(h, desc.iManufacturer, buf, sizeof(buf)) > 0) {
                            info.manufacturer = (char*)buf;
                        }
                        if (desc.iProduct && libusb_get_string_descriptor_ascii(h, desc.iProduct, buf, sizeof(buf)) > 0) {
                            info.product = (char*)buf;
                        }
                        if (desc.iSerialNumber && libusb_get_string_descriptor_ascii(h, desc.iSerialNumber, buf, sizeof(buf)) > 0) {
                            info.serial = (char*)buf;
                        }
                        libusb_close(h);
                    }
                    results.push_back(info);
                }
            }
        }
        libusb_free_device_list(devs, 1);
    }
    libusb_exit(ctx);
    return results;
}

bool USBTransport::open() {
    if (is_open()) return true;

    if (libusb_init(&_ctx) != 0) {
        std::cerr << "[-] Error: Failed to initialize libusb" << std::endl;
        return false;
    }

    libusb_device **devs = nullptr;
    ssize_t cnt = libusb_get_device_list(_ctx, &devs);
    if (cnt < 0) {
        std::cerr << "[-] Error: Unable to list USB devices" << std::endl;
        libusb_exit(_ctx);
        _ctx = nullptr;
        return false;
    }

    libusb_device *chosen_dev = nullptr;
    for (ssize_t i = 0; i < cnt; i++) {
        libusb_device *dev = devs[i];
        struct libusb_device_descriptor desc;
        if (libusb_get_device_descriptor(dev, &desc) == 0) {
            if (desc.idVendor == _target_vid) {
                if (_target_pid != 0) {
                    if (desc.idProduct == _target_pid) {
                        chosen_dev = dev;
                        break;
                    }
                } else {
                    // Match known Samsung MFP PID or specific 0x3469
                    if (is_known_samsung_pid(desc.idProduct) || (desc.idProduct >= 0x3400 && desc.idProduct <= 0x3490)) {
                        chosen_dev = dev;
                        break;
                    }
                }
            }
        }
    }

    if (!chosen_dev) {
        libusb_free_device_list(devs, 1);
        libusb_exit(_ctx);
        _ctx = nullptr;
        return false;
    }

    int rc = libusb_open(chosen_dev, &_handle);
    if (rc != 0 || !_handle) {
        std::cerr << "[-] Error: Failed to open USB device (" << libusb_error_name(rc) << ")" << std::endl;
        libusb_free_device_list(devs, 1);
        libusb_exit(_ctx);
        _ctx = nullptr;
        return false;
    }

    // Inspect device descriptor & find scanner interface with bulk endpoints
    struct libusb_config_descriptor *config = nullptr;
    rc = libusb_get_active_config_descriptor(chosen_dev, &config);
    if (rc != 0 || !config) {
        rc = libusb_get_config_descriptor(chosen_dev, 0, &config);
    }

    if (config) {
        bool found_scanner = false;
        for (int i = 0; i < config->bNumInterfaces && !found_scanner; i++) {
            const struct libusb_interface *inter = &config->interface[i];
            for (int a = 0; a < inter->num_altsetting && !found_scanner; a++) {
                const struct libusb_interface_descriptor *alt = &inter->altsetting[a];
                // Class 7 is USB PRINTER - do not select printer endpoints for scanning!
                if (alt->bInterfaceClass == 7) {
                    continue;
                }

                uint8_t ep_in = 0;
                uint8_t ep_out = 0;

                for (int e = 0; e < alt->bNumEndpoints; e++) {
                    const struct libusb_endpoint_descriptor *ep = &alt->endpoint[e];
                    if ((ep->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) == LIBUSB_TRANSFER_TYPE_BULK) {
                        if (ep->bEndpointAddress & LIBUSB_ENDPOINT_DIR_MASK) {
                            ep_in = ep->bEndpointAddress;
                        } else {
                            ep_out = ep->bEndpointAddress;
                        }
                    }
                }

                if (ep_in && ep_out) {
                    _interface_nr = alt->bInterfaceNumber;
                    _ep_in = ep_in;
                    _ep_out = ep_out;
                    found_scanner = true;
                    break;
                }
            }
        }
        libusb_free_config_descriptor(config);
    }

    libusb_free_device_list(devs, 1);

    if (_interface_nr < 0 || !_ep_in || !_ep_out) {
        std::cerr << "[-] Error: Could not locate bulk scanner endpoints on Samsung device" << std::endl;
        libusb_close(_handle);
        _handle = nullptr;
        libusb_exit(_ctx);
        _ctx = nullptr;
        return false;
    }

    // Detach kernel driver if active
    if (libusb_kernel_driver_active(_handle, _interface_nr) == 1) {
        libusb_detach_kernel_driver(_handle, _interface_nr);
    }

    rc = libusb_claim_interface(_handle, _interface_nr);
    if (rc != 0) {
        std::cerr << "[-] Error: Failed to claim interface " << _interface_nr
                  << " (" << libusb_error_name(rc) << ")" << std::endl;
        libusb_close(_handle);
        _handle = nullptr;
        libusb_exit(_ctx);
        _ctx = nullptr;
        return false;
    }
    _claimed = true;
    clear_halt();
    drain();

    std::ostringstream ss;
    ss << "USB Samsung Scanner (Interface " << _interface_nr
       << ", EP IN: 0x" << std::hex << (int)_ep_in
       << ", EP OUT: 0x" << std::hex << (int)_ep_out << ")";
    _dev_info = ss.str();

    return true;
}

void USBTransport::close() {
    if (_handle) {
        if (_claimed) {
            drain();
            libusb_release_interface(_handle, _interface_nr);
            _claimed = false;
        }
        libusb_close(_handle);
        _handle = nullptr;
    }
    if (_ctx) {
        libusb_exit(_ctx);
        _ctx = nullptr;
    }
    _interface_nr = -1;
    _ep_in = 0;
    _ep_out = 0;
}

void USBTransport::drain() {
    if (!is_open() || !_ep_in) return;
    uint8_t buf[2048];
    int transferred = 0;
    // Fast non-blocking drain with 40ms timeout
    while (libusb_bulk_transfer(_handle, _ep_in, buf, sizeof(buf), &transferred, 40) == 0 && transferred > 0) {}
    clear_halt();
}

void USBTransport::clear_halt() {
    if (!is_open()) return;
    if (_ep_in) libusb_clear_halt(_handle, _ep_in);
    if (_ep_out) libusb_clear_halt(_handle, _ep_out);
}

bool USBTransport::is_open() const {
    return _handle != nullptr && _claimed;
}

bool USBTransport::send_cmd(const uint8_t *cmd, size_t cmdlen) {
    if (!is_open() || !cmd || cmdlen == 0) return false;

    int transferred = 0;
    int rc = libusb_bulk_transfer(_handle, _ep_out, (unsigned char*)cmd, (int)cmdlen, &transferred, USB_TIMEOUT_CMD_MS);
    if (rc != 0 || transferred != (int)cmdlen) {
        std::cerr << "[-] Error sending command: " << libusb_error_name(rc)
                  << " (wrote " << transferred << "/" << cmdlen << " bytes)" << std::endl;
        return false;
    }
    return true;
}

bool USBTransport::recv_resp(uint8_t *resp, size_t resplen, size_t *actual_len) {
    if (!is_open() || !resp || resplen == 0) return false;

    int transferred = 0;
    int rc = libusb_bulk_transfer(_handle, _ep_in, (unsigned char*)resp, (int)resplen, &transferred, USB_TIMEOUT_CMD_MS);
    if (actual_len) *actual_len = transferred;

    if (rc != 0) {
        std::cerr << "[-] Error receiving response: " << libusb_error_name(rc) << std::endl;
        return false;
    }
    return true;
}

bool USBTransport::read_bulk(uint8_t *buffer, size_t bytes_to_read, size_t *bytes_read) {
    if (!is_open() || !buffer || bytes_to_read == 0) return false;

    int transferred = 0;
    int rc = libusb_bulk_transfer(_handle, _ep_in, (unsigned char*)buffer, (int)bytes_to_read, &transferred, USB_TIMEOUT_DATA_MS);
    if (bytes_read) *bytes_read = transferred;

    if (rc == LIBUSB_ERROR_TIMEOUT) {
        return (transferred > 0);
    }
    if (rc != 0) {
        std::cerr << "[-] Error reading bulk image data: " << libusb_error_name(rc) << std::endl;
        return false;
    }
    return true;
}

std::string USBTransport::get_device_info() const {
    return _dev_info.empty() ? "Samsung USB Scanner (Not Connected)" : _dev_info;
}
