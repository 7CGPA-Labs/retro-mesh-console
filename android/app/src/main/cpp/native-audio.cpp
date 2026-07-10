#include <aaudio/AAudio.h>
#include <mutex>
#include <vector>
#include <string.h>
#include <stdint.h>
#include <atomic>
#include <android/log.h>

#define LOG_TAG "NativeAudio"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern std::atomic<bool> webStreaming;
extern "C" void web_audio_batch_cb(const int16_t* data, intptr_t frames);

static AAudioStreamBuilder* builder = nullptr;
static AAudioStream* stream = nullptr;
static bool g_audio_initialized = false;

extern "C" {

__attribute__((visibility("default"))) __attribute__((used))
void native_audio_init(double sample_rate) {
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
    // CRITICAL: We DO NOT set a dataCallback. We want to write BLOCKING to throttle the core!
    
    if (AAudioStreamBuilder_openStream(builder, &stream) != AAUDIO_OK) {
        AAudioStreamBuilder_delete(builder);
        builder = nullptr;
        return;
    }

    // Set buffer size to effectively pace it (e.g. 2 bursts for low latency)
    int32_t framesPerBurst = AAudioStream_getFramesPerBurst(stream);
    AAudioStream_setBufferSizeInFrames(stream, framesPerBurst * 2);

    AAudioStream_requestStart(stream);
    
    AAudioStreamBuilder_delete(builder);
    builder = nullptr;
    
    g_audio_initialized = true;
}

__attribute__((visibility("default"))) __attribute__((used))
void native_audio_deinit() {
    if (!g_audio_initialized) return;
    AAudioStream_requestStop(stream);
    AAudioStream_close(stream);
    stream = nullptr;
    g_audio_initialized = false;
}

__attribute__((visibility("default"))) __attribute__((used))
size_t native_audio_sample_batch_cb(const int16_t* data, size_t frames) {
    if (!g_audio_initialized || !stream) return frames;
    
    web_audio_batch_cb(data, frames);
    
    if (webStreaming.load()) {
        // To maintain perfect pacing without playing sound on the device speaker,
        // we write silence (zeros) to the AAudio stream.
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
        return frames;
    }

    int64_t timeoutNanos = 1000 * 1000 * 1000; // 1 second timeout
    int32_t framesLeft = frames;
    const int16_t* p = data;
    
    while (framesLeft > 0) {
        aaudio_result_t result = AAudioStream_write(stream, p, framesLeft, timeoutNanos);
        if (result < 0) {
            LOGE("AAudio stream write failed: %s", AAudio_convertResultToText(result));
            break;
        }
        framesLeft -= result;
        p += (result * 2);
    }
    return frames;
}

extern "C" void native_audio_sample_cb(int16_t left, int16_t right) {
    int16_t frame[2] = {left, right};
    native_audio_sample_batch_cb(frame, 1);
}

}
