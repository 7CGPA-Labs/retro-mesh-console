#include <aaudio/AAudio.h>
#include <mutex>
#include <vector>
#include <string.h>
#include <stdint.h>
#include <atomic>
#include <android/log.h>
#include "retro-bridge.h"

#define LOG_TAG "MiracastAudio"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static AAudioStreamBuilder* builder = nullptr;
static AAudioStream* stream = nullptr;
static bool g_audio_initialized = false;

extern "C" {

void miracast_audio_init(double sample_rate) {
    if (g_audio_initialized) return;

    AAudio_createStreamBuilder(&builder);
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_I16);
    AAudioStreamBuilder_setChannelCount(builder, 2);
    if (sample_rate > 0) {
        AAudioStreamBuilder_setSampleRate(builder, (int32_t)sample_rate);
    }
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setUsage(builder, AAUDIO_USAGE_MEDIA);
    AAudioStreamBuilder_setContentType(builder, AAUDIO_CONTENT_TYPE_MUSIC);
    AAudioStreamBuilder_setAllowedCapturePolicy(builder, AAUDIO_ALLOW_CAPTURE_BY_ALL);
    
    if (AAudioStreamBuilder_openStream(builder, &stream) != AAUDIO_OK) {
        AAudioStreamBuilder_delete(builder);
        builder = nullptr;
        return;
    }

    int32_t framesPerBurst = AAudioStream_getFramesPerBurst(stream);
    AAudioStream_setBufferSizeInFrames(stream, framesPerBurst * 2);

    AAudioStream_requestStart(stream);
    
    AAudioStreamBuilder_delete(builder);
    builder = nullptr;
    
    g_audio_initialized = true;
}

void miracast_audio_deinit() {
    if (!g_audio_initialized) return;
    AAudioStream_requestStop(stream);
    AAudioStream_close(stream);
    stream = nullptr;
    g_audio_initialized = false;
}

void miracast_audio_push_batch(const int16_t* data, size_t frames) {
    if (!g_audio_initialized || !stream || !is_tv_connected()) return;
    
    // Apply 4.0x digital gain boost for Miracast / WebCaster
    static std::vector<int16_t> boosted_data;
    if (boosted_data.size() < frames * 2) {
        boosted_data.resize(frames * 2);
    }
    for (size_t i = 0; i < frames * 2; ++i) {
        int32_t sample = (int32_t)data[i] * 4;
        if (sample > 32767) sample = 32767;
        if (sample < -32768) sample = -32768;
        boosted_data[i] = (int16_t)sample;
    }
    
    int64_t timeoutNanos = 1000 * 1000 * 1000;
    int32_t framesLeft = frames;
    const int16_t* p = boosted_data.data();
    
    while (framesLeft > 0) {
        aaudio_result_t result = AAudioStream_write(stream, p, framesLeft, timeoutNanos);
        if (result < 0) {
            LOGE("AAudio stream write failed: %s", AAudio_convertResultToText(result));
            break;
        }
        framesLeft -= result;
        p += (result * 2);
    }
}

void miracast_audio_push_silence(size_t frames) {
    if (!g_audio_initialized || !stream) return;
    
    static std::vector<int16_t> silenceBuffer(8192, 0);
    if (silenceBuffer.size() < frames * 2) {
        silenceBuffer.resize(frames * 2, 0);
    }
    
    int64_t timeoutNanos = 1000 * 1000 * 1000;
    int32_t framesLeft = frames;
    const int16_t* p = silenceBuffer.data();
    
    while (framesLeft > 0) {
        aaudio_result_t result = AAudioStream_write(stream, p, framesLeft, timeoutNanos);
        if (result < 0) break;
        framesLeft -= result;
        p += (result * 2);
    }
}

}
