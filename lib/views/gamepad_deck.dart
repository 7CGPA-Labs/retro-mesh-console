import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../utils/logger.dart';
import 'package:flutter/material.dart';
import '../emulation/libretro.dart';
import '../utils/native_bridge.dart';
import 'package:gamepads/gamepads.dart';

class GamepadDeck extends StatefulWidget {
  final bool isHost;
  final LibretroEngine? engine;
  final String romName;
  final String coreName;
  final String hostType;

  const GamepadDeck({
    super.key,
    required this.isHost,
    this.engine,
    required this.romName,
    this.coreName = 'nes',
    this.hostType = 'unknown',
  });

  @override
  State<GamepadDeck> createState() => _GamepadDeckState();
}

class _GamepadDeckState extends State<GamepadDeck> with WidgetsBindingObserver {
  static const MethodChannel _projectionChannel = MethodChannel('dev.seven_cgpalabs.mojosnap/projection');
  
  bool _isConnectingTV = false; // Track if waiting for OS Cast dialog to return
  bool _isMenuOpen = false;
  bool _useAnalogStick = false;
  Offset _analogStickPos = Offset.zero;
  int? _activeAnalogDPadX; // 3 for left, 4 for right
  int? _activeAnalogDPadY; // 1 for up, 2 for down
  late String _currentCoreName;
  late StreamSubscription<String> _coreSubscription;
  StreamSubscription<GamepadEvent>? _gamepadSubscription;
  bool _isPhysicalControllerActive = false;

  @override
  void initState() {
    super.initState();
    _currentCoreName = widget.coreName;
    _coreSubscription = NativeBridge.onCoreChanged.listen((newCore) {
      if (mounted) {
        setState(() {
          _currentCoreName = newCore;
        });
      }
    });
    WidgetsBinding.instance.addObserver(this);
    
    // 1. Lock screen orientation to Landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // Hide system UI (status bar / navigation bar) for full immersive gameplay
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    // 2. Prevent mobile OS from sleeping or throttling priority threads natively
    NativeBridge.keepScreenOn(true);

    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    _gamepadSubscription = Gamepads.events.listen(_onGamepadEvent);

    if (widget.isHost) {
      _isConnectingTV = true;
      _checkPreConnectedDisplay();
    } else {
      NativeBridge.onDisconnected.listen((_) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }



  void _checkPreConnectedDisplay() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _startNativeTVProjection().then((connected) {
        if (connected && mounted) {
          setState(() {
            _isConnectingTV = false;
          });
        } else if (mounted) {
          // Not pre-connected, show options
          _showCastDialog();
        }
      });
    });
  }

  void _showCastDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Connect to a display', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
        content: const Text(
          'Use the system display picker to connect to a wireless display or Smart TV.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              const MethodChannel('dev.seven_cgpalabs.mojosnap/projection').invokeMethod('openSystemCastMenu');
            },
            child: const Text('Open display picker', style: TextStyle(color: Color(0xFFFF2E93))),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NativeBridge.keepScreenOn(true);
      
      if (widget.isHost && _isConnectingTV) {
        _tryConnectTV();
      }
    } else if (state == AppLifecycleState.paused) {
      if (widget.isHost && widget.engine != null) {
        // Automatically pause emulator to prevent background audio playback
        if (!widget.engine!.isPaused) {
          setState(() {
            widget.engine!.togglePause();
          });
        }
      }
    }
  }

  Future<void> _tryConnectTV() async {
    for (int i = 0; i < 5; i++) {
      if (!mounted) return;
      bool connected = await _startNativeTVProjection();
      if (connected) {
        if (mounted) {
          setState(() {
            _isConnectingTV = false;
          });
        }
        return;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text(
            'No wireless display detected. Emulation exited.',
            style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      );
      _exitGame(context);
    }
  }

  @override
  void dispose() {
    _coreSubscription.cancel();
    _gamepadSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    if (widget.isHost) {
      // Clean up host things
    }
    // Restore orientation settings
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    
    // Restore system UI overlays
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    NativeBridge.keepScreenOn(false);

    if (widget.isHost) {
      _stopNativeTVProjection();
      widget.engine?.shutdown();
      NativeBridge.stopHost();
    }
    super.dispose();
  }

  /// Triggers Platform-specific dual-screen window allocations.
  /// Detailed Native implementations for iOS and Android are documented below the widget.
  Future<bool> _startNativeTVProjection() async {
    try {
      final bool? success = await _projectionChannel.invokeMethod<bool>('startTVProjection');
      return success ?? false;
    } catch (e) {
      debugPrint('Native projection start error: $e');
      return false;
    }
  }

  Future<void> _stopNativeTVProjection() async {
    try {
      await _projectionChannel.invokeMethod('stopTVProjection');
    } catch (e) {
      debugPrint('Native projection stop error: $e');
    }
  }

  void _handleButtonEvent(int buttonId, bool pressed) {
    if (pressed) {
      HapticFeedback.lightImpact();
    }
    
    if (buttonId == MOJO_VIRTUAL_MENU) { // MENU (ID 16) — app-internal, never forwarded to core
      if (_isPhysicalControllerActive) {
        setState(() {
          _isPhysicalControllerActive = false;
        });
      }
      
      if (pressed) {
        if (widget.isHost) {
          if (_isMenuOpen) {
            Navigator.of(context, rootNavigator: true).pop();
          } else {
            _togglePause();
            if (widget.engine != null && widget.engine!.isPaused) {
              _showMenuOverlay();
            }
          }
        } else {
          if (_isMenuOpen) {
            Navigator.of(context, rootNavigator: true).pop();
          } else {
            _showClientMenuOverlay();
          }
        }
      }
      return;
    }

    if (widget.isHost) {
      // Local Host maps directly to Port 1 (index 0) in Libretro
      widget.engine?.updateButtonState(0, buttonId, pressed);
    } else {
      // Client maps to Port 2 (index 1) by sending over WebSocket
      NativeBridge.sendInput(buttonId, pressed);
    }
  }

  void _onGamepadEvent(GamepadEvent event) {
    if (!_isPhysicalControllerActive) {
      setState(() {
        _isPhysicalControllerActive = true;
      });
    }

    if (event.type == KeyType.button) {
      int? buttonId;
      final k = event.key.toLowerCase();
      // Physical gamepad button IDs follow RETRO_DEVICE_ID_JOYPAD_* (see SHARED_INPUT_PROTOCOL.md)
      // Positional mapping: regardless of Xbox/PS/Switch branding
      if      (k.contains('dpad-up')    || k.contains('dpad_up')    || k == 'up')    buttonId = RETRO_DEVICE_ID_JOYPAD_UP;     // 4
      else if (k.contains('dpad-down')  || k.contains('dpad_down')  || k == 'down')  buttonId = RETRO_DEVICE_ID_JOYPAD_DOWN;   // 5
      else if (k.contains('dpad-left')  || k.contains('dpad_left')  || k == 'left')  buttonId = RETRO_DEVICE_ID_JOYPAD_LEFT;   // 6
      else if (k.contains('dpad-right') || k.contains('dpad_right') || k == 'right') buttonId = RETRO_DEVICE_ID_JOYPAD_RIGHT;  // 7
      // Face buttons: positional (bottom=B, right=A, left=Y, top=X)
      else if (k.contains('button-a') || k.contains('button_a') || k == 'a') buttonId = RETRO_DEVICE_ID_JOYPAD_B;    // 0 — bottom face
      else if (k.contains('button-b') || k.contains('button_b') || k == 'b') buttonId = RETRO_DEVICE_ID_JOYPAD_A;    // 8 — right face
      else if (k.contains('button-x') || k.contains('button_x') || k == 'x') buttonId = RETRO_DEVICE_ID_JOYPAD_Y;    // 1 — left face
      else if (k.contains('button-y') || k.contains('button_y') || k == 'y') buttonId = RETRO_DEVICE_ID_JOYPAD_X;    // 9 — top face
      else if (k.contains('start'))                                           buttonId = RETRO_DEVICE_ID_JOYPAD_START;  // 3
      else if (k.contains('select'))                                          buttonId = RETRO_DEVICE_ID_JOYPAD_SELECT; // 2
      else if (k.contains('mode') || k.contains('menu'))                     buttonId = MOJO_VIRTUAL_MENU;             // 16 — app-internal
      else if (k.contains('l1') || k.contains('leftshoulder'))               buttonId = RETRO_DEVICE_ID_JOYPAD_L;     // 10
      else if (k.contains('r1') || k.contains('rightshoulder'))              buttonId = RETRO_DEVICE_ID_JOYPAD_R;     // 11
      else if (k.contains('l2') || k.contains('lefttrigger'))                buttonId = RETRO_DEVICE_ID_JOYPAD_L2;    // 12
      else if (k.contains('r2') || k.contains('righttrigger'))               buttonId = RETRO_DEVICE_ID_JOYPAD_R2;    // 13
      else if (k.contains('l3') || k.contains('leftstick'))                  buttonId = RETRO_DEVICE_ID_JOYPAD_L3;    // 14
      else if (k.contains('r3') || k.contains('rightstick'))                 buttonId = RETRO_DEVICE_ID_JOYPAD_R3;    // 15

      if (buttonId != null) {
        final pressed = event.value > 0.5;
        _handleButtonEvent(buttonId, pressed);
      }
    } else if (event.type == KeyType.analog) {
      int? index;
      int? id;
      final k = event.key.toLowerCase();
      
      if (k.contains('left')) {
        index = 0; // RETRO_DEVICE_INDEX_ANALOG_LEFT
      } else if (k.contains('right')) {
        index = 1; // RETRO_DEVICE_INDEX_ANALOG_RIGHT
      }

      if (k.contains('x')) {
        id = 0; // RETRO_DEVICE_ID_ANALOG_X
      } else if (k.contains('y')) {
        id = 1; // RETRO_DEVICE_ID_ANALOG_Y
      }

      if (index != null && id != null) {
        int analogValue = (event.value * 32767).toInt();
        // Clamp to Int16
        if (analogValue < -32768) analogValue = -32768;
        if (analogValue > 32767) analogValue = 32767;

        if (widget.isHost) {
          widget.engine?.updateAnalogState(0, index, id, analogValue);
        } else {
          NativeBridge.sendAnalogInput(index, id, analogValue);
        }
      }
    }
  }


  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyUpEvent) {
      final pressed = event is KeyDownEvent;
      final key = event.logicalKey;
      int? buttonId;

      // Keyboard → RetroPad mapping (retroarch.cfg standard)
      // See SHARED_INPUT_PROTOCOL.md §3 for full table
      if      (key == LogicalKeyboardKey.arrowUp)                                               { buttonId = RETRO_DEVICE_ID_JOYPAD_UP;     // 4
      } else if (key == LogicalKeyboardKey.arrowDown)                                           { buttonId = RETRO_DEVICE_ID_JOYPAD_DOWN;   // 5
      } else if (key == LogicalKeyboardKey.arrowLeft)                                           { buttonId = RETRO_DEVICE_ID_JOYPAD_LEFT;   // 6
      } else if (key == LogicalKeyboardKey.arrowRight)                                          { buttonId = RETRO_DEVICE_ID_JOYPAD_RIGHT;  // 7
      } else if (key == LogicalKeyboardKey.gameButtonA || key == LogicalKeyboardKey.keyZ)       { buttonId = RETRO_DEVICE_ID_JOYPAD_B;     // 0 — Z = B (bottom)
      } else if (key == LogicalKeyboardKey.gameButtonB || key == LogicalKeyboardKey.keyX)       { buttonId = RETRO_DEVICE_ID_JOYPAD_A;     // 8 — X = A (right)
      } else if (key == LogicalKeyboardKey.gameButtonX || key == LogicalKeyboardKey.keyA)       { buttonId = RETRO_DEVICE_ID_JOYPAD_Y;     // 1 — A = Y (left)
      } else if (key == LogicalKeyboardKey.gameButtonY || key == LogicalKeyboardKey.keyS)       { buttonId = RETRO_DEVICE_ID_JOYPAD_X;     // 9 — S = X (top)
      } else if (key == LogicalKeyboardKey.gameButtonStart  || key == LogicalKeyboardKey.enter) { buttonId = RETRO_DEVICE_ID_JOYPAD_START;  // 3
      } else if (key == LogicalKeyboardKey.gameButtonSelect || key == LogicalKeyboardKey.shiftRight) { buttonId = RETRO_DEVICE_ID_JOYPAD_SELECT; // 2 — Right Shift = Select
      } else if (key == LogicalKeyboardKey.gameButtonMode   || key == LogicalKeyboardKey.escape) { buttonId = MOJO_VIRTUAL_MENU;            // 16 — app-internal
      } else if (key == LogicalKeyboardKey.gameButtonLeft1  || key == LogicalKeyboardKey.keyQ)  { buttonId = RETRO_DEVICE_ID_JOYPAD_L;    // 10 — Q = L1
      } else if (key == LogicalKeyboardKey.gameButtonRight1 || key == LogicalKeyboardKey.keyW)  { buttonId = RETRO_DEVICE_ID_JOYPAD_R;    // 11 — W = R1
      } else if (key == LogicalKeyboardKey.gameButtonLeft2  || key == LogicalKeyboardKey.keyE)  { buttonId = RETRO_DEVICE_ID_JOYPAD_L2;   // 12 — E = L2
      } else if (key == LogicalKeyboardKey.gameButtonRight2 || key == LogicalKeyboardKey.keyR)  { buttonId = RETRO_DEVICE_ID_JOYPAD_R2;   // 13 — R = R2
      }
      
      if (buttonId != null) {
        _handleButtonEvent(buttonId, pressed);
        return true;
      }
    }
    return false;
  }

  void _togglePause() {
    if (widget.isHost && widget.engine != null) {
      setState(() {
        widget.engine!.togglePause();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          backgroundColor: const Color(0xFFFF2E93),
          content: Text(
            widget.engine!.isPaused ? 'GAME PAUSED' : 'GAME RESUMED',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Outfit',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
  }

  void _showMenuOverlay() {
    _isMenuOpen = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.menu, color: Color(0xFFFF2E93)),
            const SizedBox(width: 10),
            const Text(
              'CONSOLE MENU',
              style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.play_arrow, color: Colors.white70),
                title: const Text('Resume Game', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.refresh, color: Colors.white70),
                title: const Text('Reset Game', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 14)),
                onTap: () {
                  if (widget.engine != null) {
                    widget.engine!.resetGame();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Resetting Game...')),
                    );
                  }
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.save, color: Colors.white70),
                title: const Text('Quick Save (Slot 1)', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 14)),
                onTap: () async {
                  Navigator.pop(ctx); // Pop first so the `.then()` handler resumes the game visually
                  if (widget.engine != null) {
                    bool success = await widget.engine!.saveState(1);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(success ? 'State Saved!' : 'Failed to save state')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_open, color: Colors.white70),
                title: const Text('Quick Load (Slot 1)', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 14)),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (widget.engine != null) {
                    bool success = await widget.engine!.loadState(1);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(success ? 'State Loaded!' : 'Failed to load state or slot empty')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.exit_to_app, color: Color(0xFFEF4444)),
                title: const Text('Stop Emulation & Exit', style: TextStyle(color: Color(0xFFEF4444), fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _exitGame(context);
                },
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      _isMenuOpen = false;
      // Unpause whenever the dialog is dismissed (either by button tap or tapping outside)
      if (widget.engine != null && widget.engine!.isPaused) {
        _togglePause();
      }
    });
  }

  void _showClientMenuOverlay() {
    _isMenuOpen = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.menu, color: Color(0xFF00E5FF)),
            const SizedBox(width: 10),
            const Text(
              'CLIENT MENU',
              style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.play_arrow, color: Colors.white70),
                title: const Text('Resume', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.exit_to_app, color: Color(0xFFEF4444)),
                title: const Text('Disconnect', style: TextStyle(color: Color(0xFFEF4444), fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context); // Disconnect and go back
                },
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      _isMenuOpen = false;
    });
  }

  void _exitGame(BuildContext context) {
    if (widget.isHost) {
      _stopNativeTVProjection();
      widget.engine?.shutdown();
      NativeBridge.stopHost();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
    Navigator.pop(context); // Redirect back to main page (RoleGate)
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isHost && _isConnectingTV) {
      return Scaffold(
        backgroundColor: const Color(0xFF070714),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF2E93).withValues(alpha: 0.08),
                  border: Border.all(color: const Color(0xFFFF2E93).withValues(alpha: 0.3), width: 1.5),
                ),
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF2E93)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'WAITING FOR TELEVISION...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please select your wireless display or Smart TV in the system cast overlay.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontFamily: 'Outfit',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF070714),
      body: widget.isHost ? _buildHostLayout() : _buildClientLayout(),
    );
  }

  // --- HOST LAYOUTS (P1) ---

  Widget _buildHostLayout() {
    return _isPhysicalControllerActive ? _buildTelemetryHub() : _buildGamepadControls();
  }

  // --- CLIENT LAYOUTS (P2) ---

  Widget _buildClientLayout() {
    return _isPhysicalControllerActive ? _buildTelemetryHub() : _buildGamepadControls();
  }

  Widget _buildTelemetryHub() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.gamepad, size: 80, color: Color(0xFFFF2E93)),
          const SizedBox(height: 24),
          const Text(
            'TELEMETRY HUB',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 4.0,
              fontFamily: 'Outfit',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Core: ${_currentCoreName.toUpperCase()}  |  Status: ONLINE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
              fontFamily: 'Outfit',
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            icon: const Icon(Icons.menu),
            label: const Text('CONSOLE MENU'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E1E38),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              side: const BorderSide(color: Color(0xFFFF2E93), width: 2),
              textStyle: const TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1.2,
              ),
            ),
            onPressed: () {
              if (widget.isHost) {
                _togglePause();
                if (widget.engine != null && widget.engine!.isPaused) {
                  _showMenuOverlay();
                }
              } else {
                _showClientMenuOverlay();
              }
            },
          ),
        ],
      ),
    );
  }

  /// Core gamepad layout split into D-pad, System Panel, and Action cluster
  Widget _buildGamepadControls() {
    String cName = _currentCoreName.toLowerCase();
    bool isGenesis = cName.contains('genesis');
    bool isSnes = cName.contains('snes') || cName.contains('mgba');
    bool isPs1 = cName.contains('pcsx');

    return LayoutBuilder(
      builder: (context, constraints) {
        final double baseSize = (constraints.maxHeight * 0.22).clamp(40.0, 100.0);
        return Stack(
          children: [
            // Solid black background for pure controller experience
            Positioned.fill(
              child: Container(color: Colors.black),
            ),

            // Left shoulder buttons (L1/L2) — beside D-pad
            if (isSnes || isPs1)
              Positioned(
                left: 12,
                top: constraints.maxHeight * 0.35,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildShoulderButton(label: isPs1 ? 'L1' : 'L', buttonId: 10), // RETRO_DEVICE_ID_JOYPAD_L
                    if (isPs1) const SizedBox(height: 8),
                    if (isPs1) _buildShoulderButton(label: 'L2', buttonId: 12), // RETRO_DEVICE_ID_JOYPAD_L2
                  ],
                ),
              ),
            // Right shoulder buttons (R1/R2) — beside action buttons
            if (isSnes || isPs1)
              Positioned(
                right: 12,
                top: constraints.maxHeight * 0.35,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildShoulderButton(label: isPs1 ? 'R1' : 'R', buttonId: 11), // RETRO_DEVICE_ID_JOYPAD_R
                    if (isPs1) const SizedBox(height: 8),
                    if (isPs1) _buildShoulderButton(label: 'R2', buttonId: 13), // RETRO_DEVICE_ID_JOYPAD_R2
                  ],
                ),
              ),

            // Analog toggle
            Positioned(
              top: constraints.maxHeight * 0.08,
              left: constraints.maxWidth / 2 - 80,
              child: _buildAnalogToggle(),
            ),

            // Left & Right Controls
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left Side: D-pad or Analog
                  Padding(
                    padding: const EdgeInsets.only(left: 36),
                    child: Center(
                      child: _useAnalogStick 
                          ? _buildAnalogStick(baseSize * 3) 
                          : _buildDPad(baseSize),
                    ),
                  ),
                  // Right Side: Dynamic Action Cluster
                  Padding(
                    padding: const EdgeInsets.only(right: 36),
                    child: Center(
                      child: isGenesis ? _buildGenesisCluster(baseSize) :
                             isPs1 ? _buildPs1Cluster(baseSize) :
                             isSnes ? _buildSnesCluster(baseSize) :
                             _buildNesCluster(baseSize),
                    ),
                  ),
                ],
              ),
            ),

            // Center: System Keys (SELECT/MODE / START / MENU)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _buildSystemPanel(isGenesis),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildShoulderButton({required String label, required int buttonId}) {
    return Listener(
      onPointerDown: (_) {
        
        _handleButtonEvent(buttonId, true);
      },
      onPointerUp: (_) {
        _handleButtonEvent(buttonId, false);
      },
      onPointerCancel: (_) {
        _handleButtonEvent(buttonId, false);
      },
      child: Container(
        width: 48,
        height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E38),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalogToggle() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _useAnalogStick = !_useAnalogStick;
        });
      },
      child: Container(
        width: 160,
        height: 40,
        decoration: BoxDecoration(
          color: _useAnalogStick ? const Color(0xFFFF2E93).withValues(alpha: 0.2) : Colors.white12,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _useAnalogStick ? const Color(0xFFFF2E93) : Colors.white24,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _useAnalogStick ? Icons.gamepad : Icons.directions_walk,
              color: _useAnalogStick ? const Color(0xFFFF2E93) : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _useAnalogStick ? 'ANALOG ON' : 'D-PAD ON',
              style: TextStyle(
                color: _useAnalogStick ? const Color(0xFFFF2E93) : Colors.white54,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalogStick(double size) {
    double radius = size / 2;
    double knobRadius = size / 5;

    return GestureDetector(
      onPanStart: (details) {
        _updateAnalog(details.localPosition, radius);
      },
      onPanUpdate: (details) {
        _updateAnalog(details.localPosition, radius);
      },
      onPanEnd: (details) {
        setState(() {
          _analogStickPos = Offset.zero;
        });
        _handleAnalogEvent(0.0, 0.0);
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E38).withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Center(
          child: Transform.translate(
            offset: _analogStickPos,
            child: Container(
              width: knobRadius * 2,
              height: knobRadius * 2,
              decoration: BoxDecoration(
                color: const Color(0xFF14142B),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFF2E93), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF2E93).withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateAnalog(Offset localPosition, double radius) {
    // Map local position to a vector from the center
    Offset center = Offset(radius, radius);
    Offset delta = localPosition - center;

    // Clamp to circle
    double distance = delta.distance;
    if (distance > radius) {
      delta = Offset.fromDirection(delta.direction, radius);
    }

    setState(() {
      _analogStickPos = delta;
    });

    // Normalize for Libretro [-1.0, 1.0]
    double nx = delta.dx / radius;
    double ny = delta.dy / radius; // Libretro Y might be inverted depending on core, assuming standard Y down here
    _handleAnalogEvent(nx, ny);
  }

  void _handleAnalogEvent(double x, double y) {
    bool isPs1 = widget.coreName.toLowerCase().contains('pcsx');
    
    if (isPs1) {
      if (widget.isHost && widget.engine != null) {
        // Map [-1.0, 1.0] to [-0x7FFF, 0x7FFF]
        int ix = (x * 32767).round().clamp(-32767, 32767);
        int iy = (y * 32767).round().clamp(-32767, 32767);
        widget.engine!.updateAnalogState(0, 0, 0, ix);
        widget.engine!.updateAnalogState(0, 0, 1, iy); // 0=left stick, 1=right stick
      }
    } else {
      // Analog-to-D-pad Translation for older cores
      const double threshold = 0.5;
      
      int? newX;
      if (x < -threshold) {
        newX = RETRO_DEVICE_ID_JOYPAD_LEFT;  // 6
      } else if (x > threshold) {
        newX = RETRO_DEVICE_ID_JOYPAD_RIGHT; // 7
      }

      int? newY;
      if (y < -threshold) {
        newY = RETRO_DEVICE_ID_JOYPAD_UP;    // 4
      } else if (y > threshold) {
        newY = RETRO_DEVICE_ID_JOYPAD_DOWN;  // 5
      }
      
      // Release old buttons if they changed
      if (_activeAnalogDPadX != null && _activeAnalogDPadX != newX) {
        _handleButtonEvent(_activeAnalogDPadX!, false);
      }
      if (_activeAnalogDPadY != null && _activeAnalogDPadY != newY) {
        _handleButtonEvent(_activeAnalogDPadY!, false);
      }
      
      // Press new buttons if they changed
      if (newX != null && _activeAnalogDPadX != newX) {
        _handleButtonEvent(newX, true);
      }
      if (newY != null && _activeAnalogDPadY != newY) {
        _handleButtonEvent(newY, true);
      }
      
      _activeAnalogDPadX = newX;
      _activeAnalogDPadY = newY;
    }
  }

  Widget _buildDPad(double size) {
    return SizedBox(
      width: size * 3,
      height: size * 3,
      child: Stack(
        children: [
          // UP — RETRO_DEVICE_ID_JOYPAD_UP = 4
          Positioned(
            left: size,
            top: 0,
            child: _buildDPadDirection(label: '▲', buttonId: RETRO_DEVICE_ID_JOYPAD_UP, width: size, height: size),
          ),
          // DOWN — RETRO_DEVICE_ID_JOYPAD_DOWN = 5
          Positioned(
            left: size,
            top: size * 2,
            child: _buildDPadDirection(label: '▼', buttonId: RETRO_DEVICE_ID_JOYPAD_DOWN, width: size, height: size),
          ),
          // LEFT — RETRO_DEVICE_ID_JOYPAD_LEFT = 6
          Positioned(
            left: 0,
            top: size,
            child: _buildDPadDirection(label: '◀', buttonId: RETRO_DEVICE_ID_JOYPAD_LEFT, width: size, height: size),
          ),
          // RIGHT — RETRO_DEVICE_ID_JOYPAD_RIGHT = 7
          Positioned(
            left: size * 2,
            top: size,
            child: _buildDPadDirection(label: '▶', buttonId: RETRO_DEVICE_ID_JOYPAD_RIGHT, width: size, height: size),
          ),
          // CENTER CAP (Dead Zone)
          Positioned(
            left: size,
            top: size,
            child: Container(
              width: size,
              height: size,
              color: const Color(0xFF1E1E38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDPadDirection({
    required String label,
    required int buttonId,
    required double width,
    required double height,
  }) {
    return Listener(
      onPointerDown: (_) {
        
        _handleButtonEvent(buttonId, true);
      },
      onPointerUp: (_) {
        _handleButtonEvent(buttonId, false);
      },
      onPointerCancel: (_) {
        _handleButtonEvent(buttonId, false);
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF14142B),
          border: Border.all(color: Colors.white12, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemPanel(bool isGenesis) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!kReleaseMode) ...[
          _buildDebugTerminal(),
          const SizedBox(height: 24),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // SELECT = RETRO_DEVICE_ID_JOYPAD_SELECT (2)
            _buildSystemButton(label: isGenesis ? 'MODE' : 'SELECT', buttonId: RETRO_DEVICE_ID_JOYPAD_SELECT),
            const SizedBox(width: 16),
            // START = RETRO_DEVICE_ID_JOYPAD_START (3)
            _buildSystemButton(label: 'START', buttonId: RETRO_DEVICE_ID_JOYPAD_START),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.hostType != 'desktop')
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // MENU = MOJO_VIRTUAL_MENU (16) — app-internal only, never sent to core
              _buildSystemButton(label: 'MENU', buttonId: MOJO_VIRTUAL_MENU, isHotKey: true),
            ],
          ),
      ],
    );
  }

  Widget _buildDebugTerminal() {
    return Container(
      width: 168,
      height: 96,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF879E8B), // Classic Nokia green/gray
        border: Border.all(color: const Color(0xFF2C3E2D), width: 3),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF879E8B).withValues(alpha: 0.2),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: ValueListenableBuilder<List<String>>(
        valueListenable: ConsoleLogger.logs,
        builder: (context, logs, _) {
          return ListView.builder(
            reverse: true, // Display newest logs at bottom
            itemCount: logs.length,
            itemBuilder: (context, index) {
              // Since it's reversed, index 0 is the newest log at the bottom
              final logIdx = logs.length - 1 - index;
              return Text(
                logs[logIdx],
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 7,
                  color: Color(0xFF1B261C), // Dark Nokia LCD text color
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSystemButton({
    required String label,
    required int buttonId,
    bool isHotKey = false,
  }) {
    return Listener(
      onPointerDown: (_) {
        
        _handleButtonEvent(buttonId, true);
      },
      onPointerUp: (_) {
        _handleButtonEvent(buttonId, false);
      },
      onPointerCancel: (_) {
        _handleButtonEvent(buttonId, false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isHotKey ? const Color(0xFFFF2E93).withValues(alpha: 0.1) : const Color(0xFF1E1E38),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHotKey ? const Color(0xFFFF2E93).withValues(alpha: 0.5) : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isHotKey ? const Color(0xFFFF2E93) : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildNesCluster(double size) {
    return SizedBox(
      width: size * 2.5,
      height: size * 1.5,
      child: Stack(
        children: [
          // NES B → RetroPad B (bottom face) = 0
          Positioned(left: 0, top: size * 0.5, child: _buildGamepadButton(label: 'B', buttonId: RETRO_DEVICE_ID_JOYPAD_B, color: const Color(0xFFE57373), size: size)),
          // NES A → RetroPad A (right face) = 8
          Positioned(left: size * 1.2, top: 0, child: _buildGamepadButton(label: 'A', buttonId: RETRO_DEVICE_ID_JOYPAD_A, color: const Color(0xFF81C784), size: size)),
        ],
      ),
    );
  }

  Widget _buildSnesCluster(double size) {
    double spacing = size * 2.0;
    return SizedBox(
      width: size + spacing,
      height: size + spacing,
      child: Stack(
        children: [
          // SNES Y (left face)   → RetroPad Y = 1
          Positioned(left: 0, top: spacing / 2, child: _buildGamepadButton(label: 'Y', buttonId: RETRO_DEVICE_ID_JOYPAD_Y, color: const Color(0xFF81C784), size: size)),
          // SNES X (top face)    → RetroPad X = 9
          Positioned(left: spacing / 2, top: 0, child: _buildGamepadButton(label: 'X', buttonId: RETRO_DEVICE_ID_JOYPAD_X, color: const Color(0xFF4FC3F7), size: size)),
          // SNES A (right face)  → RetroPad A = 8
          Positioned(left: spacing, top: spacing / 2, child: _buildGamepadButton(label: 'A', buttonId: RETRO_DEVICE_ID_JOYPAD_A, color: const Color(0xFFE57373), size: size)),
          // SNES B (bottom face) → RetroPad B = 0
          Positioned(left: spacing / 2, top: spacing, child: _buildGamepadButton(label: 'B', buttonId: RETRO_DEVICE_ID_JOYPAD_B, color: const Color(0xFFFFD54F), size: size)),
        ],
      ),
    );
  }

  Widget _buildPs1Cluster(double size) {
    double spacing = size * 2.0;
    return SizedBox(
      width: size + spacing,
      height: size + spacing,
      child: Stack(
        children: [
          // □ Square (left face)    → RetroPad Y = 1
          Positioned(left: 0, top: spacing / 2, child: _buildGamepadButton(label: '□', buttonId: RETRO_DEVICE_ID_JOYPAD_Y, color: const Color(0xFFE91E63), size: size)),
          // △ Triangle (top face)   → RetroPad X = 9
          Positioned(left: spacing / 2, top: 0, child: _buildGamepadButton(label: '△', buttonId: RETRO_DEVICE_ID_JOYPAD_X, color: const Color(0xFF4CAF50), size: size)),
          // ○ Circle (right face)   → RetroPad A = 8
          Positioned(left: spacing, top: spacing / 2, child: _buildGamepadButton(label: '○', buttonId: RETRO_DEVICE_ID_JOYPAD_A, color: const Color(0xFFF44336), size: size)),
          // ✕ Cross (bottom face)   → RetroPad B = 0
          Positioned(left: spacing / 2, top: spacing, child: _buildGamepadButton(label: '✕', buttonId: RETRO_DEVICE_ID_JOYPAD_B, color: const Color(0xFF2196F3), size: size)),
        ],
      ),
    );
  }

  Widget _buildGenesisCluster(double size) {
    double xSpacing = size * 1.15;
    double ySpacing = size;
    return SizedBox(
      width: size + xSpacing * 2,
      height: size + ySpacing,
      child: Stack(
        children: [
          // Top Row: X, Y, Z — Genesis top 3 buttons
          // Genesis X → RetroPad L1 = 10
          Positioned(left: 0, top: 0, child: _buildGamepadButton(label: 'X', buttonId: RETRO_DEVICE_ID_JOYPAD_L, color: Colors.grey.shade400, size: size)),
          // Genesis Y → RetroPad X (top face) = 9
          Positioned(left: xSpacing, top: 0, child: _buildGamepadButton(label: 'Y', buttonId: RETRO_DEVICE_ID_JOYPAD_X, color: Colors.grey.shade400, size: size)),
          // Genesis Z → RetroPad R1 = 11
          Positioned(left: xSpacing * 2, top: 0, child: _buildGamepadButton(label: 'Z', buttonId: RETRO_DEVICE_ID_JOYPAD_R, color: Colors.grey.shade400, size: size)),
          // Bottom Row: A, B, C — Genesis main face buttons
          // Genesis A → RetroPad Y (left face) = 1
          Positioned(left: 0, top: ySpacing, child: _buildGamepadButton(label: 'A', buttonId: RETRO_DEVICE_ID_JOYPAD_Y, color: const Color(0xFFE57373), size: size)),
          // Genesis B → RetroPad B (bottom face) = 0
          Positioned(left: xSpacing, top: ySpacing, child: _buildGamepadButton(label: 'B', buttonId: RETRO_DEVICE_ID_JOYPAD_B, color: const Color(0xFF81C784), size: size)),
          // Genesis C → RetroPad A (right face) = 8
          Positioned(left: xSpacing * 2, top: ySpacing, child: _buildGamepadButton(label: 'C', buttonId: RETRO_DEVICE_ID_JOYPAD_A, color: const Color(0xFF4FC3F7), size: size)),
        ],
      ),
    );
  }

  Widget _buildGamepadButton({
    required String label,
    required int buttonId,
    required Color color,
    required double size,
  }) {
    return Listener(
      onPointerDown: (_) {
        
        _handleButtonEvent(buttonId, true);
      },
      onPointerUp: (_) {
        _handleButtonEvent(buttonId, false);
      },
      onPointerCancel: (_) {
        _handleButtonEvent(buttonId, false);
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2.5),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }



}

/*
--------------------------------------------------------------------------------
DUAL SCREEN NATIVE PROJECTION GUIDE (FOR IOS & ANDROID INTEGRATIONS)
--------------------------------------------------------------------------------

1. ANDROID: Implementing DisplayManager & Presentation
In your Android Host Project, locate `android/app/src/main/kotlin/.../MainActivity.kt` and register:

```kotlin
package dev.seven_cgpalabs.mojosnap

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "dev.seven_cgpalabs.mojosnap/projection"
    private var presentationDialog: android.app.Presentation? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState: Bundle?)
        
        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTVProjection" -> {
                    val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
                    val displays = displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
                    if (displays.isNotEmpty()) {
                        val externalDisplay = displays[0]
                        
                        // Spawn a custom presentation dialog pinned to the external wireless/wired monitor
                        presentationDialog = object : android.app.Presentation(this, externalDisplay) {
                            override fun onCreate(savedInstanceState: Bundle?) {
                                super.onCreate(savedInstanceState)
                                // Assign the TV projection layout context
                                // You can embed a FlutterImageView connected to a secondary shared engine here
                                setContentView(R.layout.presentation_tv_layout)
                            }
                        }
                        presentationDialog?.show()
                        result.success(true)
                    } else {
                        result.error("NO_DISPLAY", "No external display found", null)
                    }
                }
                "stopTVProjection" -> {
                    presentationDialog?.dismiss()
                    presentationDialog = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
```

2. IOS: Implementing UIWindow & UIScreen Notifications
In your iOS Host Project, locate `ios/Runner/AppDelegate.swift` and register:

```swift
import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private var externalWindow: UIWindow?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: "dev.seven_cgpalabs.mojosnap/projection",
                                           binaryMessenger: controller.binaryMessenger)
        
        channel.setMethodCallHandler { (call, result) in
            if call.method == "startTVProjection" {
                self.setupExternalScreen()
                result(true)
            } else if call.method == "stopTVProjection" {
                self.externalWindow = nil
                result(true)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
        
        // Listen for screen connect notifications (AirPlay/HDMI plug)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidConnect),
            name: UIScreen.didConnectNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidDisconnect),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    @objc private func screenDidConnect(notification: Notification) {
        setupExternalScreen()
    }
    
    @objc private func screenDidDisconnect(notification: Notification) {
        externalWindow = nil
    }
    
    private func setupExternalScreen() {
        // Stop if screen is not connected or secondary screen is missing
        guard UIScreen.screens.count > 1 else { return }
        let secondaryScreen = UIScreen.screens[1]
        
        // Allocate secondary screen window
        let windowFrame = secondaryScreen.bounds
        externalWindow = UIWindow(frame: windowFrame)
        externalWindow?.screen = secondaryScreen
        
        // Create secondary shared Flutter engine or presentation controller
        let externalViewController = UIViewController()
        externalViewController.view.backgroundColor = .black
        
        // Render secondary TV layout viewport on external screen
        externalWindow?.rootViewController = externalViewController
        externalWindow?.isHidden = false
    }
}
```
*/
