#include <jni.h>
#include <mutex>
#include <vector>
#include <string.h>
#include <stdint.h>
#include "retro-bridge.h"

static std::mutex webAudioMutex;
static std::vector<int16_t> webAudioBuffer;
static std::vector<int16_t> fixedWebAudio(44100 * 2);

extern "C" {

void webcaster_audio_init(double sample_rate) {
}

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

// --- WebCaster JNI ---

JNIEXPORT jobject JNICALL Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getAudioBuffer(JNIEnv* env, jobject thiz) {
    return env->NewDirectByteBuffer(fixedWebAudio.data(), fixedWebAudio.size() * sizeof(int16_t));
}

JNIEXPORT jint JNICALL Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getAudioSize(JNIEnv* env, jobject thiz) {
    std::lock_guard<std::mutex> lock(webAudioMutex);
    return (jint)(webAudioBuffer.size() * sizeof(int16_t));
}

JNIEXPORT jint JNICALL Java_dev_seven_1cgpalabs_mojosnap_WebCaster_consumeAudioBuffer(JNIEnv* env, jobject thiz) {
    std::lock_guard<std::mutex> lock(webAudioMutex);
    size_t copySize = std::min(webAudioBuffer.size(), fixedWebAudio.size());
    if (copySize > 0) {
        memcpy(fixedWebAudio.data(), webAudioBuffer.data(), copySize * sizeof(int16_t));
        webAudioBuffer.erase(webAudioBuffer.begin(), webAudioBuffer.begin() + copySize);
    }
    return (jint)(copySize * sizeof(int16_t));
}

}
