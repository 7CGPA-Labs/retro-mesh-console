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

// C-API exposed to Dart FFI
extern "C" void render_to_window(const uint8_t* pixels, int width, int height) {
    std::lock_guard<std::mutex> lock(renderMutex);
    
    auto drawToWindow = [&](ANativeWindow* window) {
        if (!window) return;
        
        const int scale = 4;
        int scaledWidth = width * scale;
        int scaledHeight = height * scale;
        
        ANativeWindow_setBuffersGeometry(window, scaledWidth, scaledHeight, WINDOW_FORMAT_RGBA_8888);
        
        ANativeWindow_Buffer buffer;
        if (ANativeWindow_lock(window, &buffer, nullptr) == 0) {
            uint32_t* dst = static_cast<uint32_t*>(buffer.bits);
            const uint32_t* src = reinterpret_cast<const uint32_t*>(pixels);
            
            int dstStride = buffer.stride;
            
            for (int y = 0; y < height; ++y) {
                for (int sy = 0; sy < scale; ++sy) {
                    uint32_t* dstRow = dst + (y * scale + sy) * dstStride;
                    const uint32_t* srcRow = src + y * width;
                    for (int x = 0; x < width; ++x) {
                        uint32_t pixel = srcRow[x];
                        for (int sx = 0; sx < scale; ++sx) {
                            *dstRow++ = pixel;
                        }
                    }
                }
            }
            
            ANativeWindow_unlockAndPost(window);
        }
    };
    
    drawToWindow(flutterWindow);
    drawToWindow(tvWindow);
}
