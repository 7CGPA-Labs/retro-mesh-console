#include <jni.h>
#include <android/native_window_jni.h>
#include <android/native_window.h>
#include <android/log.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <cstring>
#include <mutex>
#include <thread>
#include <condition_variable>
#include <vector>
#include <atomic>
#include "retro-bridge.h"

#define LOG_TAG "MiracastRender"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static ANativeWindow* flutterWindow = nullptr;
static ANativeWindow* tvWindow = nullptr;
static std::mutex renderMutex;

// EGL and GLES state
static EGLDisplay eglDisplay = EGL_NO_DISPLAY;
static EGLContext eglContext = EGL_NO_CONTEXT;
static EGLSurface eglSurface = EGL_NO_SURFACE;
static GLuint program = 0;
static GLuint textureId = 0;

static int tvWidth = 256;
static int tvHeight = 224;
static int physicalWidth = 0;
static int physicalHeight = 0;

static std::vector<uint32_t> tvBuffer;
static std::mutex tvMutex;
static std::condition_variable tvCondVar;
static std::atomic<bool> tvThreadRunning{false};
static std::atomic<bool> tvFrameReady{false};
static std::atomic<float> thermalScale{1.0f};

// Shaders
static const char* vertexShaderCode =
    "attribute vec4 aPosition;\n"
    "attribute vec2 aTexCoord;\n"
    "varying vec2 vTexCoord;\n"
    "void main() {\n"
    "  gl_Position = aPosition;\n"
    "  vTexCoord = aTexCoord;\n"
    "}\n";

static const char* fragmentShaderCode =
    "precision mediump float;\n"
    "varying vec2 vTexCoord;\n"
    "uniform sampler2D uTexture;\n"
    "void main() {\n"
    "  gl_FragColor = texture2D(uTexture, vTexCoord);\n"
    "}\n";

static GLuint loadShader(GLenum type, const char* shaderCode) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &shaderCode, nullptr);
    glCompileShader(shader);
    GLint compiled;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
        GLint infoLen = 0;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infoLen);
        if (infoLen > 1) {
            char* infoLog = new char[infoLen];
            glGetShaderInfoLog(shader, infoLen, nullptr, infoLog);
            LOGE("Error compiling shader:\n%s", infoLog);
            delete[] infoLog;
        }
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

static bool setupEGL() {
    if (!tvWindow) return false;

    eglDisplay = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (eglDisplay == EGL_NO_DISPLAY) {
        return false;
    }

    if (!eglInitialize(eglDisplay, nullptr, nullptr)) {
        return false;
    }

    const EGLint attribs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_BLUE_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_RED_SIZE, 8,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };

    EGLConfig config;
    EGLint numConfigs;
    if (!eglChooseConfig(eglDisplay, attribs, &config, 1, &numConfigs) || numConfigs <= 0) {
        return false;
    }

    EGLint format;
    eglGetConfigAttrib(eglDisplay, config, EGL_NATIVE_VISUAL_ID, &format);
    ANativeWindow_setBuffersGeometry(tvWindow, 0, 0, format);

    eglSurface = eglCreateWindowSurface(eglDisplay, config, tvWindow, nullptr);
    if (eglSurface == EGL_NO_SURFACE) {
        return false;
    }

    const EGLint contextAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };
    eglContext = eglCreateContext(eglDisplay, config, EGL_NO_CONTEXT, contextAttribs);
    if (eglContext == EGL_NO_CONTEXT) {
        return false;
    }

    if (!eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
        return false;
    }

    GLuint vertexShader = loadShader(GL_VERTEX_SHADER, vertexShaderCode);
    GLuint fragmentShader = loadShader(GL_FRAGMENT_SHADER, fragmentShaderCode);
    
    program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    glLinkProgram(program);
    
    glGenTextures(1, &textureId);
    glBindTexture(GL_TEXTURE_2D, textureId);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    return true;
}

static void destroyEGL() {
    if (eglDisplay != EGL_NO_DISPLAY) {
        eglMakeCurrent(eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (eglContext != EGL_NO_CONTEXT) {
            eglDestroyContext(eglDisplay, eglContext);
        }
        if (eglSurface != EGL_NO_SURFACE) {
            eglDestroySurface(eglDisplay, eglSurface);
        }
        eglTerminate(eglDisplay);
    }
    eglDisplay = EGL_NO_DISPLAY;
    eglContext = EGL_NO_CONTEXT;
    eglSurface = EGL_NO_SURFACE;
}

static void TvRenderWorker() {
    bool eglReady = false;
    int currentTexWidth = 0;
    int currentTexHeight = 0;

    while (tvThreadRunning) {
        std::unique_lock<std::mutex> lock(tvMutex);
        tvCondVar.wait(lock, [] { return tvFrameReady.load() || !tvThreadRunning.load(); });
        
        if (!tvThreadRunning) break;
        
        if (tvWindow && !eglReady) {
            eglReady = setupEGL();
        }

        if (eglReady && tvWindow) {
            physicalWidth = ANativeWindow_getWidth(tvWindow);
            physicalHeight = ANativeWindow_getHeight(tvWindow);
            
            float coreAspect = (float)tvWidth / (float)tvHeight;
            float physAspect = (float)physicalWidth / (float)physicalHeight;
            
            int viewWidth, viewHeight;
            int viewX, viewY;
            
            if (physAspect > coreAspect) {
                viewHeight = physicalHeight;
                viewWidth = (int)(physicalHeight * coreAspect);
                viewX = (physicalWidth - viewWidth) / 2;
                viewY = 0;
            } else {
                viewWidth = physicalWidth;
                viewHeight = (int)(physicalWidth / coreAspect);
                viewX = 0;
                viewY = (physicalHeight - viewHeight) / 2;
            }

            float currentScale = thermalScale.load();
            if (currentScale < 1.0f) {
                viewWidth = (int)(viewWidth * currentScale);
                viewHeight = (int)(viewHeight * currentScale);
                viewX = (physicalWidth - viewWidth) / 2;
                viewY = (physicalHeight - viewHeight) / 2;
            }
            
            glViewport(viewX, viewY, viewWidth, viewHeight);
            glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);

            glUseProgram(program);
            
            GLfloat vertices[] = {
                -1.0f,  1.0f, 0.0f,
                -1.0f, -1.0f, 0.0f,
                 1.0f,  1.0f, 0.0f,
                 1.0f, -1.0f, 0.0f
            };
            GLfloat texCoords[] = {
                0.0f, 0.0f,
                0.0f, 1.0f,
                1.0f, 0.0f,
                1.0f, 1.0f
            };
            
            GLuint posHandle = glGetAttribLocation(program, "aPosition");
            GLuint texHandle = glGetAttribLocation(program, "aTexCoord");
            
            glEnableVertexAttribArray(posHandle);
            glVertexAttribPointer(posHandle, 3, GL_FLOAT, GL_FALSE, 0, vertices);
            
            glEnableVertexAttribArray(texHandle);
            glVertexAttribPointer(texHandle, 2, GL_FLOAT, GL_FALSE, 0, texCoords);
            
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, textureId);
            
            if (currentTexWidth != tvWidth || currentTexHeight != tvHeight) {
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, tvWidth, tvHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, tvBuffer.data());
                currentTexWidth = tvWidth;
                currentTexHeight = tvHeight;
            } else {
                glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, tvWidth, tvHeight, GL_RGBA, GL_UNSIGNED_BYTE, tvBuffer.data());
            }
            
            lock.unlock();
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            eglSwapBuffers(eglDisplay, eglSurface);
            lock.lock();
        } else if (eglReady && !tvWindow) {
            destroyEGL();
            eglReady = false;
        }

        tvFrameReady = false;
    }
    
    if (eglReady) {
        destroyEGL();
    }
}

extern "C" {

void miracast_video_init() {
    // Initialization handled dynamically when frames arrive
}

void miracast_video_deinit() {
    tvThreadRunning = false;
    tvCondVar.notify_all();
}

void miracast_video_push_frame(const void* data, unsigned width, unsigned height, size_t pitch, int pixel_format) {
    if (!data) return;
    const uint16_t* pixels = reinterpret_cast<const uint16_t*>(data);
    std::lock_guard<std::mutex> lock(renderMutex);
    
    if (!tvThreadRunning) {
        tvThreadRunning = true;
        std::thread(TvRenderWorker).detach();
    }
    
    if (tvWindow) {
        std::lock_guard<std::mutex> tvLock(tvMutex);
        tvWidth = width;
        tvHeight = height;
        size_t totalPixels = width * height;
        if (tvBuffer.size() != totalPixels) {
            tvBuffer.resize(totalPixels);
        }
        
        uint32_t* dst = tvBuffer.data();
        
        for (unsigned y = 0; y < height; y++) {
            const uint8_t* rowSrc = reinterpret_cast<const uint8_t*>(pixels) + (y * pitch);
            uint32_t* rowDst = dst + (y * width);
            
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
        
        tvFrameReady = true;
        tvCondVar.notify_one();
    }
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_NativeRender_setFlutterSurface(JNIEnv* env, jclass clazz, jobject surface) {
    std::lock_guard<std::mutex> lock(renderMutex);
    if (flutterWindow) {
        ANativeWindow_release(flutterWindow);
        flutterWindow = nullptr;
    }
    if (surface != nullptr) {
        flutterWindow = ANativeWindow_fromSurface(env, surface);
    }
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_NativeRender_setTvSurface(JNIEnv* env, jclass clazz, jobject surface) {
    std::lock_guard<std::mutex> lock(renderMutex);
    
    if (tvWindow) {
        ANativeWindow_release(tvWindow);
        tvWindow = nullptr;
    }
    
    if (surface) {
        tvWindow = ANativeWindow_fromSurface(env, surface);
    }
}

bool is_tv_connected() {
    return tvWindow != nullptr;
}

JNIEXPORT void JNICALL Java_dev_seven_1cgpalabs_mojosnap_ThermalManager_setThermalScale(JNIEnv* env, jobject thiz, jfloat scale) {
    thermalScale.store(scale);
}

}
