#include <atomic>
#include <mutex>
#include "retro-bridge.h"

// Global state shared across modules
std::atomic<int> g_activePixelFormat{2};

// Input state
std::atomic<bool> ios_button_states[2][16];

extern "C" {

#include <thread>
#include <chrono>

static std::atomic<bool> emulator_running{false};
static std::thread emulator_thread;

// --- Threading ---
void start_native_emulator_thread(uintptr_t retro_run_ptr, double fps) {
    if (emulator_running.load()) return;
    emulator_running.store(true);
    typedef void (*retro_run_t)();
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
                run_func();
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

// --- Video Bridge ---
void render_to_window_ios(const uint16_t* pixels, int width, int height) {
    if (!pixels) return;
    int fmt = g_activePixelFormat.load();
    
    // Push to Miracast / Local display
    miracast_video_push_frame(pixels, width, height, width * 2, fmt);
}

// --- Audio Bridge ---
void native_audio_init(double sample_rate) {
    miracast_audio_init(sample_rate);
}

void native_audio_deinit() {
    miracast_audio_deinit();
}

size_t native_audio_sample_batch_cb(const int16_t* data, size_t frames) {
    miracast_audio_push_batch(data, frames);
    return frames;
}

void native_audio_sample_cb(int16_t left, int16_t right) {
    int16_t frame[2] = {left, right};
    native_audio_sample_batch_cb(frame, 1);
}

// --- Input & Environment ---
bool native_environment_cb(unsigned cmd, void *data) { return false; }
void native_input_poll_cb() {}

int16_t native_input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
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
    return ios_button_states[port][customId].load() ? 1 : 0;
}

__attribute__((visibility("default"))) __attribute__((used))
void set_player1_button(int customButtonId, bool pressed) {
    if (customButtonId >= 0 && customButtonId < 16) {
        ios_button_states[0][customButtonId].store(pressed);
    }
}

__attribute__((visibility("default"))) __attribute__((used))
void updatePlayer2Button(int buttonId, bool pressed) {
    if (buttonId >= 0 && buttonId < 16) {
        ios_button_states[1][buttonId].store(pressed);
    }
}

}
