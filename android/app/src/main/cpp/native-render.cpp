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
#include <cmath>

#define LOG_TAG "NativeRender"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

ANativeWindow* flutterWindow = nullptr;
ANativeWindow* tvWindow = nullptr;
std::mutex renderMutex;

// EGL and GLES state
EGLDisplay eglDisplay = EGL_NO_DISPLAY;
EGLContext eglContext = EGL_NO_CONTEXT;
EGLSurface eglSurface = EGL_NO_SURFACE;
GLuint program = 0;
GLuint textureId = 0;

int tvWidth = 256;
int tvHeight = 224;
int physicalWidth = 0;
int physicalHeight = 0;

std::vector<uint16_t> tvBuffer;

// Web Caster zero-copy bridge
std::mutex webMutex;
std::vector<uint16_t> webBuffer(1920 * 1080); // Fixed size to prevent address changes
std::atomic<int> webWidth{0};
std::atomic<int> webHeight{0};
std::atomic<bool> webStreaming{false};
std::mutex tvMutex;
std::condition_variable tvCondVar;
std::atomic<bool> tvThreadRunning{false};
std::atomic<bool> tvFrameReady{false};
std::atomic<float> thermalScale{1.0f};

// WebCaster Z-RLE variables
std::vector<uint8_t> webRleBuffer(1920 * 1080 * 2);
std::atomic<int> webRleSize{0};
std::mutex webSyncMutex;
std::condition_variable webCondVar;
bool webFrameReady = false;
std::atomic<int> activePixelFormat{2};

// Shaders
const char* vertexShaderCode =
    "attribute vec4 aPosition;\n"
    "attribute vec2 aTexCoord;\n"
    "varying vec2 vTexCoord;\n"
    "void main() {\n"
    "  gl_Position = aPosition;\n"
    "  vTexCoord = aTexCoord;\n"
    "}\n";

const char* fragmentShaderCode =
    "precision mediump float;\n"
    "varying vec2 vTexCoord;\n"
    "uniform sampler2D uTexture;\n"
    "void main() {\n"
    "  vec4 color = texture2D(uTexture, vTexCoord);\n"
    "  float scanline = sin(vTexCoord.y * 800.0) * 0.1;\n"
    "  color.rgb -= scanline;\n"
    "  gl_FragColor = color;\n"
    "}\n";

GLuint loadShader(GLenum type, const char* shaderCode) {
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

bool setupEGL() {
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

    // Set up OpenGL Program
    GLuint vertexShader = loadShader(GL_VERTEX_SHADER, vertexShaderCode);
    GLuint fragmentShader = loadShader(GL_FRAGMENT_SHADER, fragmentShaderCode);
    
    program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    glLinkProgram(program);
    
    // Set up Texture
    glGenTextures(1, &textureId);
    glBindTexture(GL_TEXTURE_2D, textureId);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    return true;
}

void destroyEGL() {
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

void TvRenderWorker() {
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
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, tvWidth, tvHeight, 0, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, tvBuffer.data());
                currentTexWidth = tvWidth;
                currentTexHeight = tvHeight;
            } else {
                glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, tvWidth, tvHeight, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, tvBuffer.data());
            }
            
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            eglSwapBuffers(eglDisplay, eglSurface);
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

extern "C" JNIEXPORT void JNICALL
Java_dev_seven_1cgpalabs_mojosnap_NativeRender_setFlutterSurface(JNIEnv* env, jclass clazz, jobject surface) {
    std::lock_guard<std::mutex> lock(renderMutex);
    if (flutterWindow) {
        ANativeWindow_release(flutterWindow);
        flutterWindow = nullptr;
    }
    if (surface != nullptr) {
        flutterWindow = ANativeWindow_fromSurface(env, surface);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_dev_seven_1cgpalabs_mojosnap_NativeRender_setTvSurface(JNIEnv* env, jclass clazz, jobject surface) {
    std::lock_guard<std::mutex> lock(renderMutex);
    if (tvWindow) {
        ANativeWindow_release(tvWindow);
        tvWindow = nullptr;
    }
    if (surface != nullptr) {
        tvWindow = ANativeWindow_fromSurface(env, surface);
    }
}

extern "C" bool native_environment_cb(unsigned cmd, void *data) {
    if (cmd == 10) { // RETRO_ENVIRONMENT_SET_PIXEL_FORMAT
        if (data) {
            activePixelFormat.store(*static_cast<int*>(data));
            return true;
        }
    } else if (cmd == 9 || cmd == 31) { // GET_SYSTEM_DIRECTORY or GET_SAVE_DIRECTORY
        if (data) {
            const char** dir = static_cast<const char**>(data);
            *dir = "/sdcard/RetroMesh";
            return true;
        }
    } else if (cmd == 17) { // GET_VARIABLE_UPDATE
        if (data) {
            *static_cast<bool*>(data) = false;
            return true;
        }
    } else if (cmd == 15) { // GET_VARIABLE
        return false;
    } else if (cmd == 16) { // SET_VARIABLES
        return true;
    }
    return false;
}

extern "C" void native_input_poll_cb() {
}

extern "C" void render_to_window(const void* data, unsigned width, unsigned height, size_t pitch) {
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
        
        int fmt = activePixelFormat.load();
        uint16_t* dst = tvBuffer.data();
        
        for (unsigned y = 0; y < height; y++) {
            const uint8_t* rowSrc = reinterpret_cast<const uint8_t*>(pixels) + (y * pitch);
            uint16_t* rowDst = dst + (y * width);
            
            if (fmt == 1) { // XRGB8888
                const uint32_t* src32 = reinterpret_cast<const uint32_t*>(rowSrc);
                for (unsigned x = 0; x < width; x++) {
                    uint32_t color = src32[x];
                    int r = (color >> 16) & 0xFF;
                    int g = (color >> 8) & 0xFF;
                    int b = color & 0xFF;
                    rowDst[x] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
                }
            } else if (fmt == 0) { // 0RGB1555
                const uint16_t* src16 = reinterpret_cast<const uint16_t*>(rowSrc);
                for (unsigned x = 0; x < width; x++) {
                    uint16_t color = src16[x];
                    int r = (color >> 10) & 0x1F;
                    int g = (color >> 5) & 0x1F;
                    int b = color & 0x1F;
                    rowDst[x] = (r << 11) | ((g << 1) << 5) | b;
                }
            } else { // RGB565 and HW_GL_RGBA (assuming handled similarly if needed)
                memcpy(rowDst, rowSrc, width * 2);
            }
        }
        
        tvFrameReady = true;
        tvCondVar.notify_one();
    }

    if (webStreaming.load()) {
        std::lock_guard<std::mutex> wLock(webMutex);
        webWidth.store(width);
        webHeight.store(height);
        size_t totalPixels = width * height;
        if (totalPixels <= 1920 * 1080) {
            uint16_t* dst = webBuffer.data();
            int fmt = activePixelFormat.load();
            
            for (unsigned y = 0; y < height; y++) {
                const uint8_t* rowSrc = reinterpret_cast<const uint8_t*>(pixels) + (y * pitch);
                uint16_t* rowDst = dst + (y * width);
                
                if (fmt == 1) { // XRGB8888
                    const uint32_t* src32 = reinterpret_cast<const uint32_t*>(rowSrc);
                    for (unsigned x = 0; x < width; x++) {
                        uint32_t color = src32[x];
                        int r = (color >> 16) & 0xFF;
                        int g = (color >> 8) & 0xFF;
                        int b = color & 0xFF;
                        rowDst[x] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
                    }
                } else if (fmt == 3) { // HW_GL_RGBA
                    const uint8_t* src8 = reinterpret_cast<const uint8_t*>(rowSrc);
                    for (unsigned x = 0; x < width; x++) {
                        int r = src8[x * 4 + 0];
                        int g = src8[x * 4 + 1];
                        int b = src8[x * 4 + 2];
                        rowDst[x] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
                    }
                } else if (fmt == 0) { // 0RGB1555
                    const uint16_t* src16 = reinterpret_cast<const uint16_t*>(rowSrc);
                    for (unsigned x = 0; x < width; x++) {
                        uint16_t color = src16[x];
                        int r = (color >> 10) & 0x1F;
                        int g = (color >> 5) & 0x1F;
                        int b = color & 0x1F;
                        rowDst[x] = (r << 11) | ((g << 1) << 5) | b;
                    }
                } else { // RGB565
                    memcpy(rowDst, rowSrc, width * 2);
                }
            }
            
            // Z-RLE Compression
            int outIdx = 0;
            int i = 0;
            uint8_t* out = webRleBuffer.data();
            uint8_t* in = reinterpret_cast<uint8_t*>(dst);
            int byteCount = totalPixels * 2;
            
            while (i < byteCount) {
                int runLength = 1;
                int maxRun = 129;
                while (runLength < maxRun && i + (runLength * 2) < byteCount) {
                    int nextIdx = i + (runLength * 2);
                    if (in[nextIdx] == in[i] && in[nextIdx+1] == in[i+1]) {
                        runLength++;
                    } else {
                        break;
                    }
                }
                
                if (runLength >= 2) {
                    out[outIdx++] = (runLength - 2) + 128;
                    out[outIdx++] = in[i];
                    out[outIdx++] = in[i+1];
                    i += runLength * 2;
                } else {
                    int rawLength = 1;
                    int maxRaw = 128;
                    while (rawLength < maxRaw && i + (rawLength * 2) < byteCount) {
                        int currIdx = i + (rawLength * 2);
                        int nextIdx = currIdx + 2;
                        if (nextIdx < byteCount && in[currIdx] == in[nextIdx] && in[currIdx+1] == in[nextIdx+1]) {
                            break;
                        }
                        rawLength++;
                    }
                    out[outIdx++] = rawLength - 1;
                    memcpy(out + outIdx, in + i, rawLength * 2);
                    outIdx += rawLength * 2;
                    i += rawLength * 2;
                }
            }
            webRleSize.store(outIdx);
        }
        
        {
            std::lock_guard<std::mutex> syncLock(webSyncMutex);
            webFrameReady = true;
        }
        webCondVar.notify_all();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_dev_seven_1cgpalabs_mojosnap_ThermalManager_setThermalScale(JNIEnv* env, jobject thiz, jfloat scale) {
    thermalScale.store(scale);
}

std::atomic<bool> button_states[2][16];
std::atomic<int16_t> analog_states[2][2][2]; // [port][index][id (0=X, 1=Y)]
std::atomic<int16_t> pointer_x{0};
std::atomic<int16_t> pointer_y{0};
std::atomic<bool> pointer_pressed{false};

extern "C" int16_t native_input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (device == 1) { // RETRO_DEVICE_JOYPAD
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
            case 12: customId = 14; break; // L2
            case 13: customId = 15; break; // R2
            case 14: customId = 16; break; // L3
            case 15: customId = 17; break; // R3
        }
        if (customId == -1 || port > 1) return 0;
        return button_states[port][customId].load() ? 1 : 0;
    } 
    else if (device == 5) { // RETRO_DEVICE_ANALOG
        if (port > 1 || index > 1 || id > 1) return 0;
        return analog_states[port][index][id].load();
    }
    else if (device == 6) { // RETRO_DEVICE_POINTER
        if (port > 0) return 0; // Pointer usually only on port 0
        switch(id) {
            case 0: return pointer_x.load(); // RETRO_DEVICE_ID_POINTER_X
            case 1: return pointer_y.load(); // RETRO_DEVICE_ID_POINTER_Y
            case 2: return pointer_pressed.load() ? 1 : 0; // RETRO_DEVICE_ID_POINTER_PRESSED
        }
    }
    return 0;
}

extern "C" void set_player1_button(int customButtonId, bool pressed) {
    if (customButtonId >= 0 && customButtonId < 16) {
        button_states[0][customButtonId].store(pressed);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_dev_seven_1cgpalabs_mojosnap_NetworkManager_updatePlayer2Button(JNIEnv* env, jobject thiz, jint buttonId, jboolean pressed) {
    if (buttonId >= 0 && buttonId < 16) {
        button_states[1][buttonId].store(pressed);
    }
}

extern "C" void set_player1_analog(int index, int id, int16_t value) {
    if (index >= 0 && index < 2 && id >= 0 && id < 2) {
        analog_states[0][index][id].store(value);
    }
}

extern "C" void set_player1_pointer(int16_t x, int16_t y, bool pressed) {
    pointer_x.store(x);
    pointer_y.store(y);
    pointer_pressed.store(pressed);
}

// --- WebCaster JNI ---

extern "C" JNIEXPORT void JNICALL
Java_dev_seven_1cgpalabs_mojosnap_WebCaster_setWebStreaming(JNIEnv* env, jobject thiz, jboolean streaming) {
    webStreaming.store(streaming);
}

extern "C" JNIEXPORT jobject JNICALL
Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getFrameBuffer(JNIEnv* env, jobject thiz) {
    return env->NewDirectByteBuffer(webBuffer.data(), webBuffer.size() * sizeof(uint16_t));
}

extern "C" JNIEXPORT jintArray JNICALL
Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getFrameDimensions(JNIEnv* env, jobject thiz) {
    std::lock_guard<std::mutex> wLock(webMutex);
    jintArray result = env->NewIntArray(2);
    jint dims[2];
    dims[0] = webWidth.load();
    dims[1] = webHeight.load();
    env->SetIntArrayRegion(result, 0, 2, dims);
    return result;
}

extern "C" JNIEXPORT jobject JNICALL
Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getRleBuffer(JNIEnv* env, jobject thiz) {
    return env->NewDirectByteBuffer(webRleBuffer.data(), webRleBuffer.size());
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getRleSize(JNIEnv* env, jobject thiz) {
    return webRleSize.load();
}

extern "C" JNIEXPORT void JNICALL
Java_dev_seven_1cgpalabs_mojosnap_WebCaster_waitForNextFrame(JNIEnv* env, jobject thiz) {
    std::unique_lock<std::mutex> lock(webSyncMutex);
    webCondVar.wait_for(lock, std::chrono::milliseconds(32), []{ return webFrameReady; });
    webFrameReady = false;
}

extern "C" JNIEXPORT void JNICALL
Java_dev_seven_1cgpalabs_mojosnap_WebCaster_setPixelFormat(JNIEnv* env, jobject thiz, jint fmt) {
    activePixelFormat.store(fmt);
}

extern "C" void set_pixel_format(int fmt) {
    activePixelFormat.store(fmt);
}

// Dummy HW rendering functions to satisfy Dart FFI lookups
extern "C" bool hw_render_init(int width, int height) { return false; }
extern "C" void hw_render_extract_frame() {}
extern "C" uintptr_t hw_get_current_framebuffer() { return 0; }
extern "C" void* hw_get_proc_address(const char* sym) { return nullptr; }

// Global audio buffer for WebCaster
std::mutex webAudioMutex;
std::vector<int16_t> webAudioBuffer;
std::vector<int16_t> fixedWebAudio(44100 * 2);

extern "C" void web_audio_batch_cb(const int16_t* data, intptr_t frames) {
    if (!webStreaming.load()) return;
    std::lock_guard<std::mutex> lock(webAudioMutex);
    size_t samples = frames * 2;
    if (webAudioBuffer.size() > 44100 * 2) {
        webAudioBuffer.clear();
    }
    webAudioBuffer.insert(webAudioBuffer.end(), data, data + samples);
}

extern "C" JNIEXPORT jobject JNICALL
Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getAudioBuffer(JNIEnv* env, jobject thiz) {
    return env->NewDirectByteBuffer(fixedWebAudio.data(), fixedWebAudio.size() * sizeof(int16_t));
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_seven_1cgpalabs_mojosnap_WebCaster_getAudioSize(JNIEnv* env, jobject thiz) {
    std::lock_guard<std::mutex> lock(webAudioMutex);
    return (jint)(webAudioBuffer.size() * sizeof(int16_t));
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_seven_1cgpalabs_mojosnap_WebCaster_consumeAudioBuffer(JNIEnv* env, jobject thiz) {
    std::lock_guard<std::mutex> lock(webAudioMutex);
    size_t copySize = std::min(webAudioBuffer.size(), fixedWebAudio.size());
    if (copySize > 0) {
        memcpy(fixedWebAudio.data(), webAudioBuffer.data(), copySize * sizeof(int16_t));
        webAudioBuffer.erase(webAudioBuffer.begin(), webAudioBuffer.begin() + copySize);
    }
    return (jint)(copySize * sizeof(int16_t));
}

// --- Native Emulator Thread ---

typedef void (*retro_run_t)();
static std::atomic<bool> emulator_running{false};
static std::thread emulator_thread;

extern "C" void start_native_emulator_thread(uintptr_t retro_run_ptr) {
    if (emulator_running.load()) return;
    emulator_running.store(true);
    retro_run_t run_func = reinterpret_cast<retro_run_t>(retro_run_ptr);
    
    emulator_thread = std::thread([run_func]() {
        while (emulator_running.load()) {
            run_func();
        }
    });
    // Removed detach() to allow joining on stop
}

extern "C" void stop_native_emulator_thread() {
    emulator_running.store(false);
    if (emulator_thread.joinable()) {
        emulator_thread.join();
    }
}
