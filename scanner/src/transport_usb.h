#ifndef TRANSPORT_USB_H
#define TRANSPORT_USB_H

#include "transport.h"
#if defined(__has_include)
  #if __has_include(<libusb-1.0/libusb.h>)
    #include <libusb-1.0/libusb.h>
  #elif __has_include(<libusb.h>)
    #include <libusb.h>
  #else
    #include <libusb.h>
  #endif
#else
  #include <libusb.h>
#endif
#include <vector>

struct USBDeviceInfo {
    uint16_t vid;
    uint16_t pid;
    std::string manufacturer;
    std::string product;
    std::string serial;
    uint8_t bus;
    uint8_t address;
};

class USBTransport : public ITransport {
public:
    USBTransport(uint16_t vid = 0x04e8, uint16_t pid = 0);
    virtual ~USBTransport();

    virtual bool open() override;
    virtual void close() override;
    virtual bool is_open() const override;
    virtual bool send_cmd(const uint8_t *cmd, size_t cmdlen) override;
    virtual bool recv_resp(uint8_t *resp, size_t resplen, size_t *actual_len = nullptr) override;
    virtual bool read_bulk(uint8_t *buffer, size_t bytes_to_read, size_t *bytes_read) override;
    virtual void drain() override;
    virtual void clear_halt() override;
    virtual std::string get_device_info() const override;

    static std::vector<USBDeviceInfo> enumerate_samsung_devices();

private:
    uint16_t _target_vid;
    uint16_t _target_pid;
    libusb_context *_ctx;
    libusb_device_handle *_handle;
    int _interface_nr;
    uint8_t _ep_in;
    uint8_t _ep_out;
    std::string _dev_info;
    bool _claimed;
};

#endif // TRANSPORT_USB_H
