#include "wv_shm.h"

#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <cstring>
#include <cstdio>

WvShm::~WvShm() { close(); }

bool WvShm::open(const std::string& path, uint32_t max_w, uint32_t max_h) {
    close();
    max_w_ = max_w;
    max_h_ = max_h;
    size_ = wv_shm_size(max_w, max_h);

    fd_ = ::open(path.c_str(), O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd_ < 0) {
        std::perror("[wv_shm] open");
        return false;
    }
    if (ftruncate(fd_, (off_t)size_) != 0) {
        std::perror("[wv_shm] ftruncate");
        ::close(fd_);
        fd_ = -1;
        return false;
    }
    base_ = mmap(nullptr, size_, PROT_READ | PROT_WRITE, MAP_SHARED, fd_, 0);
    if (base_ == MAP_FAILED) {
        std::perror("[wv_shm] mmap");
        base_ = nullptr;
        ::close(fd_);
        fd_ = -1;
        return false;
    }
    header_ = reinterpret_cast<wv_shm_header*>(base_);
    pixels_ = reinterpret_cast<uint8_t*>(base_) + sizeof(wv_shm_header);

    std::memset(base_, 0, size_);
    header_->magic = WV_SHM_MAGIC;
    header_->version = WV_SHM_VERSION;
    header_->pixels_offset = (uint32_t)sizeof(wv_shm_header);
    header_->pixels_capacity = max_w * max_h * 4u;
    header_->seq = 0;
    header_->alive = 1;
    return true;
}

void WvShm::close() {
    if (header_) header_->alive = 0;
    if (base_ && base_ != MAP_FAILED) munmap(base_, size_);
    if (fd_ >= 0) ::close(fd_);
    base_ = nullptr;
    header_ = nullptr;
    pixels_ = nullptr;
    fd_ = -1;
}

void WvShm::setAlive(uint32_t v) {
    if (header_) header_->alive = v;
}

void WvShm::writeFrame(const void* bgra, uint32_t width, uint32_t height,
                       const int32_t* dirty_xywh, uint32_t num_dirty) {
    if (!header_) return;
    uint32_t bytes = width * height * 4u;
    if (bytes > header_->pixels_capacity) return;  // frame bigger than mapping

    // seqlock: odd during write
    header_->seq = header_->seq | 1u;   // make odd
    __sync_synchronize();

    header_->width = width;
    header_->height = height;
    uint32_t n = num_dirty > WV_MAX_DIRTY ? WV_MAX_DIRTY : num_dirty;
    header_->num_dirty = n;
    if (dirty_xywh && n) {
        std::memcpy(header_->dirty, dirty_xywh, n * 4 * sizeof(int32_t));
    }
    std::memcpy(pixels_, bgra, bytes);

    __sync_synchronize();
    header_->seq += 1;   // back to even, new frame published
}
