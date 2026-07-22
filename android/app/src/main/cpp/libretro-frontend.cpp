#include "libretro-frontend.h"
#include <dlfcn.h>
#include <string>
#include <vector>
#include <android/log.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern "C" void sendLogToKotlin(const char* tag, const char* msg);

#define LOG_TAG "LibretroFrontend"
#define LOGI(...) do { \
    __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__); \
    char buf[512]; \
    snprintf(buf, sizeof(buf), __VA_ARGS__); \
    sendLogToKotlin(LOG_TAG, buf); \
} while(0)
#define LOGE(...) do { \
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__); \
    char buf[512]; \
    snprintf(buf, sizeof(buf), __VA_ARGS__); \
    sendLogToKotlin(LOG_TAG, buf); \
} while(0)

// Libretro structures & types
struct retro_game_info {
    const char *path;
    const void *data;
    size_t      size;
    const char *meta;
};

struct retro_system_info {
    const char *library_name;
    const char *library_version;
    const char *valid_extensions;
    bool        need_fullpath;
    bool        block_extract;
};

struct retro_game_geometry {
    unsigned base_width;
    unsigned base_height;
    unsigned max_width;
    unsigned max_height;
    float    aspect_ratio;
};

struct retro_system_timing {
    double fps;
    double sample_rate;
};

struct retro_system_av_info {
    struct retro_game_geometry geometry;
    struct retro_system_timing timing;
};

typedef bool (*retro_environment_t)(unsigned cmd, void *data);
typedef void (*retro_video_refresh_t)(const void *data, unsigned width, unsigned height, size_t pitch);
typedef void (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t (*retro_audio_sample_batch_t)(const int16_t *data, size_t frames);
typedef void (*retro_input_poll_t)(void);
typedef int16_t (*retro_input_state_t)(unsigned port, unsigned device, unsigned index, unsigned id);

// Libretro API function pointers
static void (*retro_init)(void) = nullptr;
static void (*retro_deinit)(void) = nullptr;
static void (*retro_set_environment)(retro_environment_t) = nullptr;
static void (*retro_set_video_refresh)(retro_video_refresh_t) = nullptr;
static void (*retro_set_audio_sample)(retro_audio_sample_t) = nullptr;
static void (*retro_set_audio_sample_batch)(retro_audio_sample_batch_t) = nullptr;
static void (*retro_set_input_poll)(retro_input_poll_t) = nullptr;
static void (*retro_set_input_state)(retro_input_state_t) = nullptr;
static void (*retro_get_system_info)(struct retro_system_info *info) = nullptr;
static void (*retro_get_system_av_info)(struct retro_system_av_info *info) = nullptr;
static void (*retro_set_controller_port_device)(unsigned port, unsigned device) = nullptr;
static bool (*retro_load_game)(const struct retro_game_info *game) = nullptr;
static void (*retro_unload_game)(void) = nullptr;
static void (*retro_reset)(void) = nullptr;
static void (*retro_run)(void) = nullptr;
static size_t (*retro_serialize_size)(void) = nullptr;
static bool (*retro_serialize)(void *data, size_t size) = nullptr;
static bool (*retro_unserialize)(const void *data, size_t size) = nullptr;

static void* core_handle = nullptr;
static bool is_game_loaded = false;
static std::string current_core_name = "Unknown Core";

// External callbacks from retro-bridge.cpp
extern "C" {
    void start_native_emulator_thread(uintptr_t retro_run_ptr, double fps);
    void stop_native_emulator_thread();
    void set_native_emulator_paused(bool paused);
    void render_to_window(const void* data, unsigned width, unsigned height, size_t pitch);
    void native_audio_init(double sample_rate);
    void native_audio_deinit();
    void native_video_deinit();
    size_t native_audio_sample_batch_cb(const int16_t* data, size_t frames);
    void native_audio_sample_cb(int16_t left, int16_t right);
    bool native_environment_cb(unsigned cmd, void *data);
    void native_input_poll_cb();
    int16_t native_input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id);
}

// Router Logic
// resolve_core is no longer needed here

bool frontend_init_and_load(const char* core_path_ptr, const char* rom_path) {
    frontend_deinit();

    std::string core_path = core_path_ptr;
    LOGI("Loading core: %s", core_path.c_str());

    core_handle = dlopen(core_path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!core_handle) {
        LOGE("Failed to load core: %s", dlerror());
        return false;
    }

    #define BIND_SYM(name) \
        name = (decltype(name))dlsym(core_handle, #name); \
        if (!name) { LOGE("Failed to find symbol %s", #name); return false; }

    BIND_SYM(retro_init);
    BIND_SYM(retro_deinit);
    BIND_SYM(retro_set_environment);
    BIND_SYM(retro_set_video_refresh);
    BIND_SYM(retro_set_audio_sample);
    BIND_SYM(retro_set_audio_sample_batch);
    BIND_SYM(retro_set_input_poll);
    BIND_SYM(retro_set_input_state);
    BIND_SYM(retro_get_system_info);
    BIND_SYM(retro_get_system_av_info);
    BIND_SYM(retro_set_controller_port_device);
    BIND_SYM(retro_load_game);
    BIND_SYM(retro_unload_game);
    BIND_SYM(retro_reset);
    BIND_SYM(retro_run);
    BIND_SYM(retro_serialize_size);
    BIND_SYM(retro_serialize);
    BIND_SYM(retro_unserialize);
    #undef BIND_SYM

    retro_set_environment(native_environment_cb);
    retro_set_video_refresh(render_to_window);
    retro_set_audio_sample(native_audio_sample_cb);
    retro_set_audio_sample_batch(native_audio_sample_batch_cb);
    retro_set_input_poll(native_input_poll_cb);
    retro_set_input_state(native_input_state_cb);

    retro_init();

    struct retro_system_info sys_info = {0};
    retro_get_system_info(&sys_info);
    if (sys_info.library_name) {
        current_core_name = sys_info.library_name;
    }

    // Load game
    struct retro_game_info game_info = {0};
    game_info.path = rom_path;
    game_info.data = nullptr;
    game_info.size = 0;
    game_info.meta = nullptr;

    std::vector<uint8_t> rom_buffer;
    if (!sys_info.need_fullpath) {
        FILE* f = fopen(rom_path, "rb");
        if (f) {
            fseek(f, 0, SEEK_END);
            size_t size = ftell(f);
            fseek(f, 0, SEEK_SET);
            rom_buffer.resize(size);
            fread(rom_buffer.data(), 1, size, f);
            fclose(f);
            game_info.data = rom_buffer.data();
            game_info.size = size;
        }
    }

    unsigned deviceType = (current_core_name.find("pcsx") != std::string::npos) ? 5 /* RETRO_DEVICE_ANALOG */ : 1 /* RETRO_DEVICE_JOYPAD */;
    retro_set_controller_port_device(0, deviceType);
    retro_set_controller_port_device(1, deviceType);

    if (retro_load_game(&game_info)) {
        is_game_loaded = true;
        struct retro_system_av_info av_info = {0};
        retro_get_system_av_info(&av_info);
        double fps = av_info.timing.fps;
        if (fps <= 0) fps = 60.0;
        
        native_audio_init(av_info.timing.sample_rate);
        
        start_native_emulator_thread(reinterpret_cast<uintptr_t>(retro_run), fps);
        return true;
    }

    LOGE("retro_load_game failed");
    return false;
}

void frontend_deinit() {
    stop_native_emulator_thread();
    native_audio_deinit();
    native_video_deinit();
    
    if (is_game_loaded && retro_unload_game) {
        retro_unload_game();
        is_game_loaded = false;
    }
    if (retro_deinit) {
        retro_deinit();
    }
    if (core_handle) {
        dlclose(core_handle);
        core_handle = nullptr;
    }
    retro_init = nullptr;
    retro_deinit = nullptr;
    retro_set_environment = nullptr;
    retro_set_video_refresh = nullptr;
    retro_set_audio_sample = nullptr;
    retro_set_audio_sample_batch = nullptr;
    retro_set_input_poll = nullptr;
    retro_set_input_state = nullptr;
    retro_get_system_info = nullptr;
    retro_get_system_av_info = nullptr;
    retro_set_controller_port_device = nullptr;
    retro_load_game = nullptr;
    retro_unload_game = nullptr;
    retro_reset = nullptr;
    retro_run = nullptr;
    retro_serialize_size = nullptr;
    retro_serialize = nullptr;
    retro_unserialize = nullptr;
}

void frontend_reset() {
    if (is_game_loaded && retro_reset) {
        retro_reset();
    }
}

static std::string get_state_path(int slot, const char* save_dir) {
    char buf[512];
    snprintf(buf, sizeof(buf), "%s/save_state_%d.st", save_dir, slot);
    return std::string(buf);
}

bool frontend_save_state(int slot, const char* save_dir) {
    if (!is_game_loaded || !retro_serialize_size || !retro_serialize) return false;
    stop_native_emulator_thread();
    
    bool success = false;
    size_t size = retro_serialize_size();
    if (size > 0) {
        std::vector<uint8_t> buffer(size);
        if (retro_serialize(buffer.data(), size)) {
            std::string path = get_state_path(slot, save_dir);
            FILE* f = fopen(path.c_str(), "wb");
            if (f) {
                fwrite(buffer.data(), 1, size, f);
                fclose(f);
                success = true;
            }
        }
    }
    
    // Restart thread (assume 60 fps fallback if we don't store it)
    // To be safe we could query av_info again.
    struct retro_system_av_info av_info = {0};
    retro_get_system_av_info(&av_info);
    start_native_emulator_thread(reinterpret_cast<uintptr_t>(retro_run), av_info.timing.fps > 0 ? av_info.timing.fps : 60.0);
    return success;
}

bool frontend_load_state(int slot, const char* save_dir) {
    if (!is_game_loaded || !retro_serialize_size || !retro_unserialize) return false;
    stop_native_emulator_thread();
    
    bool success = false;
    std::string path = get_state_path(slot, save_dir);
    FILE* f = fopen(path.c_str(), "rb");
    if (f) {
        fseek(f, 0, SEEK_END);
        size_t file_size = ftell(f);
        fseek(f, 0, SEEK_SET);
        
        size_t expected_size = retro_serialize_size();
        if (file_size == expected_size) {
            std::vector<uint8_t> buffer(file_size);
            fread(buffer.data(), 1, file_size, f);
            if (retro_unserialize(buffer.data(), file_size)) {
                success = true;
            }
        }
        fclose(f);
    }
    
    struct retro_system_av_info av_info = {0};
    retro_get_system_av_info(&av_info);
    start_native_emulator_thread(reinterpret_cast<uintptr_t>(retro_run), av_info.timing.fps > 0 ? av_info.timing.fps : 60.0);
    return success;
}

void frontend_toggle_pause() {
    static bool is_paused = false;
    is_paused = !is_paused;
    set_native_emulator_paused(is_paused);
}
