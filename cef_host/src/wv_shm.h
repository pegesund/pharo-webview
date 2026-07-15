// Writer side of the shared-memory frame bridge (host process).
#ifndef WV_SHM_H
#define WV_SHM_H

#include <string>
#include <cstdint>
#include "wv_shared.h"

class WvShm {
public:
    WvShm() = default;
    ~WvShm();

    // Create/truncate the backing file and mmap it for max_w x max_h.
    bool open(const std::string& path, uint32_t max_w, uint32_t max_h);
    void close();

    // Write one frame (BGRA, pitch = width*4) under the seqlock. dirty may be
    // null/0 for a full-frame update. Clamps to capacity.
    void writeFrame(const void* bgra, uint32_t width, uint32_t height,
                    const int32_t* dirty_xywh, uint32_t num_dirty);

    void setAlive(uint32_t v);
    bool valid() const { return header_ != nullptr; }

private:
    int fd_ = -1;
    void* base_ = nullptr;
    size_t size_ = 0;
    wv_shm_header* header_ = nullptr;
    uint8_t* pixels_ = nullptr;
    uint32_t max_w_ = 0, max_h_ = 0;
};

#endif /* WV_SHM_H */
