// ignore_for_file: camel_case_types, non_constant_identifier_names, constant_identifier_names
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide Size;
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';
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

const int retro_hw_frame_buffer_valid = -1; // -1 casted to pointer is (void*)-1

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
  @Bool() external bool need_fullpath;
  @Bool() external bool block_extract;
}

final class retro_game_geometry extends Struct {
  @Uint32() external int base_width;
  @Uint32() external int base_height;
  @Uint32() external int max_width;
  @Uint32() external int max_height;
  @Float() external double aspect_ratio;
}

final class retro_system_timing extends Struct {
  @Double() external double fps;
  @Double() external double sample_rate;
}

final class retro_system_av_info extends Struct {
  external retro_game_geometry geometry;
  external retro_system_timing timing;
}

// --- FFI Callback Type Definitions ---

typedef retro_environment_t = Bool Function(Uint32 cmd, Pointer<Void> data);
typedef retro_video_refresh_t = Void Function(Pointer<Void> data, Uint32 width, Uint32 height, IntPtr pitch);
typedef retro_audio_sample_t = Void Function(Int16 left, Int16 right);
typedef retro_audio_sample_batch_t = IntPtr Function(Pointer<Int16> data, IntPtr frames);
typedef retro_input_poll_t = Void Function();
typedef retro_input_state_t = Int16 Function(Uint32 port, Uint32 device, Uint32 index, Uint32 id);

typedef render_to_window_c = Void Function(Pointer<Uint16> pixels, Int32 width, Int32 height, Int32 pitch);
typedef render_to_window_dart = void Function(Pointer<Uint16> pixels, int width, int height, int pitch);

typedef hw_render_init_c = Bool Function(Int32 width, Int32 height);
typedef hw_render_init_dart = bool Function(int width, int height);

typedef retro_hw_get_current_framebuffer_t = IntPtr Function();
typedef retro_hw_get_proc_address_t = Pointer<Void> Function(Pointer<Utf8> sym);

final class retro_hw_render_callback extends Struct {
  @Int32() external int context_type;
  external Pointer<NativeFunction<retro_hw_get_current_framebuffer_t>> get_current_framebuffer;
  external Pointer<NativeFunction<retro_hw_get_proc_address_t>> get_proc_address;
  external Pointer<Void> depth;
  external Pointer<Void> stencil;
  external Pointer<Void> bottom_left_origin;
  external Pointer<Void> version_major;
  external Pointer<Void> version_minor;
  @Bool() external bool cache_context;
  external Pointer<Void> context_reset;
  external Pointer<Void> context_destroy;
}

// --- Main Engine Wrapper ---

class LibretroEngine {
  static LibretroEngine? activeInstance;

  // Emulation State Notifiers
  // Texture ID notifier removed as we no longer render via Flutter texture
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
  String _coreName = 'Unknown Core';
  String get coreName => _coreName;
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
  late void Function() _retroUnloadGame;
  late void Function(Pointer<retro_system_info>) _retroGetSystemInfo;
  late void Function(Pointer<retro_system_av_info>) _retroGetSystemAvInfo;
  late void Function() _retroReset;
  late int Function() _retroSerializeSize;
  late bool Function(Pointer<Void>, int) _retroSerialize;
  late bool Function(Pointer<Void>, int) _retroUnserialize;
  // Native Audio Bridge
  late void Function(double) _nativeAudioInit;
  late void Function() _nativeAudioDeinit;
  late void Function(int, bool) _setPlayer1Button;
  late void Function(int, int, int) _setPlayer1Analog;
  late void Function(int, int, bool) _setPlayer1Pointer;
  late Pointer<NativeFunction<retro_audio_sample_batch_t>> _nativeAudioCb;
  late Pointer<NativeFunction<retro_input_state_t>> _nativeInputCb;
  late Pointer<NativeFunction<retro_video_refresh_t>> _nativeVideoCb;
  late Pointer<NativeFunction<retro_audio_sample_t>> _nativeAudioSampleCb;
  late Pointer<NativeFunction<retro_input_poll_t>> _nativeInputPollCb;
  late Pointer<NativeFunction<retro_environment_t>> _nativeEnvironmentCb;
  
  // Native Emulator Thread Bridge
  late Pointer<NativeFunction<Void Function()>> _retroRunPtr;
  late void Function(int, double) _startNativeEmulatorThread;
  late void Function() _stopNativeEmulatorThread;
  late void Function(bool) _setNativeEmulatorPaused;
  
  double _coreFps = 60.0;

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
        final nativeRenderLib = DynamicLibrary.open('libnative_render.so');
        _nativeVideoCb = nativeRenderLib.lookup<NativeFunction<retro_video_refresh_t>>('render_to_window');
        _nativeAudioSampleCb = nativeRenderLib.lookup<NativeFunction<retro_audio_sample_t>>('native_audio_sample_cb');
        _nativeInputPollCb = nativeRenderLib.lookup<NativeFunction<retro_input_poll_t>>('native_input_poll_cb');
        _nativeEnvironmentCb = nativeRenderLib.lookup<NativeFunction<retro_environment_t>>('native_environment_cb');
        
        _nativeAudioInit = nativeRenderLib.lookupFunction<Void Function(Double), void Function(double)>('native_audio_init');
        _nativeAudioDeinit = nativeRenderLib.lookupFunction<Void Function(), void Function()>('native_audio_deinit');
        _nativeAudioCb = nativeRenderLib.lookup<NativeFunction<retro_audio_sample_batch_t>>('native_audio_sample_batch_cb');
        _nativeInputCb = nativeRenderLib.lookup<NativeFunction<retro_input_state_t>>('native_input_state_cb');
        _setPlayer1Button = nativeRenderLib.lookupFunction<Void Function(Int32, Bool), void Function(int, bool)>('set_player1_button');
        _setPlayer1Analog = nativeRenderLib.lookupFunction<Void Function(Int32, Int32, Int16), void Function(int, int, int)>('set_player1_analog');
        _setPlayer1Pointer = nativeRenderLib.lookupFunction<Void Function(Int16, Int16, Bool), void Function(int, int, bool)>('set_player1_pointer');
        _startNativeEmulatorThread = nativeRenderLib.lookupFunction<Void Function(IntPtr, Double), void Function(int, double)>('start_native_emulator_thread');
        _stopNativeEmulatorThread = nativeRenderLib.lookupFunction<Void Function(), void Function()>('stop_native_emulator_thread');
        _setNativeEmulatorPaused = nativeRenderLib.lookupFunction<Void Function(Bool), void Function(bool)>('set_native_emulator_paused');
      } else if (Platform.isIOS) {
        // Statically linked or loaded via Framework bundle on iOS
        _lib = DynamicLibrary.process();
        _nativeAudioInit = DynamicLibrary.process().lookupFunction<Void Function(Double), void Function(double)>('native_audio_init');
        _nativeAudioDeinit = DynamicLibrary.process().lookupFunction<Void Function(), void Function()>('native_audio_deinit');
        _nativeAudioCb = DynamicLibrary.process().lookup<NativeFunction<retro_audio_sample_batch_t>>('native_audio_sample_batch_cb');
        _nativeInputCb = DynamicLibrary.process().lookup<NativeFunction<retro_input_state_t>>('native_input_state_cb');
        _setPlayer1Button = DynamicLibrary.process().lookupFunction<Void Function(Int32, Bool), void Function(int, bool)>('set_player1_button');
        _setPlayer1Analog = DynamicLibrary.process().lookupFunction<Void Function(Int32, Int32, Int16), void Function(int, int, int)>('set_player1_analog');
        _setPlayer1Pointer = DynamicLibrary.process().lookupFunction<Void Function(Int16, Int16, Bool), void Function(int, int, bool)>('set_player1_pointer');
        _startNativeEmulatorThread = DynamicLibrary.process().lookupFunction<Void Function(IntPtr, Double), void Function(int, double)>('start_native_emulator_thread');
        _stopNativeEmulatorThread = DynamicLibrary.process().lookupFunction<Void Function(), void Function()>('stop_native_emulator_thread');
        _setNativeEmulatorPaused = DynamicLibrary.process().lookupFunction<Void Function(Bool), void Function(bool)>('set_native_emulator_paused');
      } else {
        _lib = DynamicLibrary.open(corePath);
      }

      _bindFunctions();
      _setupCallbacks();
      _retroInit();
      
      final info = calloc<retro_system_info>();
      _retroGetSystemInfo(info);
      if (info.ref.library_name != nullptr) {
        _coreName = info.ref.library_name.toDartString();
      }
      calloc.free(info);

      // _nativeAudioInit is called in loadGame once we have sample_rate

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
        
    _retroGetSystemAvInfo = dylib.lookupFunction<
        Void Function(Pointer<retro_system_av_info>),
        void Function(Pointer<retro_system_av_info>)>('retro_get_system_av_info');

    _retroInit = dylib.lookupFunction<Void Function(), void Function()>('retro_init');
    _retroDeinit = dylib.lookupFunction<Void Function(), void Function()>('retro_deinit');
    _retroApiVersion = dylib.lookupFunction<UnsignedInt Function(), int Function()>('retro_api_version');
    
    _retroSetControllerPortDevice = dylib.lookupFunction<
        Void Function(Uint32, Uint32),
        void Function(int, int)>('retro_set_controller_port_device');

    _retroLoadGame = dylib.lookupFunction<
        Bool Function(Pointer<retro_game_info>),
        bool Function(Pointer<retro_game_info>)>('retro_load_game');

    _retroRunPtr = dylib.lookup<NativeFunction<Void Function()>>('retro_run');
    _retroUnloadGame = dylib.lookupFunction<Void Function(), void Function()>('retro_unload_game');
    _retroReset = dylib.lookupFunction<Void Function(), void Function()>('retro_reset');

    _retroSerializeSize = dylib.lookupFunction<IntPtr Function(), int Function()>('retro_serialize_size');
    _retroSerialize = dylib.lookupFunction<Bool Function(Pointer<Void>, IntPtr), bool Function(Pointer<Void>, int)>('retro_serialize');
    _retroUnserialize = dylib.lookupFunction<Bool Function(Pointer<Void>, IntPtr), bool Function(Pointer<Void>, int)>('retro_unserialize');
  }

  void _setupCallbacks() {
    _retroSetEnvironment(_nativeEnvironmentCb);
    _retroSetVideoRefresh(_nativeVideoCb);
    _retroSetAudioSample(_nativeAudioSampleCb);
    _retroSetAudioSampleBatch(_nativeAudioCb);
    _retroSetInputPoll(_nativeInputPollCb);
    _retroSetInputState(_nativeInputCb);
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
        
        final avInfo = calloc<retro_system_av_info>();
        _retroGetSystemAvInfo(avInfo);
        _coreFps = avInfo.ref.timing.fps;
        if (_coreFps <= 0) _coreFps = 60.0;
        _log('Core requested FPS: $_coreFps');
        double sampleRate = avInfo.ref.timing.sample_rate;
        if (sampleRate <= 0) sampleRate = 44100.0;
        _nativeAudioInit(sampleRate);
        calloc.free(avInfo);
        
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

  void resetGame() {
    if (_isCoreInitialized && !isMockMode) {
      _retroReset();
      _log('Game Reset');
    }
  }

  Future<bool> saveState(int slot) async {
    if (isMockMode) return false;
    try {
      final size = _retroSerializeSize();
      if (size == 0) return false;
      
      final buffer = calloc<Uint8>(size);
      final success = _retroSerialize(buffer.cast<Void>(), size);
      
      if (success) {
        final bytes = buffer.asTypedList(size);
        final docDir = await getApplicationDocumentsDirectory();
        final saveFile = File('${docDir.path}/save_state_$slot.st');
        await saveFile.writeAsBytes(bytes);
        _log('State saved to slot $slot ($size bytes)');
      }
      calloc.free(buffer);
      return success;
    } catch (e) {
      _log('Failed to save state: $e');
      return false;
    }
  }

  Future<bool> loadState(int slot) async {
    if (isMockMode) return false;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final saveFile = File('${docDir.path}/save_state_$slot.st');
      if (!await saveFile.exists()) return false;

      final bytes = await saveFile.readAsBytes();
      final size = _retroSerializeSize();
      
      if (bytes.length != size) {
        _log('State size mismatch. Expected $size, got ${bytes.length}');
        return false;
      }

      final buffer = calloc<Uint8>(size);
      buffer.asTypedList(size).setAll(0, bytes);
      
      final success = _retroUnserialize(buffer.cast<Void>(), size);
      if (success) {
        _log('State loaded from slot $slot');
      }
      calloc.free(buffer);
      return success;
    } catch (e) {
      _log('Failed to load state: $e');
      return false;
    }
  }

  /// Starts execution loop based on core's requested FPS
  void startGameLoop() {
    stopGameLoop();
    if (isMockMode) {
      int intervalUs = (1000000.0 / _coreFps).round();
      _log('Starting mock game loop with interval: $intervalUs microseconds');
      _gameLoopTimer = Timer.periodic(Duration(microseconds: intervalUs), (timer) {
        _renderMockFrame();
      });
    } else {
      _log('Starting Native C++ Emulator Thread with FPS: $_coreFps');
      _startNativeEmulatorThread(_retroRunPtr.address, _coreFps);
    }
  }

  void stopGameLoop() {
    _gameLoopTimer?.cancel();
    _gameLoopTimer = null;
    if (!isMockMode) {
      _stopNativeEmulatorThread();
    }
  }

  /// Update input state buffer
  void updateButtonState(int port, int customButtonId, bool pressed) {
    if (port == 0) {
      if (isMockMode) {
        p1ButtonStates[customButtonId] = pressed;
      } else {
        _setPlayer1Button(customButtonId, pressed);
      }
    } else if (port == 1) {
      p2ButtonStates[customButtonId] = pressed;
    }
  }

  /// Update analog state buffer (Dreamcast)
  void updateAnalogState(int port, int index, int id, int value) {
    if (port == 0 && !isMockMode) {
      _setPlayer1Analog(index, id, value);
    }
    // Note: Player 2 analog over network not fully implemented yet
  }

  /// Update pointer state buffer (Nintendo DS)
  void updatePointerState(int port, int x, int y, bool pressed) {
    if (port == 0 && !isMockMode) {
      _setPlayer1Pointer(x, y, pressed);
    }
  }

  /// Shutdown emulator and release resources
  void togglePause() {
    isPaused = !isPaused;
    if (!isMockMode) {
      _setNativeEmulatorPaused(isPaused);
    }
  }

  void shutdown() {
    stopGameLoop();
    _log('Shutting down engine');
    if (_lib != null && !isMockMode) {
      _nativeAudioDeinit();
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

  // --- Callback Internal Implementations removed as C++ Bridge handles it ---

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
    // Since TV renders natively and we don't preview, we just process inputs.
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
    ConsoleLogger.log('Libretro', message);
  }
}

class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
  @override
  String toString() => message;
}
