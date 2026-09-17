#ifndef TRANSPORT_H
#define TRANSPORT_H

#include <stddef.h>
#include <stdint.h>
#include <string>

class ITransport {
public:
    virtual ~ITransport() {}
    virtual bool open() = 0;
    virtual void close() = 0;
    virtual bool is_open() const = 0;
    virtual bool send_cmd(const uint8_t *cmd, size_t cmdlen) = 0;
    virtual bool recv_resp(uint8_t *resp, size_t resplen, size_t *actual_len = nullptr) = 0;
    virtual bool read_bulk(uint8_t *buffer, size_t bytes_to_read, size_t *bytes_read) = 0;
    virtual void drain() {}
    virtual void clear_halt() {}
    virtual std::string get_device_info() const = 0;
};

#endif // TRANSPORT_H
