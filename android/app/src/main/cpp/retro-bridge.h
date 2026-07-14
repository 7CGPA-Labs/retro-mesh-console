#pragma once
#include <stdint.h>
#include <stddef.h>
#include <atomic>

extern "C" {

// Video API
void miracast_video_init();
void miracast_video_deinit();
void miracast_video_push_frame(const void* data, unsigned width, unsigned height, size_t pitch, int pixel_format);

// Audio API
void miracast_audio_init(double sample_rate);
void miracast_audio_deinit();
void miracast_audio_push_batch(const int16_t* data, size_t frames);
void miracast_audio_push_silence(size_t frames);

}
