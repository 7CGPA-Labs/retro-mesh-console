#include <vector>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include "retro-bridge.h"

// Web Caster zero-copy bridge
static std::mutex webMutex;
static std::vector<uint16_t> webBuffer(1920 * 1080);
static std::atomic<int> webWidth{0};
static std::atomic<int> webHeight{0};

extern "C" {

void webcaster_video_init() {}
void webcaster_video_deinit() {}

void webcaster_video_push_frame(const void* data, unsigned width, unsigned height, size_t pitch, int pixel_format) {
    if (!data) return;
    const uint16_t* pixels = reinterpret_cast<const uint16_t*>(data);
    
    std::lock_guard<std::mutex> wLock(webMutex);
    webWidth.store(width);
    webHeight.store(height);
    size_t totalPixels = width * height;
    if (totalPixels <= 1920 * 1080) {
        memcpy(webBuffer.data(), pixels, totalPixels * sizeof(uint16_t));
    }
}

// Swift / Obj-C interface
__attribute__((visibility("default"))) __attribute__((used))
const uint16_t* get_web_buffer() {
    return webBuffer.data();
}

__attribute__((visibility("default"))) __attribute__((used))
int get_web_width() {
    return webWidth.load();
}

__attribute__((visibility("default"))) __attribute__((used))
int get_web_height() {
    return webHeight.load();
}

}
