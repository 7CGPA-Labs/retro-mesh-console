// ignore_for_file: camel_case_types, non_constant_identifier_names, constant_identifier_names
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// --- Libretro Constants ---
const int RETRO_DEVICE_JOYPAD = 1;
const int RETRO_DEVICE_ID_JOYPAD_B = 0;
const int RETRO_DEVICE_ID_JOYPAD_Y = 1;
const int RETRO_DEVICE_ID_JOYPAD_SELECT = 2;
const int RETRO_DEVICE_ID_JOYPAD_START = 3;
const int RETRO_DEVICE_ID_JOYPAD_UP = 4;
const int RETRO_DEVICE_ID_JOYPAD_DOWN = 5;
const int RETRO_DEVICE_ID_JOYPAD_LEFT = 6;
const int RETRO_DEVICE_ID_JOYPAD_RIGHT = 7;
const int RETRO_DEVICE_ID_JOYPAD_A = 8;
const int RETRO_DEVICE_ID_JOYPAD_X = 9;
const int RETRO_DEVICE_ID_JOYPAD_L = 10;
const int RETRO_DEVICE_ID_JOYPAD_R = 11;
const int RETRO_DEVICE_ID_JOYPAD_L2 = 12;
const int RETRO_DEVICE_ID_JOYPAD_R2 = 13;

// --- Libretro C Structs mapped to FFI ---

final class retro_game_info extends Struct {
  external Pointer<Utf8> path;
  external Pointer<Void> data;
  @IntPtr()
  external int size;
  external Pointer<Utf8> meta;
}

final class retro_system_info extends Struct {
  external Pointer<Utf8> library_name;
  external Pointer<Utf8> library_version;
  external Pointer<Utf8> valid_extensions;
  @Bool()
  external bool need_fullpath;
  @Bool()
  external bool block_extract;
}

// --- FFI Callback Type Definitions ---

typedef retro_environment_t = Bool Function(Uint32 cmd, Pointer<Void> data);
typedef retro_video_refresh_t = Void Function(Pointer<Void> data, Uint32 width, Uint32 height, IntPtr pitch);
typedef retro_audio_sample_t = Void Function(Int16 left, Int16 right);
typedef retro_audio_sample_batch_t = IntPtr Function(Pointer<Int16> data, IntPtr frames);
typedef retro_input_poll_t = Void Function();
typedef retro_input_state_t = Int16 Function(Uint32 port, Uint32 device, Uint32 index, Uint32 id);

// --- Top-Level Callback Functions for FFI registration ---

bool _environmentCallback(int cmd, Pointer<Void> data) {
  return LibretroEngine.activeInstance?._handleEnvironment(cmd, data) ?? false;
}

void _videoRefreshCallback(Pointer<Void> data, int width, int height, int pitch) {
  LibretroEngine.activeInstance?._handleVideoRefresh(data, width, height, pitch);
}

void _audioSampleCallback(int left, int right) {
  LibretroEngine.activeInstance?._handleAudioSample(left, right);
}

int _audioSampleBatchCallback(Pointer<Int16> data, int frames) {
  return LibretroEngine.activeInstance?._handleAudioSampleBatch(data, frames) ?? 0;
}

void _inputPollCallback() {
  LibretroEngine.activeInstance?._handleInputPoll();
}

int _inputStateCallback(int port, int device, int index, int id) {
  return LibretroEngine.activeInstance?._handleInputState(port, device, index, id) ?? 0;
}

// --- Main Engine Wrapper ---

class LibretroEngine {
  static LibretroEngine? activeInstance;
  
  static const MethodChannel _audioChannel = MethodChannel('com.retromesh.console/audio');

  // Emulation State Notifiers
  // For local UI rendering
  final ValueNotifier<ui.Image?> currentFrameNotifier = ValueNotifier<ui.Image?>(null);
  // For native dual-screen projection
  final ValueNotifier<Uint8List?> rawFrameNotifier = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<String> logNotifier = ValueNotifier<String>('Engine Initialized');

  // Input states for Port 1 (P1) and Port 2 (P2)
  // Maps: Button ID (1..12) -> pressed (bool)
  final Map<int, bool> p1ButtonStates = {};
  final Map<int, bool> p2ButtonStates = {};

  // Libretro Native Symbols
  DynamicLibrary? _lib;
  bool isMockMode = false;
  bool _isCoreInitialized = false;
  bool _isGameLoaded = false;
  Timer? _gameLoopTimer;
  bool isPaused = false;

  late void Function(Pointer<NativeFunction<retro_environment_t>>) _retroSetEnvironment;
  late void Function(Pointer<NativeFunction<retro_video_refresh_t>>) _retroSetVideoRefresh;
  late void Function(Pointer<NativeFunction<retro_audio_sample_t>>) _retroSetAudioSample;
  late void Function(Pointer<NativeFunction<retro_audio_sample_batch_t>>) _retroSetAudioSampleBatch;
  late void Function(Pointer<NativeFunction<retro_input_poll_t>>) _retroSetInputPoll;
  late void Function(Pointer<NativeFunction<retro_input_state_t>>) _retroSetInputState;

  late void Function() _retroInit;
  late void Function() _retroDeinit;
  late int Function() _retroApiVersion;
  late void Function(int, int) _retroSetControllerPortDevice;
  late bool Function(Pointer<retro_game_info>) _retroLoadGame;
  late void Function() _retroRun;
  late void Function() _retroUnloadGame;
  late void Function(Pointer<retro_system_info>) _retroGetSystemInfo;

  String coreName = 'Unknown Core';

  // Mock Engine Rendering Variables
  int _mockX = 120;
  int _mockY = 100;
  int _mockDX = 2;
  int _mockDY = 2;
  static const int _mockWidth = 256;
  static const int _mockHeight = 224;

  LibretroEngine() {
    activeInstance = this;
  }

  /// Extracts emulation core binary from Flutter assets to persistent documents folder
  static Future<String> extractCoreFromAssets(String coreAssetPath) async {
    final docDir = await getApplicationDocumentsDirectory();
    final filename = coreAssetPath.split('/').last;
    final targetFile = File('${docDir.path}/cores/$filename');

    if (!await targetFile.parent.exists()) {
      await targetFile.parent.create(recursive: true);
    }

    // Always copy in debug or when missing
    if (!await targetFile.exists()) {
      final data = await rootBundle.load(coreAssetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await targetFile.writeAsBytes(bytes);
    }
    return targetFile.path;
  }

  /// Initialize Libretro engine by loading dynamic library
  void initializeCore(String corePath) {
    _log('Initializing Core: $corePath');
    try {
      if (corePath.isEmpty || !File(corePath).existsSync()) {
        throw FileNotFoundException('Libretro core file not found at $corePath. Falling back to Mock Mode.');
      }

      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open(corePath);
      } else if (Platform.isIOS) {
        // Statically linked or loaded via Framework bundle on iOS
        _lib = DynamicLibrary.process();
      } else {
        _lib = DynamicLibrary.open(corePath);
      }

      _bindFunctions();
      _setupCallbacks();
      _retroInit();
      
      final info = calloc<retro_system_info>();
      _retroGetSystemInfo(info);
      if (info.ref.library_name != nullptr) {
        coreName = info.ref.library_name.toDartString();
      }
      calloc.free(info);

      _isCoreInitialized = true;
      isMockMode = false;
      _log('Libretro Dynamic Core loaded successfully. API Version: ${_retroApiVersion()}');
    } catch (e) {
      isMockMode = true;
      _isCoreInitialized = true;
      _log('FFI core load failed: $e. Running in high-performance mock simulation loop.');
    }
  }

  void _bindFunctions() {
    final dylib = _lib!;
    
    _retroSetEnvironment = dylib.lookupFunction<
        Void Function(Pointer<NativeFunction<retro_environment_t>>),
        void Function(Pointer<NativeFunction<retro_environment_t>>)>('retro_set_environment');

    _retroSetVideoRefresh = dylib.lookupFunction<
        Void Function(Pointer<NativeFunction<retro_video_refresh_t>>),
        void Function(Pointer<NativeFunction<retro_video_refresh_t>>)>('retro_set_video_refresh');

    _retroSetAudioSample = dylib.lookupFunction<
        Void Function(Pointer<NativeFunction<retro_audio_sample_t>>),
        void Function(Pointer<NativeFunction<retro_audio_sample_t>>)>('retro_set_audio_sample');

    _retroSetAudioSampleBatch = dylib.lookupFunction<
        Void Function(Pointer<NativeFunction<retro_audio_sample_batch_t>>),
        void Function(Pointer<NativeFunction<retro_audio_sample_batch_t>>)>('retro_set_audio_sample_batch');

    _retroSetInputPoll = dylib.lookupFunction<
        Void Function(Pointer<NativeFunction<retro_input_poll_t>>),
        void Function(Pointer<NativeFunction<retro_input_poll_t>>)>('retro_set_input_poll');

    _retroSetInputState = dylib.lookupFunction<
        Void Function(Pointer<NativeFunction<retro_input_state_t>>),
        void Function(Pointer<NativeFunction<retro_input_state_t>>)>('retro_set_input_state');

    _retroGetSystemInfo = dylib.lookupFunction<
        Void Function(Pointer<retro_system_info>),
        void Function(Pointer<retro_system_info>)>('retro_get_system_info');

    _retroInit = dylib.lookupFunction<Void Function(), void Function()>('retro_init');
    _retroDeinit = dylib.lookupFunction<Void Function(), void Function()>('retro_deinit');
    _retroApiVersion = dylib.lookupFunction<UnsignedInt Function(), int Function()>('retro_api_version');
    
    _retroSetControllerPortDevice = dylib.lookupFunction<
        Void Function(Uint32, Uint32),
        void Function(int, int)>('retro_set_controller_port_device');

    _retroLoadGame = dylib.lookupFunction<
        Bool Function(Pointer<retro_game_info>),
        bool Function(Pointer<retro_game_info>)>('retro_load_game');

    _retroRun = dylib.lookupFunction<Void Function(), void Function()>('retro_run');
    _retroUnloadGame = dylib.lookupFunction<Void Function(), void Function()>('retro_unload_game');
  }

  void _setupCallbacks() {
    _retroSetEnvironment(Pointer.fromFunction<retro_environment_t>(_environmentCallback, false));
    _retroSetVideoRefresh(Pointer.fromFunction<retro_video_refresh_t>(_videoRefreshCallback));
    _retroSetAudioSample(Pointer.fromFunction<retro_audio_sample_t>(_audioSampleCallback));
    _retroSetAudioSampleBatch(Pointer.fromFunction<retro_audio_sample_batch_t>(_audioSampleBatchCallback, 0));
    _retroSetInputPoll(Pointer.fromFunction<retro_input_poll_t>(_inputPollCallback));
    _retroSetInputState(Pointer.fromFunction<retro_input_state_t>(_inputStateCallback, 0));
  }

  /// Load ROM file and boot up core
  bool loadGame(String romPath) {
    _log('Loading game: $romPath');
    if (isMockMode) {
      _isGameLoaded = true;
      _log('Mock game loaded successfully.');
      startGameLoop();
      return true;
    }

    final pathPointer = romPath.toNativeUtf8();
    final gameInfo = calloc<retro_game_info>();
    gameInfo.ref.path = pathPointer;
    gameInfo.ref.data = nullptr;
    gameInfo.ref.size = 0;
    gameInfo.ref.meta = nullptr;

    try {
      _retroSetControllerPortDevice(0, RETRO_DEVICE_JOYPAD);
      _retroSetControllerPortDevice(1, RETRO_DEVICE_JOYPAD);
      
      final success = _retroLoadGame(gameInfo);
      if (success) {
        _isGameLoaded = true;
        _log('Libretro game loaded successfully.');
        startGameLoop();
      } else {
        _log('Libretro failed to load ROM.');
      }
      return success;
    } finally {
      calloc.free(gameInfo);
      // Do not free pathPointer immediately as core might access it asynchronously
    }
  }

  /// Starts execution loop at roughly 60 Hz (16.67ms per frame)
  void startGameLoop() {
    stopGameLoop();
    _gameLoopTimer = Timer.periodic(const Duration(microseconds: 16667), (timer) {
      if (!_isGameLoaded || !_isCoreInitialized) return;
      
      if (isMockMode) {
        _renderMockFrame();
      } else {
        if (isPaused) return;
        try {
          _retroRun();
        } catch (e) {
          _log('Error running emulator frame: $e');
        }
      }
    });
  }

  void stopGameLoop() {
    _gameLoopTimer?.cancel();
    _gameLoopTimer = null;
  }

  /// Update input state buffer
  void updateButtonState(int port, int customButtonId, bool pressed) {
    if (port == 0) {
      p1ButtonStates[customButtonId] = pressed;
    } else if (port == 1) {
      p2ButtonStates[customButtonId] = pressed;
    }
  }

  /// Shutdown emulator and release resources
  void togglePause() {
    isPaused = !isPaused;
  }

  void shutdown() {
    stopGameLoop();
    _log('Shutting down engine');
    if (_lib != null && !isMockMode) {
      if (_isGameLoaded) {
        _retroUnloadGame();
        _isGameLoaded = false;
      }
      if (_isCoreInitialized) {
        _retroDeinit();
        _isCoreInitialized = false;
      }
    }
    activeInstance = null;
  }

  // --- Callback Internal Implementations ---

  bool _handleEnvironment(int cmd, Pointer<Void> data) {
    // Basic Environment Commands handling
    switch (cmd) {
      case 9: // RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY
        if (data != nullptr) {
          // Point core to documents folder
          getApplicationDocumentsDirectory().then((dir) {
            final p = data.cast<Pointer<Utf8>>();
            p.value = dir.path.toNativeUtf8();
          });
          return true;
        }
        break;
      case 10: // RETRO_ENVIRONMENT_SET_PIXEL_FORMAT
        if (data != nullptr) {
          final fmt = data.cast<Uint32>().value;
          _log('Core set pixel format: $fmt (0 = 15bit, 1 = XRGB8888, 2 = RGB565)');
          return true;
        }
        break;
    }
    return false;
  }

  void _handleVideoRefresh(Pointer<Void> data, int width, int height, int pitch) {
    if (data == nullptr) return;
    
    // Convert core frame buffer based on format. For emulation, we assume RGB565 or XRGB8888.
    // Real retro games are small; NES/SNES/Sega are ~256x224 to ~320x224.
    // Convert buffer directly to RGBA8888 for Flutter presentation
    final totalPixels = width * height;
    final rgbaData = Uint8List(totalPixels * 4);
    
    // Standard Pitch represents width in bytes of a single scanline.
    // 2 bytes per pixel for RGB565.
    final pitchPixels = pitch ~/ 2;
    final Pointer<Uint16> src = data.cast<Uint16>();

    int destIdx = 0;
    for (int y = 0; y < height; y++) {
      final srcRowStart = y * pitchPixels;
      for (int x = 0; x < width; x++) {
        final pixel = src[srcRowStart + x];
        // Extract 5-6-5 RGB bits
        final r = ((pixel >> 11) & 0x1F) * 255 ~/ 31;
        final g = ((pixel >> 5) & 0x3F) * 255 ~/ 63;
        final b = (pixel & 0x1F) * 255 ~/ 31;
        
        rgbaData[destIdx++] = r;
        rgbaData[destIdx++] = g;
        rgbaData[destIdx++] = b;
        rgbaData[destIdx++] = 255; // Alpha
      }
    }

    rawFrameNotifier.value = rgbaData;

    ui.decodeImageFromPixels(
      rgbaData,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) {
        currentFrameNotifier.value = img;
      },
    );
  }

  void _handleAudioSample(int left, int right) {
    // Libretro audio out. Audio streams are not required for main UI presentation
    // but hooks are maintained.
  }

  int _handleAudioSampleBatch(Pointer<Int16> data, int frames) {
    if (frames > 0) {
      final int bytesCount = frames * 4; // 2 channels * 16-bit (2 bytes) = 4 bytes per frame
      final Uint8List audioBytes = data.cast<Uint8>().asTypedList(bytesCount);
      _audioChannel.invokeMethod('pushAudio', audioBytes);
    }
    return frames;
  }

  void _handleInputPoll() {
    // Inputs are polled automatically when calling input_state
  }

  int _handleInputState(int port, int device, int index, int id) {
    if (device != RETRO_DEVICE_JOYPAD) return 0;
    
    final customId = _libretroIdToCustomId(id);
    if (customId == null) return 0;

    bool pressed = false;
    if (port == 0) {
      pressed = p1ButtonStates[customId] ?? false;
    } else if (port == 1) {
      pressed = p2ButtonStates[customId] ?? false;
    }

    return pressed ? 1 : 0;
  }

  int? _libretroIdToCustomId(int libretroId) {
    switch (libretroId) {
      case RETRO_DEVICE_ID_JOYPAD_B: return 6;      // B
      case RETRO_DEVICE_ID_JOYPAD_Y: return 8;      // Y
      case RETRO_DEVICE_ID_JOYPAD_SELECT: return 10; // SELECT
      case RETRO_DEVICE_ID_JOYPAD_START: return 9;  // START
      case RETRO_DEVICE_ID_JOYPAD_UP: return 1;     // Up
      case RETRO_DEVICE_ID_JOYPAD_DOWN: return 2;   // Down
      case RETRO_DEVICE_ID_JOYPAD_LEFT: return 3;   // Left
      case RETRO_DEVICE_ID_JOYPAD_RIGHT: return 4;  // Right
      case RETRO_DEVICE_ID_JOYPAD_A: return 5;      // A
      case RETRO_DEVICE_ID_JOYPAD_X: return 7;      // X
      case RETRO_DEVICE_ID_JOYPAD_L: return 12;     // L1
      case RETRO_DEVICE_ID_JOYPAD_R: return 13;     // R1
      case RETRO_DEVICE_ID_JOYPAD_L2: return 14;    // L2
      case RETRO_DEVICE_ID_JOYPAD_R2: return 15;    // R2
      default: return null;
    }
  }

  // --- High-Performance Falling Interactive Mock Viewport ---
  
  void _renderMockFrame() {
    final totalPixels = _mockWidth * _mockHeight;
    final rgbaData = Uint8List(totalPixels * 4);
    
    // Draw background (sleek retro grid)
    for (int y = 0; y < _mockHeight; y++) {
      for (int x = 0; x < _mockWidth; x++) {
        final idx = (y * _mockWidth + x) * 4;
        final isGrid = (x % 32 == 0 || y % 32 == 0);
        if (isPaused) {
          // Dim the background if paused
          rgbaData[idx] = isGrid ? 15 : 8;
          rgbaData[idx + 1] = isGrid ? 15 : 8;
          rgbaData[idx + 2] = isGrid ? 20 : 10;
          rgbaData[idx + 3] = 255;
        } else {
          rgbaData[idx] = isGrid ? 35 : 18;      // R
          rgbaData[idx + 1] = isGrid ? 35 : 18;  // G
          rgbaData[idx + 2] = isGrid ? 50 : 22;  // B
          rgbaData[idx + 3] = 255;               // A
        }
      }
    }

    // Render visual feedback representing buttons being pressed
    // P1 (Host) Gamepad Indicators - Red Glowing Chips
    if (p1ButtonStates[1] ?? false) _drawMockSquare(rgbaData, 45, 30, 255, 0, 100);  // UP
    if (p1ButtonStates[2] ?? false) _drawMockSquare(rgbaData, 45, 60, 255, 0, 100);  // DOWN
    if (p1ButtonStates[3] ?? false) _drawMockSquare(rgbaData, 30, 45, 255, 0, 100);  // LEFT
    if (p1ButtonStates[4] ?? false) _drawMockSquare(rgbaData, 60, 45, 255, 0, 100);  // RIGHT
    if (p1ButtonStates[5] ?? false) _drawMockSquare(rgbaData, 90, 50, 0, 255, 120);  // A
    if (p1ButtonStates[6] ?? false) _drawMockSquare(rgbaData, 105, 50, 0, 255, 120); // B
    if (p1ButtonStates[7] ?? false) _drawMockSquare(rgbaData, 90, 35, 0, 255, 120);  // X
    if (p1ButtonStates[8] ?? false) _drawMockSquare(rgbaData, 105, 35, 0, 255, 120); // Y

    // P2 (Client) Gamepad Indicators - Blue Glowing Chips
    if (p2ButtonStates[1] ?? false) _drawMockSquare(rgbaData, 195, 30, 0, 100, 255);  // UP
    if (p2ButtonStates[2] ?? false) _drawMockSquare(rgbaData, 195, 60, 0, 100, 255);  // DOWN
    if (p2ButtonStates[3] ?? false) _drawMockSquare(rgbaData, 180, 45, 0, 100, 255);  // LEFT
    if (p2ButtonStates[4] ?? false) _drawMockSquare(rgbaData, 210, 45, 0, 100, 255);  // RIGHT
    if (p2ButtonStates[5] ?? false) _drawMockSquare(rgbaData, 240, 50, 255, 200, 0);  // A
    if (p2ButtonStates[6] ?? false) _drawMockSquare(rgbaData, 255, 50, 255, 200, 0);  // B
    if (p2ButtonStates[7] ?? false) _drawMockSquare(rgbaData, 240, 35, 255, 200, 0);  // X
    if (p2ButtonStates[8] ?? false) _drawMockSquare(rgbaData, 255, 35, 255, 200, 0);  // Y

    // Start/Select HUD markers
    if (p1ButtonStates[9] ?? false) _drawMockSquare(rgbaData, 130, 180, 0, 255, 255);  // P1 START
    if (p1ButtonStates[10] ?? false) _drawMockSquare(rgbaData, 110, 180, 0, 255, 255); // P1 SELECT
    if (p2ButtonStates[9] ?? false) _drawMockSquare(rgbaData, 150, 180, 255, 0, 255);  // P2 START
    if (p2ButtonStates[10] ?? false) _drawMockSquare(rgbaData, 170, 180, 255, 0, 255); // P2 SELECT

    // Bouncing Ball
    if (!isPaused) {
      _mockX += _mockDX;
      _mockY += _mockDY;
      if (_mockX <= 5 || _mockX >= _mockWidth - 20) _mockDX = -_mockDX;
      if (_mockY <= 5 || _mockY >= _mockHeight - 20) _mockDY = -_mockDY;
    }

    // Draw active bouncing box
    for (int y = _mockY; y < _mockY + 12; y++) {
      for (int x = _mockX; x < _mockX + 12; x++) {
        if (x >= 0 && x < _mockWidth && y >= 0 && y < _mockHeight) {
          final idx = (y * _mockWidth + x) * 4;
          rgbaData[idx] = 0;
          rgbaData[idx + 1] = isPaused ? 100 : 255;
          rgbaData[idx + 2] = 0;
          rgbaData[idx + 3] = 255;
        }
      }
    }

    if (isPaused) {
      // Draw PAUSED in red blocks in the center
      _drawMockSquare(rgbaData, 120, 110, 255, 0, 0);
      _drawMockSquare(rgbaData, 135, 110, 255, 0, 0);
      // P A U S E D indicator
      for(int i = 0; i < 60; i++) {
         _drawMockSquare(rgbaData, 100 + i, 100, 255, 255, 255);
      }
    }

    rawFrameNotifier.value = rgbaData;

    ui.decodeImageFromPixels(
      rgbaData,
      _mockWidth,
      _mockHeight,
      ui.PixelFormat.rgba8888,
      (ui.Image img) {
        currentFrameNotifier.value = img;
      },
    );
  }

  void _drawMockSquare(Uint8List rgba, int sx, int sy, int r, int g, int b) {
    for (int y = sy; y < sy + 8; y++) {
      for (int x = sx; x < sx + 8; x++) {
        if (x >= 0 && x < _mockWidth && y >= 0 && y < _mockHeight) {
          final idx = (y * _mockWidth + x) * 4;
          rgba[idx] = r;
          rgba[idx + 1] = g;
          rgba[idx + 2] = b;
          rgba[idx + 3] = 255;
        }
      }
    }
  }

  void _log(String message) {
    logNotifier.value = '[${DateTime.now().toIso8601String().substring(11, 19)}] $message';
    debugPrint('[LibretroEngine] $message');
  }
}

class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
  @override
  String toString() => message;
}
