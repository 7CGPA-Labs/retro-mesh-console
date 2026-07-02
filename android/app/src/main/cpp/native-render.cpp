#include <jni.h>
#include <android/native_window_jni.h>
#include <android/native_window.h>
#include <android/log.h>
#include <cstring>
#include <mutex>

#define LOG_TAG "NativeRender"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

ANativeWindow* flutterWindow = nullptr;
ANativeWindow* tvWindow = nullptr;
std::mutex renderMutex;

extern "C" JNIEXPORT void JNICALL
Java_com_retromesh_retro_1mesh_1console_NativeRender_setFlutterSurface(JNIEnv* env, jclass clazz, jobject surface) {
    std::lock_guard<std::mutex> lock(renderMutex);
    if (flutterWindow) {
        ANativeWindow_release(flutterWindow);
        flutterWindow = nullptr;
    }
    if (surface != nullptr) {
        flutterWindow = ANativeWindow_fromSurface(env, surface);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_retromesh_retro_1mesh_1console_NativeRender_setTvSurface(JNIEnv* env, jclass clazz, jobject surface) {
    std::lock_guard<std::mutex> lock(renderMutex);
    if (tvWindow) {
        ANativeWindow_release(tvWindow);
        tvWindow = nullptr;
    }
    if (surface != nullptr) {
        tvWindow = ANativeWindow_fromSurface(env, surface);
    }
}

#include <thread>
#include <condition_variable>
#include <vector>
#include <atomic>

// Background thread state for TV rendering
std::vector<uint16_t> tvBuffer;
std::mutex tvMutex;
std::condition_variable tvCondVar;
std::atomic<bool> tvThreadRunning{false};
std::atomic<bool> tvFrameReady{false};
int tvWidth = 256;
int tvHeight = 224;

void TvRenderWorker() {
    while (tvThreadRunning) {
        std::unique_lock<std::mutex> lock(tvMutex);
        tvCondVar.wait(lock, [] { return tvFrameReady.load() || !tvThreadRunning.load(); });
        
        if (!tvThreadRunning) break;
        
        if (tvWindow) {
            // No crisp scaling loop. Use exact 1:1 dimensions and let SurfaceFlinger stretch it seamlessly.
            ANativeWindow_setBuffersGeometry(tvWindow, tvWidth, tvHeight, WINDOW_FORMAT_RGB_565);
            
            ANativeWindow_Buffer buffer;
            if (ANativeWindow_lock(tvWindow, &buffer, nullptr) == 0) {
                uint16_t* dst = static_cast<uint16_t*>(buffer.bits);
                const uint16_t* src = tvBuffer.data();
                
                int dstStride = buffer.stride;
                
                for (int y = 0; y < tvHeight; ++y) {
                    memcpy(dst + (y * dstStride), src + (y * tvWidth), tvWidth * sizeof(uint16_t));
                }
                
                ANativeWindow_unlockAndPost(tvWindow);
            }
        }
        tvFrameReady = false;
    }
}

// C-API exposed to Dart FFI
extern "C" void render_to_window(const uint16_t* pixels, int width, int height) {
    std::lock_guard<std::mutex> lock(renderMutex);
    
    // Start background thread if not running
    if (!tvThreadRunning) {
        tvThreadRunning = true;
        std::thread(TvRenderWorker).detach();
    }
    
    // Dispatch to TV worker thread for crisp 4x scaling (non-blocking)
    if (tvWindow) {
        std::lock_guard<std::mutex> tvLock(tvMutex);
        tvWidth = width;
        tvHeight = height;
        size_t totalPixels = width * height;
        if (tvBuffer.size() != totalPixels) {
            tvBuffer.resize(totalPixels);
        }
        memcpy(tvBuffer.data(), pixels, totalPixels * sizeof(uint16_t));
        tvFrameReady = true;
        tvCondVar.notify_one();
    }
}

// --- Native Input Management ---

std::atomic<bool> button_states[2][16];

extern "C" int16_t native_input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (device != 1) return 0; // RETRO_DEVICE_JOYPAD = 1
    
    int customId = -1;
    switch (id) {
        case 0: customId = 6; break; // B
        case 1: customId = 8; break; // Y
        case 2: customId = 10; break; // SELECT
        case 3: customId = 9; break; // START
        case 4: customId = 1; break; // UP
        case 5: customId = 2; break; // DOWN
        case 6: customId = 3; break; // LEFT
        case 7: customId = 4; break; // RIGHT
        case 8: customId = 5; break; // A
        case 9: customId = 7; break; // X
        case 10: customId = 11; break; // L
        case 11: customId = 12; break; // R
    }
    
    if (customId == -1 || port > 1) return 0;
    return button_states[port][customId].load() ? 1 : 0;
}

extern "C" void set_player1_button(int customButtonId, bool pressed) {
    if (customButtonId >= 0 && customButtonId < 16) {
        button_states[0][customButtonId].store(pressed);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_retromesh_retro_1mesh_1console_NetworkManager_updatePlayer2Button(JNIEnv* env, jobject thiz, jint buttonId, jboolean pressed) {
    if (buttonId >= 0 && buttonId < 16) {
        button_states[1][buttonId].store(pressed);
    }
}
