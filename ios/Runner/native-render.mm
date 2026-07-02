#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

extern "C" {
    // Expose the function to Dart FFI
    __attribute__((visibility("default"))) __attribute__((used))
    void render_to_window_ios(const uint16_t* pixels, int width, int height);
}

// Forward declaration of the swift class property or method we'll call
// In Objective-C++, we can post a notification or call a block if we want.
// But the fastest way is to have the Swift code register a callback or provide the CVPixelBuffer.
// Since we want zero-copy (or close to it) RGB565 to CGImage, we will broadcast a notification with the CGImage.
// Wait, a notification is slow. Let's just create a shared pointer to the UIImageView layer.
// Actually, CoreGraphics is thread-safe. We can create a CGImage from the raw RGB565 pointer,
// and update a global CALayer's contents.

static CALayer* global_tv_layer = nil;

extern "C" {
    __attribute__((visibility("default"))) __attribute__((used))
    void set_global_tv_layer(void* layer) {
        global_tv_layer = (__bridge CALayer*)layer;
    }
}

void render_to_window_ios(const uint16_t* pixels, int width, int height) {
    if (global_tv_layer == nil) {
        return;
    }

    // Convert RGB565 to RGBA8888 for accurate CoreGraphics rendering
    size_t numPixels = width * height;
    uint32_t* rgba = (uint32_t*)malloc(numPixels * 4);
    
    for (size_t i = 0; i < numPixels; i++) {
        uint16_t p = pixels[i];
        uint8_t r = (p >> 11) & 0x1F;
        uint8_t g = (p >> 5) & 0x3F;
        uint8_t b = p & 0x1F;
        
        // Scale to 8-bit
        r = (r << 3) | (r >> 2);
        g = (g << 2) | (g >> 4);
        b = (b << 3) | (b >> 2);
        
        // ABGR format for CoreGraphics with kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big (which is RGBA in memory)
        rgba[i] = (0xFF << 24) | (b << 16) | (g << 8) | r;
    }

    NSData *data = [NSData dataWithBytesNoCopy:rgba length:numPixels * 4 freeWhenDone:YES];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
    
    CGImageRef cgImage = CGImageCreate(
        width,
        height,
        8,
        32,
        width * 4,
        colorSpace,
        bitmapInfo,
        provider,
        NULL,
        false,
        kCGRenderingIntentDefault
    );

    if (cgImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            global_tv_layer.contents = (__bridge id)cgImage;
            global_tv_layer.magnificationFilter = kCAFilterLinear; // Use linear scaling to gracefully handle non-integer dynamic resolutions
            [CATransaction commit];
            CGImageRelease(cgImage);
        });
    }

    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
}

// --- Native Input Management ---

#include <atomic>

std::atomic<bool> ios_button_states[2][16];

extern "C" {
    __attribute__((visibility("default"))) __attribute__((used))
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

#include "native-audio.mm"
