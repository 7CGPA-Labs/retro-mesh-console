#include <jni.h>
#include <vector>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include "retro-bridge.h"

// Web Caster zero-copy bridge
static std::mutex webMutex;
static std::vector<uint16_t> webBuffer(1920 * 1080); // Fixed size to prevent address changes
static std::atomic<int> webWidth{0};
static std::atomic<int> webHeight{0};

// WebCaster Z-RLE variables
static std::vector<uint8_t> webRleBuffer(1920 * 1080 * 2);
static std::atomic<int> webRleSize{0};
static std::mutex webSyncMutex;
static std::condition_variable webCondVar;
static bool webFrameReady = false;

extern "C" {

void webcaster_video_init() {
}

void webcaster_video_deinit() {
    std::lock_guard<std::mutex> syncLock(webSyncMutex);
    webFrameReady = true;
    webCondVar.notify_all();
}

void webcaster_video_push_frame(const void* data, unsigned width, unsigned height, size_t pitch, int pixel_format) {
    if (!data) return;
    const uint16_t* pixels = reinterpret_cast<const uint16_t*>(data);
    
    std::lock_guard<std::mutex> wLock(webMutex);
    webWidth.store(width);
    webHeight.store(height);
    size_t totalPixels = width * height;
    if (totalPixels <= 1920 * 1080) {
        uint16_t* dst = webBuffer.data();
        
        for (unsigned y = 0; y < height; y++) {
            const uint8_t* rowSrc = reinterpret_cast<const uint8_t*>(pixels) + (y * pitch);
            uint16_t* rowDst = dst + (y * width);
            
            if (pixel_format == 1) { // XRGB8888
                const uint32_t* src32 = reinterpret_cast<const uint32_t*>(rowSrc);
                for (unsigned x = 0; x < width; x++) {
                    uint32_t color = src32[x];
                    int r = (color >> 16) & 0xFF;
                    int g = (color >> 8) & 0xFF;
                    int b = color & 0xFF;
                    rowDst[x] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
                }
            } else if (pixel_format == 3) { // HW_GL_RGBA
                const uint8_t* src8 = reinterpret_cast<const uint8_t*>(rowSrc);
                for (unsigned x = 0; x < width; x++) {
                    int r = src8[x * 4 + 0];
                    int g = src8[x * 4 + 1];
                    int b = src8[x * 4 + 2];
                    rowDst[x] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
                }
            } else if (pixel_format == 0) { // 0RGB1555
                const uint16_t* src16 = reinterpret_cast<const uint16_t*>(rowSrc);
                for (unsigned x = 0; x < width; x++) {
                    uint16_t color = src16[x];
                    int r = (color >> 10) & 0x1F;
                    int g = (color >> 5) & 0x1F;
                    int b = color & 0x1F;
                    rowDst[x] = (r << 11) | ((g << 1) << 5) | b;
                }
            } else { // RGB565
                memcpy(rowDst, rowSrc, width * 2);
            }
        }
        
        // Z-RLE Compression
        int outIdx = 0;
        int i = 0;
        uint8_t* out = webRleBuffer.data();
        uint8_t* in = reinterpret_cast<uint8_t*>(dst);
        int byteCount = totalPixels * 2;
        
        while (i < byteCount) {
            int runLength = 1;
            int maxRun = 129;
            while (runLength < maxRun && i + (runLength * 2) < byteCount) {
                int nextIdx = i + (runLength * 2);
                if (in[nextIdx] == in[i] && in[nextIdx+1] == in[i+1]) {
                    runLength++;
                } else {
                    break;
                }
            }
            
            if (runLength >= 2) {
                out[outIdx++] = (runLength - 2) + 128;
                out[outIdx++] = in[i];
                out[outIdx++] = in[i+1];
                i += runLength * 2;
            } else {
                int rawLength = 1;
                int maxRaw = 128;
                while (rawLength < maxRaw && i + (rawLength * 2) < byteCount) {
                    int currIdx = i + (rawLength * 2);
                    int nextIdx = currIdx + 2;
                    if (nextIdx < byteCount && in[currIdx] == in[nextIdx] && in[currIdx+1] == in[nextIdx+1]) {
                        break;
                    }
                    rawLength++;
                }
                out[outIdx++] = rawLength - 1;
                memcpy(out + outIdx, in + i, rawLength * 2);
                outIdx += rawLength * 2;
                i += rawLength * 2;
            }
        }
        webRleSize.store(outIdx);
    }
    
    {
        std::lock_guard<std::mutex> syncLock(webSyncMutex);
        webFrameReady = true;
    }
    webCondVar.notify_all();
}

// --- WebCaster JNI ---

JNIEXPORT jobject JNICALL Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getFrameBuffer(JNIEnv* env, jobject thiz) {
    return env->NewDirectByteBuffer(webBuffer.data(), webBuffer.size() * sizeof(uint16_t));
}

JNIEXPORT jintArray JNICALL Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getFrameDimensions(JNIEnv* env, jobject thiz) {
    std::lock_guard<std::mutex> wLock(webMutex);
    jintArray result = env->NewIntArray(2);
    jint dims[2];
    dims[0] = webWidth.load();
    dims[1] = webHeight.load();
    env->SetIntArrayRegion(result, 0, 2, dims);
    return result;
}

JNIEXPORT jobject JNICALL Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getRleBuffer(JNIEnv* env, jobject thiz) {
    return env->NewDirectByteBuffer(webRleBuffer.data(), webRleBuffer.size());
}

JNIEXPORT jint JNICALL Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getRleSize(JNIEnv* env, jobject thiz) {
    return webRleSize.load();
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_WebCaster_waitForNextFrame(JNIEnv* env, jobject thiz) {
    std::unique_lock<std::mutex> lock(webSyncMutex);
    webCondVar.wait_for(lock, std::chrono::milliseconds(32), []{ return webFrameReady; });
    webFrameReady = false;
}

}
