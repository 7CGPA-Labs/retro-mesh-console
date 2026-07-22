#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Frontend API
bool frontend_init_and_load(const char* core_dir, const char* rom_path);
void frontend_deinit();
void frontend_reset();
bool frontend_save_state(int slot, const char* save_dir);
bool frontend_load_state(int slot, const char* save_dir);
void frontend_toggle_pause();

#ifdef __cplusplus
}
#endif
