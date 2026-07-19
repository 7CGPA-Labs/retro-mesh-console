#import <AudioToolbox/AudioToolbox.h>
#include <mutex>
#include <vector>
#include <string.h>
#include <stdint.h>
#include "retro-bridge.h"

// Global AudioUnit device and config
static AudioComponentInstance g_audioUnit = nullptr;
static bool g_audio_initialized = false;

// Ring buffer for audio samples
static std::vector<int16_t> g_audio_buffer;
static std::mutex g_audio_mutex;
static size_t g_read_index = 0;
static size_t g_write_index = 0;

static OSStatus render_callback(void *inRefCon,
                                AudioUnitRenderActionFlags *ioActionFlags,
                                const AudioTimeStamp *inTimeStamp,
                                UInt32 inBusNumber,
                                UInt32 inNumberFrames,
                                AudioBufferList *ioData) {
    std::lock_guard<std::mutex> lock(g_audio_mutex);
    int16_t* out = static_cast<int16_t*>(ioData->mBuffers[0].mData);
    size_t samples_requested = inNumberFrames * 2; // Stereo
    
    size_t samples_available = g_write_index >= g_read_index ? 
                               (g_write_index - g_read_index) : 
                               (g_audio_buffer.size() - g_read_index + g_write_index);
                               
    if (samples_available < samples_requested) {
        memset(out, 0, samples_requested * sizeof(int16_t));
        return noErr;
    }
    
    for (size_t i = 0; i < samples_requested; ++i) {
        out[i] = g_audio_buffer[g_read_index];
        g_read_index = (g_read_index + 1) % g_audio_buffer.size();
    }
    
    return noErr;
}

extern "C" {

void miracast_audio_init(double sample_rate) {
    if (g_audio_initialized) return;

    double actual_sample_rate = (sample_rate > 0) ? sample_rate : 44100.0;
    g_audio_buffer.resize(static_cast<size_t>(actual_sample_rate) * 2 * 2);

    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;

    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) return;

    if (AudioComponentInstanceNew(comp, &g_audioUnit) != noErr) return;

    AURenderCallbackStruct input;
    input.inputProc = render_callback;
    input.inputProcRefCon = nullptr;

    if (AudioUnitSetProperty(g_audioUnit, 
                             kAudioUnitProperty_SetRenderCallback, 
                             kAudioUnitScope_Input,
                             0, 
                             &input, 
                             sizeof(input)) != noErr) {
        AudioComponentInstanceDispose(g_audioUnit);
        g_audioUnit = nullptr;
        return;
    }

    AudioStreamBasicDescription audioFormat;
    audioFormat.mSampleRate = actual_sample_rate;
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mChannelsPerFrame = 2;
    audioFormat.mBitsPerChannel = 16;
    audioFormat.mBytesPerPacket = 4;
    audioFormat.mBytesPerFrame = 4;

    if (AudioUnitSetProperty(g_audioUnit, 
                             kAudioUnitProperty_StreamFormat, 
                             kAudioUnitScope_Input, 
                             0, 
                             &audioFormat, 
                             sizeof(audioFormat)) != noErr) {
        AudioComponentInstanceDispose(g_audioUnit);
        g_audioUnit = nullptr;
        return;
    }

    if (AudioUnitInitialize(g_audioUnit) != noErr) {
        AudioComponentInstanceDispose(g_audioUnit);
        g_audioUnit = nullptr;
        return;
    }
    
    if (AudioOutputUnitStart(g_audioUnit) != noErr) {
        AudioUnitUninitialize(g_audioUnit);
        AudioComponentInstanceDispose(g_audioUnit);
        g_audioUnit = nullptr;
        return;
    }

    g_audio_initialized = true;
}

void miracast_audio_deinit() {
    if (!g_audio_initialized) return;
    
    if (g_audioUnit) {
        AudioOutputUnitStop(g_audioUnit);
        AudioUnitUninitialize(g_audioUnit);
        AudioComponentInstanceDispose(g_audioUnit);
        g_audioUnit = nullptr;
    }
    
    g_audio_initialized = false;
    g_read_index = 0;
    g_write_index = 0;
}

void miracast_audio_push_batch(const int16_t* data, size_t frames) {
    if (!g_audio_initialized || !is_tv_connected()) return;
    
    std::lock_guard<std::mutex> lock(g_audio_mutex);
    size_t samples_to_write = frames * 2;
    
    for (size_t i = 0; i < samples_to_write; ++i) {
        int32_t sample = (int32_t)data[i] * 4; // Apply gain
        if (sample > 32767) sample = 32767;
        if (sample < -32768) sample = -32768;
        
        g_audio_buffer[g_write_index] = (int16_t)sample;
        g_write_index = (g_write_index + 1) % g_audio_buffer.size();
        
        if (g_write_index == g_read_index) {
            g_read_index = (g_read_index + 1) % g_audio_buffer.size();
        }
    }
}

void miracast_audio_push_silence(size_t frames) {
    // CoreAudio handles underruns by playing silence, so we just don't push samples
}

}
