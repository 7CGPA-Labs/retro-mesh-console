#include <jni.h>
#include <android/native_window_jni.h>
#include <android/native_window.h>
#include <android/log.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <cstring>
#include <mutex>
#include <thread>
#include <condition_variable>
#include <vector>
#include <atomic>
#include "retro-bridge.h"

#define LOG_TAG "MiracastRender"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static ANativeWindow* tvWindow = nullptr;
static std::mutex renderMutex;

static int tvWidth = 256;
static int tvHeight = 224;
static std::vector<uint8_t> rawTvBuffer;
static int tvPixelFormat = 0;
static size_t tvPitch = 0;
static std::mutex tvMutex;
static std::condition_variable tvCondVar;
static std::atomic<bool> tvThreadRunning{false};
static std::atomic<bool> tvFrameReady{false};
static std::atomic<float> thermalScale{1.0f};

static void TvRenderWorker() {
    ANativeWindow* lastTvWindow = nullptr;
    std::vector<uint8_t> localRawTvBuffer;

    while (tvThreadRunning) {
        std::unique_lock<std::mutex> lock(tvMutex);
        tvCondVar.wait(lock, [] { return tvFrameReady.load() || !tvThreadRunning.load(); });
        
        if (!tvThreadRunning) break;
        
        // Copy to local buffer to unlock mutex immediately
        if (localRawTvBuffer.size() != rawTvBuffer.size()) {
            localRawTvBuffer.resize(rawTvBuffer.size());
        }
        std::memcpy(localRawTvBuffer.data(), rawTvBuffer.data(), rawTvBuffer.size());
        
        int lWidth = tvWidth;
        int lHeight = tvHeight;
        int lPitch = tvPitch;
        int lFormat = tvPixelFormat;
        ANativeWindow* currentTvWindow = tvWindow;
        
        tvFrameReady = false;
        
        // UNLOCK immediately! This prevents ANativeWindow_unlockAndPost (VSync) from blocking the emulator audio/video!
        lock.unlock();
        
        if (currentTvWindow != lastTvWindow) {
            lastTvWindow = currentTvWindow;
            if (currentTvWindow) {
                // Force window geometry to match game resolution and format (RGBA_8888)
                ANativeWindow_setBuffersGeometry(currentTvWindow, lWidth, lHeight, WINDOW_FORMAT_RGBA_8888);
            }
        }

        if (currentTvWindow) {
            ANativeWindow_Buffer buffer;
            if (ANativeWindow_lock(currentTvWindow, &buffer, nullptr) == 0) {
                
                // Software pixel conversion and copy directly to NativeWindow buffer
                for (unsigned y = 0; y < lHeight; y++) {
                    const uint8_t* rowSrc = localRawTvBuffer.data() + (y * lPitch);
                    uint8_t* rowDst = static_cast<uint8_t*>(buffer.bits) + (y * buffer.stride * 4);
                    
                    if (lFormat == 1) { // XRGB8888
                        const uint32_t* src32 = reinterpret_cast<const uint32_t*>(rowSrc);
                        uint32_t* dst32 = reinterpret_cast<uint32_t*>(rowDst);
                        for (unsigned x = 0; x < lWidth; x++) {
                            uint32_t color = src32[x];
                            uint32_t r = (color >> 16) & 0xFF;
                            uint32_t g = (color >> 8) & 0xFF;
                            uint32_t b = color & 0xFF;
                            dst32[x] = (0xFFu << 24) | (b << 16) | (g << 8) | r;
                        }
                    } else if (lFormat == 0) { // 0RGB1555
                        const uint16_t* src16 = reinterpret_cast<const uint16_t*>(rowSrc);
                        uint32_t* dst32 = reinterpret_cast<uint32_t*>(rowDst);
                        for (unsigned x = 0; x < lWidth; x++) {
                            uint16_t color = src16[x];
                            uint32_t r = ((color >> 10) & 0x1F) << 3;
                            uint32_t g = ((color >> 5) & 0x1F) << 3;
                            uint32_t b = (color & 0x1F) << 3;
                            dst32[x] = (0xFFu << 24) | (b << 16) | (g << 8) | r;
                        }
                    } else { // RGB565
                        const uint16_t* src16 = reinterpret_cast<const uint16_t*>(rowSrc);
                        uint32_t* dst32 = reinterpret_cast<uint32_t*>(rowDst);
                        for (unsigned x = 0; x < lWidth; x++) {
                            uint16_t color = src16[x];
                            uint32_t r = ((color >> 11) & 0x1F) << 3;
                            uint32_t g = ((color >> 5) & 0x3F) << 2;
                            uint32_t b = (color & 0x1F) << 3;
                            dst32[x] = (0xFFu << 24) | (b << 16) | (g << 8) | r;
                        }
                    }
                }
                
                ANativeWindow_unlockAndPost(currentTvWindow);
            }
        }
    }
}

extern "C" {

void miracast_video_init() {
    // Initialization handled dynamically when frames arrive
}

void miracast_video_deinit() {
    std::lock_guard<std::mutex> lock(renderMutex);
    tvThreadRunning = false;
    tvCondVar.notify_all();
}

void miracast_video_push_frame(const void* data, unsigned width, unsigned height, size_t pitch, int pixel_format) {
    if (!data || width == 0 || height == 0) return;
    
    // Thermal CPU Throttling logic
    float tScale = thermalScale.load();
    if (tScale < 1.0f) {
        static int frameCounter = 0;
        frameCounter++;
        // Skip frames aggressively to cool down CPU when thermal throttling kicks in
        if (tScale < 0.6f && (frameCounter % 3) != 0) return; // Cap at ~20fps
        else if (tScale < 0.9f && (frameCounter % 2) != 0) return; // Cap at ~30fps
    }
    
    std::lock_guard<std::mutex> lock(renderMutex);
    
    if (!tvThreadRunning) {
        tvThreadRunning = true;
        std::thread(TvRenderWorker).detach();
    }
    
    if (tvWindow) {
        std::lock_guard<std::mutex> tvLock(tvMutex);
        tvWidth = width;
        tvHeight = height;
        tvPitch = pitch;
        tvPixelFormat = pixel_format;
        
        size_t requiredSize = pitch * height;
        if (rawTvBuffer.size() != requiredSize) {
            rawTvBuffer.resize(requiredSize);
        }
        std::memcpy(rawTvBuffer.data(), data, requiredSize);
        
        tvFrameReady = true;
        tvCondVar.notify_one();
    }
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_NativeRender_setTvSurface(JNIEnv* env, jclass clazz, jobject surface) {
    std::lock_guard<std::mutex> lock(renderMutex);
    
    if (tvWindow) {
        ANativeWindow_release(tvWindow);
        tvWindow = nullptr;
    }
    
    if (surface) {
        tvWindow = ANativeWindow_fromSurface(env, surface);
    }
}

bool is_tv_connected() {
    return tvWindow != nullptr;
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_ThermalManager_setThermalScale(JNIEnv* env, jobject thiz, jfloat scale) {
    thermalScale.store(scale);
}

}
