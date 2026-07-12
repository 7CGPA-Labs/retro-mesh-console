#include <jni.h>
#include <atomic>
#include <thread>
#include <mutex>
#include "retro-bridge.h"

// Global state shared across modules
std::atomic<bool> g_webStreaming{false};
std::atomic<int> g_activePixelFormat{2};

// Input state
std::atomic<bool> button_states[2][16];
std::atomic<int16_t> analog_states[2][2][2]; // [port][index][id (0=X, 1=Y)]
std::atomic<int16_t> pointer_x{0};
std::atomic<int16_t> pointer_y{0};
std::atomic<bool> pointer_pressed{false};

// Emulator thread
typedef void (*retro_run_t)();
static std::atomic<bool> emulator_running{false};
static std::thread emulator_thread;

extern "C" {

// --- Threading ---
void start_native_emulator_thread(uintptr_t retro_run_ptr) {
    if (emulator_running.load()) return;
    emulator_running.store(true);
    retro_run_t run_func = reinterpret_cast<retro_run_t>(retro_run_ptr);
    
    emulator_thread = std::thread([run_func]() {
        while (emulator_running.load()) {
            run_func();
        }
    });
}

void stop_native_emulator_thread() {
    emulator_running.store(false);
    if (emulator_thread.joinable()) {
        emulator_thread.join();
    }
}

// --- Video Bridge ---
void render_to_window(const void* data, unsigned width, unsigned height, size_t pitch) {
    if (!data) return;
    int fmt = g_activePixelFormat.load();
    
    // Push to Miracast / Local display
    miracast_video_push_frame(data, width, height, pitch, fmt);
    
    // Push to WebCaster if active
    if (g_webStreaming.load()) {
        webcaster_video_push_frame(data, width, height, pitch, fmt);
    }
}

// --- Audio Bridge ---
void native_audio_init(double sample_rate) {
    miracast_audio_init(sample_rate);
    webcaster_audio_init(sample_rate);
}

void native_audio_deinit() {
    miracast_audio_deinit();
    webcaster_audio_deinit();
}

size_t native_audio_sample_batch_cb(const int16_t* data, size_t frames) {
    if (g_webStreaming.load()) {
        webcaster_audio_push_batch(data, frames);
        miracast_audio_push_silence(frames);
    } else {
        miracast_audio_push_batch(data, frames);
    }
    return frames;
}

void native_audio_sample_cb(int16_t left, int16_t right) {
    int16_t frame[2] = {left, right};
    native_audio_sample_batch_cb(frame, 1);
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
            *dir = "/sdcard/RetroMesh";
            return true;
        }
    } else if (cmd == 17) { // GET_VARIABLE_UPDATE
        if (data) {
            *static_cast<bool*>(data) = false;
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
    if (device == 1) { // RETRO_DEVICE_JOYPAD
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
            case 12: customId = 14; break; // L2
            case 13: customId = 15; break; // R2
            case 14: customId = 16; break; // L3
            case 15: customId = 17; break; // R3
        }
        if (customId == -1 || port > 1) return 0;
        return button_states[port][customId].load() ? 1 : 0;
    } 
    else if (device == 5) { // RETRO_DEVICE_ANALOG
        if (port > 1 || index > 1 || id > 1) return 0;
        return analog_states[port][index][id].load();
    }
    else if (device == 6) { // RETRO_DEVICE_POINTER
        if (port > 0) return 0; // Pointer usually only on port 0
        switch(id) {
            case 0: return pointer_x.load();
            case 1: return pointer_y.load();
            case 2: return pointer_pressed.load() ? 1 : 0;
        }
    }
    return 0;
}

void set_player1_button(int customButtonId, bool pressed) {
    if (customButtonId >= 0 && customButtonId < 16) {
        button_states[0][customButtonId].store(pressed);
    }
}

void set_player1_analog(int index, int id, int16_t value) {
    if (index >= 0 && index < 2 && id >= 0 && id < 2) {
        analog_states[0][index][id].store(value);
    }
}

void set_player1_pointer(int16_t x, int16_t y, bool pressed) {
    pointer_x.store(x);
    pointer_y.store(y);
    pointer_pressed.store(pressed);
}

// Dummy HW rendering functions to satisfy Dart FFI lookups
bool hw_render_init(int width, int height) { return false; }
void hw_render_extract_frame() {}
uintptr_t hw_get_current_framebuffer() { return 0; }
void* hw_get_proc_address(const char* sym) { return nullptr; }

// --- WebCaster State JNI & Utils ---
JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_WebCaster_setWebStreaming(JNIEnv* env, jobject thiz, jboolean streaming) {
    g_webStreaming.store(streaming);
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_WebCaster_setPixelFormat(JNIEnv* env, jobject thiz, jint fmt) {
    g_activePixelFormat.store(fmt);
}

void set_pixel_format(int fmt) {
    g_activePixelFormat.store(fmt);
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_NetworkManager_updatePlayer2Button(JNIEnv* env, jobject thiz, jint buttonId, jboolean pressed) {
    if (buttonId >= 0 && buttonId < 16) {
        button_states[1][buttonId].store(pressed);
    }
}

}
