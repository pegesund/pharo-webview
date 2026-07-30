#include "wv_shm.h"

#include <cstring>
#include <cstdio>

#ifdef _WIN32
  #ifndef WIN32_LEAN_AND_MEAN
  #define WIN32_LEAN_AND_MEAN
  #endif
  #include <windows.h>
  // MSVC has no __sync_synchronize; MemoryBarrier is the equivalent full fence.
  #define WV_FULL_FENCE() MemoryBarrier()
#else
  #include <fcntl.h>
  #include <unistd.h>
  #include <sys/mman.h>
  #define WV_FULL_FENCE() __sync_synchronize()
#endif

WvShm::~WvShm() { close(); }

#ifdef _WIN32

bool WvShm::open(const std::string& path, uint32_t max_w, uint32_t max_h) {
    close();
    max_w_ = max_w;
    max_h_ = max_h;
    size_ = wv_shm_size(max_w, max_h);

    // Share read+write+delete so the Pharo reader can map the same file and the
    // slot file can be replaced on restart.
    HANDLE file = CreateFileA(path.c_str(), GENERIC_READ | GENERIC_WRITE,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        std::fprintf(stderr, "[wv_shm] CreateFile failed (%lu) for %s\n",
                     GetLastError(), path.c_str());
        return false;
    }
    LARGE_INTEGER sz; sz.QuadPart = (LONGLONG)size_;
    if (!SetFilePointerEx(file, sz, nullptr, FILE_BEGIN) || !SetEndOfFile(file)) {
        std::fprintf(stderr, "[wv_shm] SetEndOfFile failed (%lu)\n", GetLastError());
        CloseHandle(file);
        return false;
    }
    HANDLE mapping = CreateFileMappingA(file, nullptr, PAGE_READWRITE,
                                        (DWORD)((uint64_t)size_ >> 32),
                                        (DWORD)(size_ & 0xFFFFFFFFu), nullptr);
    if (!mapping) {
        std::fprintf(stderr, "[wv_shm] CreateFileMapping failed (%lu)\n", GetLastError());
        CloseHandle(file);
        return false;
    }
    base_ = MapViewOfFile(mapping, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, size_);
    if (!base_) {
        std::fprintf(stderr, "[wv_shm] MapViewOfFile failed (%lu)\n", GetLastError());
        CloseHandle(mapping);
        CloseHandle(file);
        return false;
    }
    winFile_ = file;
    winMapping_ = mapping;

    header_ = reinterpret_cast<wv_shm_header*>(base_);
    pixels_ = reinterpret_cast<uint8_t*>(base_) + sizeof(wv_shm_header);

    std::memset(base_, 0, size_);
    header_->magic = WV_SHM_MAGIC;
    header_->version = WV_SHM_VERSION;
    header_->pixels_offset = (uint32_t)sizeof(wv_shm_header);
    header_->pixels_capacity = max_w * max_h * 4u;
    header_->seq = 0;
    header_->alive = 1;
    // Make header init visible to the reader before it polls the file.
    FlushViewOfFile(base_, sizeof(wv_shm_header));
    return true;
}

void WvShm::close() {
    if (header_) header_->alive = 0;
    if (base_) UnmapViewOfFile(base_);
    if (winMapping_) CloseHandle((HANDLE)winMapping_);
    if (winFile_) CloseHandle((HANDLE)winFile_);
    winFile_ = nullptr;
    winMapping_ = nullptr;
    base_ = nullptr;
    header_ = nullptr;
    pixels_ = nullptr;
    fd_ = -1;
}

#else  // POSIX

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

#endif  // _WIN32 / POSIX

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
    WV_FULL_FENCE();

    header_->width = width;
    header_->height = height;
    uint32_t n = num_dirty > WV_MAX_DIRTY ? WV_MAX_DIRTY : num_dirty;
    header_->num_dirty = n;
    if (dirty_xywh && n) {
        std::memcpy(header_->dirty, dirty_xywh, n * 4 * sizeof(int32_t));
    }
    std::memcpy(pixels_, bgra, bytes);

    WV_FULL_FENCE();
    header_->seq += 1;   // back to even, new frame published
}
