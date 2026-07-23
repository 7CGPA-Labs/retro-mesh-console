#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <mutex>
#include <vector>
#include <atomic>
#include <thread>
#include <condition_variable>
#include "retro-bridge.h"

static CALayer* global_tv_layer = nil;

struct VideoFrame {
    std::vector<uint8_t> pixels;
    int width = 0;
    int height = 0;
    int pixel_format = 0;
};

static VideoFrame* backBuffer = new VideoFrame();
static std::atomic<VideoFrame*> readyBuffer{nullptr};
static VideoFrame* frontBuffer = new VideoFrame();
static std::atomic<bool> tvThreadRunning{false};
static std::mutex renderMutex;
static std::condition_variable renderCv;
static std::atomic<bool> frameReady{false};
static std::atomic<float> thermalScale{1.0f};

static void RenderWorker() {
    while (tvThreadRunning.load()) {
        {
            std::unique_lock<std::mutex> lock(renderMutex);
            renderCv.wait(lock, [] { return frameReady.load() || !tvThreadRunning.load(); });
            if (!tvThreadRunning.load()) break;
            frontBuffer = readyBuffer.exchange(frontBuffer);
            frameReady = false;
        }

        if (global_tv_layer == nil || frontBuffer->width == 0) continue;

        int width = frontBuffer->width;
        int height = frontBuffer->height;
        int pixel_format = frontBuffer->pixel_format;
        size_t numPixels = width * height;
        
        // Background CPU conversion is okay if we can't do Metal easily here, 
        // but it's off the emulator thread!
        uint32_t* rgba = (uint32_t*)malloc(numPixels * 4);
        
        for (unsigned y = 0; y < height; y++) {
            // Simplified pitch assumption for now, ideally pitch is passed
            const uint8_t* rowSrc = frontBuffer->pixels.data() + (y * (width * (pixel_format == 1 ? 4 : 2)));
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
        
        NSData *nsdata = [NSData dataWithBytesNoCopy:rgba length:numPixels * 4 freeWhenDone:YES];
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)nsdata);
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
        
        CGImageRef cgImage = CGImageCreate(
            width, height, 8, 32, width * 4,
            colorSpace, bitmapInfo, provider, NULL, false, kCGRenderingIntentDefault
        );

        if (cgImage) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                global_tv_layer.contents = (__bridge id)cgImage;
                global_tv_layer.magnificationFilter = kCAFilterLinear;
                [CATransaction commit];
            });
            CGImageRelease(cgImage);
        }

        CGColorSpaceRelease(colorSpace);
        CGDataProviderRelease(provider);
    }
}

extern "C" {
    __attribute__((visibility("default"))) __attribute__((used))
    void set_global_tv_layer(void* layer) {
        global_tv_layer = (__bridge CALayer*)layer;
    }
    
    __attribute__((visibility("default"))) __attribute__((used))
    void set_thermal_scale(float scale) {
        thermalScale.store(scale, std::memory_order_relaxed);
    }
    
    bool is_tv_connected() {
        return global_tv_layer != nil;
    }

    void miracast_video_init() {}
    
    void miracast_video_deinit() {
        tvThreadRunning = false;
        renderCv.notify_all();
    }

    void miracast_video_push_frame(const void* data, unsigned width, unsigned height, size_t pitch, int pixel_format) {
        if (global_tv_layer == nil || !data || width == 0 || height == 0) {
            return;
        }
        
        if (!tvThreadRunning.load()) {
            tvThreadRunning.store(true);
            std::thread(RenderWorker).detach();
        }

        float tScale = thermalScale.load(std::memory_order_relaxed);
        if (tScale < 1.0f) {
            static int frameCounter = 0;
            frameCounter++;
            if (tScale < 0.6f && (frameCounter % 3) != 0) return; 
            else if (tScale < 0.9f && (frameCounter % 2) != 0) return; 
        }

        size_t requiredSize = pitch * height;
        if (backBuffer->pixels.size() != requiredSize) {
            backBuffer->pixels.resize(requiredSize);
        }
        backBuffer->width = width;
        backBuffer->height = height;
        backBuffer->pixel_format = pixel_format;
        std::memcpy(backBuffer->pixels.data(), data, requiredSize);

        {
            std::lock_guard<std::mutex> lock(renderMutex);
            backBuffer = readyBuffer.exchange(backBuffer);
            frameReady = true;
        }
        renderCv.notify_one();
    }
}
