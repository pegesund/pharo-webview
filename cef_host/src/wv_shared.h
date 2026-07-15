// Shared-memory layout for the CEF host <-> Pharo bridge.
// A single file is mmap'd by both processes. Layout:
//
//   [ wv_shm_header ][ pixel region: BGRA, pitch = width*4 ]
//
// Tearing: the writer uses a seqlock. `seq` is bumped to ODD before writing a
// frame and to EVEN (+1) after. A reader that wants a clean frame reads seq,
// copies/uploads, then re-reads seq; if it changed or was odd, the frame was
// mid-write. For zero-copy direct texture upload a reader may skip the recheck
// and tolerate the rare torn frame.
//
// This header is deliberately C-friendly (fixed-size ints, no C++), so the
// Pharo FFI side can read the same offsets.
#ifndef WV_SHARED_H
#define WV_SHARED_H

#include <stdint.h>

#define WV_SHM_MAGIC   0x57565348u  /* 'WVSH' */
#define WV_SHM_VERSION 1u
#define WV_MAX_DIRTY   16

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t magic;       /* WV_SHM_MAGIC once initialised          */
    uint32_t version;     /* WV_SHM_VERSION                          */
    uint32_t width;       /* current frame width  in pixels         */
    uint32_t height;      /* current frame height in pixels          */
    volatile uint32_t seq;/* seqlock: odd = write in progress        */
    uint32_t num_dirty;   /* number of valid dirty rects             */
    int32_t  dirty[WV_MAX_DIRTY * 4]; /* x,y,w,h quadruples          */
    uint32_t pixels_offset;/* byte offset of pixel region from base  */
    uint32_t pixels_capacity;/* capacity of the pixel region in bytes*/
    uint32_t alive;       /* host sets 1 while running, 0 on exit    */
    uint32_t reserved;
} wv_shm_header;

/* Total mapping size for a browser of at most max_w x max_h. */
static inline uint32_t wv_shm_size(uint32_t max_w, uint32_t max_h) {
    return (uint32_t)sizeof(wv_shm_header) + max_w * max_h * 4u;
}

#ifdef __cplusplus
}
#endif

#endif /* WV_SHARED_H */
