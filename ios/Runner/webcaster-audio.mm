#include <vector>
#include <mutex>
#include <string.h>
#include <stdint.h>
#include "retro-bridge.h"

static std::mutex webAudioMutex;
static std::vector<int16_t> webAudioBuffer;

extern "C" {

void webcaster_audio_init(double sample_rate) {}

void webcaster_audio_deinit() {
    std::lock_guard<std::mutex> lock(webAudioMutex);
    webAudioBuffer.clear();
}

void webcaster_audio_push_batch(const int16_t* data, size_t frames) {
    std::lock_guard<std::mutex> lock(webAudioMutex);
    
    // Apply 4.0x digital gain boost for WebCaster too
    std::vector<int16_t> boosted_data(frames * 2);
    for (size_t i = 0; i < frames * 2; ++i) {
        int32_t sample = (int32_t)data[i] * 4;
        if (sample > 32767) sample = 32767;
        if (sample < -32768) sample = -32768;
        boosted_data[i] = (int16_t)sample;
    }
    
    size_t samples = frames * 2;
    if (webAudioBuffer.size() > 44100 * 2) {
        webAudioBuffer.clear();
    }
    webAudioBuffer.insert(webAudioBuffer.end(), boosted_data.data(), boosted_data.data() + samples);
}

// Swift / Obj-C interface
__attribute__((visibility("default"))) __attribute__((used))
int get_web_audio_size() {
    std::lock_guard<std::mutex> lock(webAudioMutex);
    return (int)(webAudioBuffer.size() * sizeof(int16_t));
}

__attribute__((visibility("default"))) __attribute__((used))
int consume_web_audio(int16_t* out_buffer, int max_bytes) {
    std::lock_guard<std::mutex> lock(webAudioMutex);
    size_t max_samples = max_bytes / sizeof(int16_t);
    size_t copySize = std::min(webAudioBuffer.size(), max_samples);
    if (copySize > 0) {
        memcpy(out_buffer, webAudioBuffer.data(), copySize * sizeof(int16_t));
        webAudioBuffer.erase(webAudioBuffer.begin(), webAudioBuffer.begin() + copySize);
    }
    return (int)(copySize * sizeof(int16_t));
}

}
