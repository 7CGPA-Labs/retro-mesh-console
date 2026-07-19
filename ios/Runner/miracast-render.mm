#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <mutex>
#include <vector>
#include <atomic>
#include "retro-bridge.h"

static CALayer* global_tv_layer = nil;

extern "C" {
    __attribute__((visibility("default"))) __attribute__((used))
    void set_global_tv_layer(void* layer) {
        global_tv_layer = (__bridge CALayer*)layer;
    }
    
    bool is_tv_connected() {
        return global_tv_layer != nil;
    }

    void miracast_video_init() {}
    void miracast_video_deinit() {}

    void miracast_video_push_frame(const void* data, unsigned width, unsigned height, size_t pitch, int pixel_format) {
        if (global_tv_layer == nil || !data) {
            return;
        }

        const uint8_t* pixels = reinterpret_cast<const uint8_t*>(data);
        uint32_t* rgba = (uint32_t*)malloc(width * height * 4);
        
        for (unsigned y = 0; y < height; y++) {
            const uint8_t* rowSrc = pixels + (y * pitch);
            uint32_t* rowDst = rgba + (y * width);
            
            if (pixel_format == 1) { // XRGB8888
                const uint32_t* src32 = reinterpret_cast<const uint32_t*>(rowSrc);
                for (unsigned x = 0; x < width; x++) {
                    uint32_t color = src32[x];
                    uint32_t r = (color >> 16) & 0xFF;
                    uint32_t g = (color >> 8) & 0xFF;
                    uint32_t b = color & 0xFF;
                    rowDst[x] = (0xFFu << 24) | (b << 16) | (g << 8) | r;
                }
            } else if (pixel_format == 0) { // 0RGB1555
                const uint16_t* src16 = reinterpret_cast<const uint16_t*>(rowSrc);
                for (unsigned x = 0; x < width; x++) {
                    uint16_t color = src16[x];
                    uint32_t r = ((color >> 10) & 0x1F) << 3;
                    uint32_t g = ((color >> 5) & 0x1F) << 3;
                    uint32_t b = (color & 0x1F) << 3;
                    rowDst[x] = (0xFFu << 24) | (b << 16) | (g << 8) | r;
                }
            } else { // RGB565
                const uint16_t* src16 = reinterpret_cast<const uint16_t*>(rowSrc);
                for (unsigned x = 0; x < width; x++) {
                    uint16_t color = src16[x];
                    uint32_t r = ((color >> 11) & 0x1F) << 3;
                    uint32_t g = ((color >> 5) & 0x3F) << 2;
                    uint32_t b = (color & 0x1F) << 3;
                    rowDst[x] = (0xFFu << 24) | (b << 16) | (g << 8) | r;
                }
            }
        }
        
        size_t numPixels = width * height;

        NSData *nsdata = [NSData dataWithBytesNoCopy:rgba length:numPixels * 4 freeWhenDone:YES];
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)nsdata);
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
        
        CGImageRef cgImage = CGImageCreate(
            width, height, 8, 32, width * 4,
            colorSpace, bitmapInfo, provider, NULL, false, kCGRenderingIntentDefault
        );

        if (cgImage) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                global_tv_layer.contents = (__bridge id)cgImage;
                global_tv_layer.magnificationFilter = kCAFilterLinear;
                [CATransaction commit];
                CGImageRelease(cgImage);
            });
        }

        CGColorSpaceRelease(colorSpace);
        CGDataProviderRelease(provider);
    }
}
