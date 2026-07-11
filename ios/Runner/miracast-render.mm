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

    void miracast_video_init() {}
    void miracast_video_deinit() {}

    void miracast_video_push_frame(const void* data, unsigned width, unsigned height, size_t pitch, int pixel_format) {
        if (global_tv_layer == nil || !data) {
            return;
        }

        const uint16_t* pixels = reinterpret_cast<const uint16_t*>(data);
        size_t numPixels = width * height;
        uint32_t* rgba = (uint32_t*)malloc(numPixels * 4);
        
        for (size_t i = 0; i < numPixels; i++) {
            uint16_t p = pixels[i];
            uint8_t r = (p >> 11) & 0x1F;
            uint8_t g = (p >> 5) & 0x3F;
            uint8_t b = p & 0x1F;
            
            r = (r << 3) | (r >> 2);
            g = (g << 2) | (g >> 4);
            b = (b << 3) | (b >> 2);
            
            rgba[i] = (0xFF << 24) | (b << 16) | (g << 8) | r;
        }

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
