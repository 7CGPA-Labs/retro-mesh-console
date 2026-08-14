#include <jni.h>
#include <atomic>
#include <thread>
#include <mutex>
#include <chrono>
#include "retro-bridge.h"
#include "libretro-frontend.h"
#include <android/log.h>

static JavaVM* g_vm = nullptr;
static jclass g_loggerClass = nullptr;
static jobject g_loggerInstance = nullptr;
static jmethodID g_logMethod = nullptr;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

extern "C" void sendLogToKotlin(const char* tag, const char* msg) {
    if (!g_vm || !g_loggerClass || !g_loggerInstance || !g_logMethod) return;
    JNIEnv* env;
    bool attached = false;
    int status = g_vm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (g_vm->AttachCurrentThread(&env, nullptr) != 0) return;
        attached = true;
    } else if (status != JNI_OK) {
        return;
    }

    jstring jTag = env->NewStringUTF(tag);
    jstring jMsg = env->NewStringUTF(msg);
    env->CallVoidMethod(g_loggerInstance, g_logMethod, jTag, jMsg);
    env->DeleteLocalRef(jTag);
    env->DeleteLocalRef(jMsg);

    if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }

    if (attached) {
        g_vm->DetachCurrentThread();
    }
}

// Global state shared across modules
std::atomic<int> g_activePixelFormat{0};

// Input state
std::atomic<bool> button_states[2][16];
std::atomic<int16_t> analog_states[2][2][2]; // [port][index][id (0=X, 1=Y)]

// Emulator thread
typedef void (*retro_run_t)();
static std::atomic<bool> emulator_running{false};
static std::atomic<bool> emulator_paused{false};
static std::thread emulator_thread;

extern "C" {

// Removed rumble interface

// --- Threading ---
void start_native_emulator_thread(uintptr_t retro_run_ptr, double fps) {
    if (emulator_running.load()) return;
    emulator_running.store(true);
    retro_run_t run_func = reinterpret_cast<retro_run_t>(retro_run_ptr);
    
    emulator_thread = std::thread([run_func, fps]() {
        double current_fps = (fps <= 0.0) ? 60.0 : fps;
        double targetFrameTime = 1.0 / current_fps;
        auto lastTime = std::chrono::steady_clock::now();
        double accumulator = 0.0;
        
        while (emulator_running.load()) {
            auto currentTime = std::chrono::steady_clock::now();
            double dt = std::chrono::duration<double>(currentTime - lastTime).count();
            lastTime = currentTime;
            
            accumulator += dt;
            if (accumulator > 0.1) accumulator = 0.1;
            
            while (accumulator >= targetFrameTime && emulator_running.load()) {
                if (!emulator_paused.load()) {
                    run_func();
                }
                accumulator -= targetFrameTime;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    });
}

void stop_native_emulator_thread() {
    emulator_running.store(false);
    if (emulator_thread.joinable()) {
        emulator_thread.join();
    }
}

void set_native_emulator_paused(bool paused) {
    emulator_paused.store(paused);
}

// --- Video Bridge ---
void render_to_window(const void* data, unsigned width, unsigned height, size_t pitch) {
    if (!data) return;
    int fmt = g_activePixelFormat.load();
    
    // Push to Miracast / Local display
    miracast_video_push_frame(data, width, height, pitch, fmt);
}

// --- Audio Bridge ---
void native_audio_init(double sample_rate) {
    miracast_audio_init(sample_rate);
}

void native_audio_deinit() {
    miracast_audio_deinit();
}

void native_video_deinit() {
    miracast_video_deinit();
}

size_t native_audio_sample_batch_cb(const int16_t* data, size_t frames) {
    miracast_audio_push_batch(data, frames);
    return frames;
}

void native_audio_sample_cb(int16_t left, int16_t right) {
    int16_t frame[2] = {left, right};
    native_audio_sample_batch_cb(frame, 1);
}

static void core_log_cb(int level, const char *fmt, ...) {
    char buffer[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    sendLogToKotlin("CoreLog", buffer);
}

// --- Input & Environment ---
bool native_environment_cb(unsigned cmd, void *data) {
    if (cmd == 10) { // RETRO_ENVIRONMENT_SET_PIXEL_FORMAT
        if (data) {
            g_activePixelFormat.store(*static_cast<int*>(data));
            return true;
        }
    } else if (cmd == 9 || cmd == 31) { // GET_SYSTEM_DIRECTORY or GET_SAVE_DIRECTORY
        if (data) {
            const char** dir = static_cast<const char**>(data);
            *dir = "/storage/emulated/0/Android/data/dev.seven_cgpalabs.mojosnap/files";
            return true;
        }
    } else if (cmd == 8) { // RETRO_ENVIRONMENT_GET_CAN_DUPE
        if (data) {
            *static_cast<bool*>(data) = true;
            return true;
        }
    } else if (cmd == 32) { // RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO
        return true;
    } else if (cmd == 37) { // RETRO_ENVIRONMENT_SET_GEOMETRY
        return true;
    } else if (cmd == 17) { // GET_VARIABLE_UPDATE
        if (data) {
            *static_cast<bool*>(data) = false;
            return true;
        }
    } else if (cmd == 27) { // RETRO_ENVIRONMENT_GET_LOG_INTERFACE
        struct retro_log_callback {
            void (*log)(int level, const char *fmt, ...);
        };
        if (data) {
            auto* cb = static_cast<retro_log_callback*>(data);
            cb->log = core_log_cb;
            return true;
        }
    } else if (cmd == 15) { // GET_VARIABLE
        return false;
    } else if (cmd == 16) { // SET_VARIABLES
        return true;
    }
    return false;
}

void native_input_poll_cb() {
}

int16_t native_input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port >= 2) return 0;
    
    unsigned device_type = device & 0xFF; // RETRO_DEVICE_MASK

    if (device_type == 1) { // RETRO_DEVICE_JOYPAD
        if (id == 256) { // RETRO_DEVICE_ID_JOYPAD_MASK
            int16_t mask = 0;
            for (int i = 0; i < 16; i++) {
                if (button_states[port][i].load()) {
                    mask |= (1 << i);
                }
            }
            // Analog-to-digital fallback for D-Pad
            int16_t lx = analog_states[port][0][0].load();
            int16_t ly = analog_states[port][0][1].load();
            if (ly < -16000) mask |= (1 << 4); // UP
            if (ly > 16000)  mask |= (1 << 5); // DOWN
            if (lx < -16000) mask |= (1 << 6); // LEFT
            if (lx > 16000)  mask |= (1 << 7); // RIGHT
            return mask;
        }

        if (id < 16) {
            if (button_states[port][id].load()) {
                return 1;
            }
            // Analog-to-digital fallback for D-Pad
            if (id == 4) { // UP
                return (analog_states[port][0][1].load() < -16000) ? 1 : 0;
            } else if (id == 5) { // DOWN
                return (analog_states[port][0][1].load() > 16000) ? 1 : 0;
            } else if (id == 6) { // LEFT
                return (analog_states[port][0][0].load() < -16000) ? 1 : 0;
            } else if (id == 7) { // RIGHT
                return (analog_states[port][0][0].load() > 16000) ? 1 : 0;
            }
        }
        return 0;
    } 
    else if (device_type == 5) { // RETRO_DEVICE_ANALOG
        if (index == 2) { // RETRO_DEVICE_INDEX_ANALOG_BUTTON
            if (id < 16) {
                return button_states[port][id].load() ? 1 : 0;
            }
            return 0;
        }
        if (index < 2 && id < 2) {
            int16_t val = analog_states[port][index][id].load();
            if (val != 0) return val;
            
            // Digital-to-analog fallback for Left Analog (index 0)
            if (index == 0) {
                if (id == 0) { // X axis
                    if (button_states[port][6].load()) return -32767; // LEFT
                    if (button_states[port][7].load()) return 32767;  // RIGHT
                } else if (id == 1) { // Y axis
                    if (button_states[port][4].load()) return -32767; // UP
                    if (button_states[port][5].load()) return 32767;  // DOWN
                }
            }
            return 0;
        }
    }
    return 0;
}

void set_player1_button(int buttonId, bool pressed) {
    if (buttonId >= 0 && buttonId < 16) {
        button_states[0][buttonId].store(pressed);
    }
}

void set_player1_analog(int index, int id, int16_t value) {
    if (index >= 0 && index < 2 && id >= 0 && id < 2) {
        analog_states[0][index][id].store(value);
    }
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_NetworkManager_updatePlayer2Button(JNIEnv* env, jobject thiz, jint buttonId, jboolean pressed) {
    if (buttonId >= 0 && buttonId < 16) {
        button_states[1][buttonId].store(pressed);
    }
}

JNIEXPORT jboolean JNICALL Java_dev_seven_1cgpalabs_mojosnap_MainActivity_loadGame(JNIEnv* env, jobject thiz, jstring coreDir, jstring romPath) {
    if (!g_loggerClass) {
        jclass localLoggerClass = env->FindClass("dev/seven_cgpalabs/mojosnap/utils/ConsoleLogger");
        if (localLoggerClass) {
            g_loggerClass = (jclass)env->NewGlobalRef(localLoggerClass);
            jfieldID instanceField = env->GetStaticFieldID(localLoggerClass, "INSTANCE", "Ldev/seven_cgpalabs/mojosnap/utils/ConsoleLogger;");
            if (instanceField) {
                jobject instance = env->GetStaticObjectField(localLoggerClass, instanceField);
                g_loggerInstance = env->NewGlobalRef(instance);
                g_logMethod = env->GetMethodID(localLoggerClass, "log", "(Ljava/lang/String;Ljava/lang/String;)V");
                env->DeleteLocalRef(instance);
            }
            env->DeleteLocalRef(localLoggerClass);
        }
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
        }
    }

    const char* c_core_dir = env->GetStringUTFChars(coreDir, NULL);
    const char* c_rom_path = env->GetStringUTFChars(romPath, NULL);
    
    bool result = frontend_init_and_load(c_core_dir, c_rom_path);
    
    env->ReleaseStringUTFChars(coreDir, c_core_dir);
    env->ReleaseStringUTFChars(romPath, c_rom_path);
    return result;
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_MainActivity_setButtonState(JNIEnv* env, jobject thiz, jint port, jint buttonId, jboolean pressed) {
    if (port >= 0 && port < 2 && buttonId >= 0 && buttonId < 16) {
        button_states[port][buttonId].store(pressed);
    }
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_MainActivity_setAnalogState(JNIEnv* env, jobject thiz, jint port, jint index, jint id, jint value) {
    if (port >= 0 && port < 2 && index >= 0 && index < 2 && id >= 0 && id < 2) {
        analog_states[port][index][id].store(static_cast<int16_t>(value));
    }
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_MainActivity_togglePause(JNIEnv* env, jobject thiz) {
    frontend_toggle_pause();
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_MainActivity_resetGame(JNIEnv* env, jobject thiz) {
    frontend_reset();
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_MainActivity_shutdown(JNIEnv* env, jobject thiz) {
    frontend_deinit();
}

JNIEXPORT jboolean JNICALL Java_dev_seven_1cgpalabs_mojosnap_MainActivity_saveState(JNIEnv* env, jobject thiz, jint slot, jstring saveDir) {
    const char* c_save_dir = env->GetStringUTFChars(saveDir, NULL);
    bool result = frontend_save_state(slot, c_save_dir);
    env->ReleaseStringUTFChars(saveDir, c_save_dir);
    return result;
}

JNIEXPORT jboolean JNICALL Java_dev_seven_1cgpalabs_mojosnap_MainActivity_loadState(JNIEnv* env, jobject thiz, jint slot, jstring saveDir) {
    const char* c_save_dir = env->GetStringUTFChars(saveDir, NULL);
    bool result = frontend_load_state(slot, c_save_dir);
    env->ReleaseStringUTFChars(saveDir, c_save_dir);
    return result;
}

}
