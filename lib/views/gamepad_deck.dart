import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../network/host_server.dart';
import '../network/client_socket.dart';
import '../emulation/libretro.dart';

class GamepadDeck extends StatefulWidget {
  final bool isHost;
  final LibretroEngine? engine;
  final String romName;

  const GamepadDeck({
    super.key,
    required this.isHost,
    this.engine,
    required this.romName,
  });

  @override
  State<GamepadDeck> createState() => _GamepadDeckState();
}

class _GamepadDeckState extends State<GamepadDeck> with WidgetsBindingObserver {
  static const MethodChannel _projectionChannel = MethodChannel('com.retromesh.console/projection');
  
  bool _isCasting = false; // Track if cast dialog presentation is active
  bool _isConnectingTV = false; // Track if waiting for OS Cast dialog to return

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 1. Lock screen orientation to Landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // 2. Prevent mobile OS from sleeping or throttling priority threads
    WakelockPlus.enable();

    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    if (widget.isHost) {
      _isConnectingTV = true;
      _checkPreConnectedDisplay();
    }
  }

  DateTime? _lastFrameTime;

  void _onFrameGenerated() {
    if (_isCasting) {
      final now = DateTime.now();
      if (_lastFrameTime != null && now.difference(_lastFrameTime!).inMilliseconds < 33) {
        return; // Throttle TV broadcast to 30 FPS to prevent GC stutter
      }
      _lastFrameTime = now;
      
      final frame = widget.engine?.rawFrameNotifier.value;
      if (frame != null) {
        _projectionChannel.invokeMethod('sendFrame', frame);
      }
    }
  }

  void _checkPreConnectedDisplay() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      _startNativeTVProjection().then((connected) {
        if (connected && mounted) {
          setState(() {
            _isConnectingTV = false;
            _isCasting = true;
          });
          widget.engine?.currentFrameNotifier.addListener(_onFrameGenerated);
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isHost && _isConnectingTV) {
      _startNativeTVProjection().then((connected) {
        if (!connected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFEF4444),
              content: Text(
                'No wireless display selected. Emulation exited.',
                style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          );
          _exitGame(context);
        } else {
          setState(() {
            _isConnectingTV = false;
            _isCasting = true;
          });
          widget.engine?.rawFrameNotifier.addListener(_onFrameGenerated);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    if (widget.isHost) {
      widget.engine?.rawFrameNotifier.removeListener(_onFrameGenerated);
    }
    // Restore orientation settings
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    WakelockPlus.disable();

    if (widget.isHost) {
      _stopNativeTVProjection();
      widget.engine?.shutdown();
      HostServer.instance.stop();
    } else {
      ClientSocket.instance.disconnect();
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
    if (buttonId == 11) { // MENU
      if (pressed && widget.isHost) {
        _togglePause();
        if (widget.engine!.isPaused) {
          _showMenuOverlay();
        }
      }
      return;
    }

    if (widget.isHost) {
      // Local Host maps directly to Port 1 (index 0) in Libretro
      widget.engine?.updateButtonState(0, buttonId, pressed);
    } else {
      // Client maps to Port 2 (index 1) by sending over WebSocket
      ClientSocket.instance.sendButtonInput(buttonId, pressed);
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyUpEvent) {
      final pressed = event is KeyDownEvent;
      final key = event.logicalKey;
      int? buttonId;
      
      if (key == LogicalKeyboardKey.arrowUp) buttonId = 1;
      else if (key == LogicalKeyboardKey.arrowDown) buttonId = 2;
      else if (key == LogicalKeyboardKey.arrowLeft) buttonId = 3;
      else if (key == LogicalKeyboardKey.arrowRight) buttonId = 4;
      else if (key == LogicalKeyboardKey.gameButtonA || key == LogicalKeyboardKey.keyX) buttonId = 5;
      else if (key == LogicalKeyboardKey.gameButtonB || key == LogicalKeyboardKey.keyZ) buttonId = 6;
      else if (key == LogicalKeyboardKey.gameButtonX || key == LogicalKeyboardKey.keyS) buttonId = 7;
      else if (key == LogicalKeyboardKey.gameButtonY || key == LogicalKeyboardKey.keyA) buttonId = 8;
      else if (key == LogicalKeyboardKey.gameButtonStart || key == LogicalKeyboardKey.enter) buttonId = 9;
      else if (key == LogicalKeyboardKey.gameButtonSelect || key == LogicalKeyboardKey.space) buttonId = 10;
      else if (key == LogicalKeyboardKey.gameButtonMode || key == LogicalKeyboardKey.escape) buttonId = 11;
      else if (key == LogicalKeyboardKey.gameButtonLeft1 || key == LogicalKeyboardKey.keyQ) buttonId = 12;
      else if (key == LogicalKeyboardKey.gameButtonRight1 || key == LogicalKeyboardKey.keyE) buttonId = 13;
      else if (key == LogicalKeyboardKey.gameButtonLeft2 || key == LogicalKeyboardKey.digit1) buttonId = 14;
      else if (key == LogicalKeyboardKey.gameButtonRight2 || key == LogicalKeyboardKey.digit3) buttonId = 15;
      
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
        widget.engine!.isPaused = !widget.engine!.isPaused;
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.menu, color: Color(0xFFFF2E93)),
            const SizedBox(width: 10),
            const Text(
              'CONSOLE MENU',
              style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Colors.white70),
              title: const Text('Resume Game', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
              onTap: () {
                Navigator.pop(ctx);
                if (widget.engine!.isPaused) {
                  _togglePause();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.white70),
              title: const Text('Reset Game', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
              onTap: () {
                Navigator.pop(ctx);
                if (widget.engine != null) {
                  widget.engine!.initializeCore(''); // Reset
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Resetting Game...')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Color(0xFFEF4444)),
              title: const Text('Exit to Main Menu', style: TextStyle(color: Color(0xFFEF4444), fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(ctx);
                _exitGame(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _exitGame(BuildContext context) {
    if (widget.isHost) {
      _stopNativeTVProjection();
      widget.engine?.shutdown();
      HostServer.instance.stop();
    } else {
      ClientSocket.instance.disconnect();
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
                  color: const Color(0xFFFF2E93).withOpacity(0.08),
                  border: Border.all(color: const Color(0xFFFF2E93).withOpacity(0.3), width: 1.5),
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
                  color: Colors.white.withOpacity(0.5),
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
    return ValueListenableBuilder<CombinedTelemetry>(
      valueListenable: HostServer.instance.telemetryNotifier,
      builder: (context, telemetry, child) {
        return SafeArea(
          child: Column(
            children: [
              _buildHeaderBar(
                title: 'CONSOLE HOST • PORT 1',
                subtitle: widget.romName,
                color: const Color(0xFFFF2E93),
                extraActions: [
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1E1E38),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Exit Game', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                          content: const Text('Are you sure you want to exit? This will stop the emulation and disconnect all players.', style: TextStyle(color: Colors.white70, fontFamily: 'Outfit')),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('CANCEL', style: TextStyle(color: Colors.white38)),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _exitGame(context);
                              },
                              child: const Text('EXIT', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.exit_to_app, color: Color(0xFFEF4444), size: 16),
                    label: const Text(
                      'EXIT GAME',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: _buildGamepadControls(),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- CLIENT LAYOUTS (P2) ---

  Widget _buildClientLayout() {
    return ValueListenableBuilder<String>(
      valueListenable: ClientSocket.instance.connectionStatusNotifier,
      builder: (context, status, child) {
        if (status == 'Connected') {
          return SafeArea(
            child: Column(
              children: [
                _buildHeaderBar(
                  title: 'CLIENT SQUAD CONTROLLER • PORT 2',
                  subtitle: 'WebSocket Connected • Low Latency Mode',
                  color: const Color(0xFF00E5FF),
                  extraActions: [
                    TextButton.icon(
                      onPressed: () {
                        ClientSocket.instance.disconnect();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.exit_to_app, color: Color(0xFFEF4444), size: 16),
                      label: const Text(
                        'DISCONNECT',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: _buildGamepadControls(),
                ),
              ],
            ),
          );
        } else {
          // Connecting / Scanning screen
          return _buildClientScanningScreen(status);
        }
      },
    );
  }

  Widget _buildClientScanningScreen(String status) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00E5FF).withOpacity(0.08),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1.5),
              ),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              status,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Make sure both devices are connected to the same Wi-Fi network. Auto-discovery will connect you automatically.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                ClientSocket.instance.disconnect();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1E38),
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'Cancel & Return Gate',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- REUSABLE UI BLOCKS ---

  Widget _buildHeaderBar({
    required String title,
    required String subtitle,
    required Color color,
    List<Widget> extraActions = const [],
  }) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F28),
        border: Border(
          bottom: BorderSide(color: Colors.white12, width: 1.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '|  $subtitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(children: extraActions),
        ],
      ),
    );
  }

  /// Core gamepad layout split into D-pad, System Panel, and ABXY cluster
  Widget _buildGamepadControls() {
    return Stack(
      children: [
        // Left Side: D-pad
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 36),
            child: _buildDPad(),
          ),
        ),

        // Right Side: ABXY Cluster
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 36),
            child: _buildABXYCluster(),
          ),
        ),

        // Center: System Keys (SELECT / START / MENU / PAUSE)
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: _buildSystemPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildDPad() {
    const double size = 72;
    return SizedBox(
      width: size * 3,
      height: size * 3,
      child: Stack(
        children: [
          // UP
          Positioned(
            left: size,
            top: 0,
            child: _buildDPadDirection(label: '▲', buttonId: 1, width: size, height: size),
          ),
          // DOWN
          Positioned(
            left: size,
            top: size * 2,
            child: _buildDPadDirection(label: '▼', buttonId: 2, width: size, height: size),
          ),
          // LEFT
          Positioned(
            left: 0,
            top: size,
            child: _buildDPadDirection(label: '◀', buttonId: 3, width: size, height: size),
          ),
          // RIGHT
          Positioned(
            left: size * 2,
            top: size,
            child: _buildDPadDirection(label: '▶', buttonId: 4, width: size, height: size),
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
        HapticFeedback.lightImpact();
        _handleButtonEvent(buttonId, true);
      },
      onPointerUp: (_) {
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

  Widget _buildSystemPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSystemButton(label: 'SELECT', buttonId: 10),
            const SizedBox(width: 16),
            _buildSystemButton(label: 'START', buttonId: 9),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSystemButton(label: 'MENU', buttonId: 11, isHotKey: true),
          ],
        ),
      ],
    );
  }

  Widget _buildSystemButton({
    required String label,
    required int buttonId,
    bool isHotKey = false,
  }) {
    return Listener(
      onPointerDown: (_) {
        HapticFeedback.lightImpact();
        _handleButtonEvent(buttonId, true);
      },
      onPointerUp: (_) {
        _handleButtonEvent(buttonId, false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isHotKey ? const Color(0xFFFF2E93).withOpacity(0.1) : const Color(0xFF1E1E38),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHotKey ? const Color(0xFFFF2E93).withOpacity(0.5) : Colors.white24,
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

  Widget _buildABXYCluster() {
    const double size = 64;
    const double spacing = 128;
    return SizedBox(
      width: size + spacing,
      height: size + spacing,
      child: Stack(
        children: [
          // Y
          Positioned(
            left: 0,
            top: spacing / 2,
            child: _buildGamepadButton(label: 'Y', buttonId: 8, color: const Color(0xFFFFD54F), size: size),
          ),
          // X
          Positioned(
            left: spacing / 2,
            top: 0,
            child: _buildGamepadButton(label: 'X', buttonId: 7, color: const Color(0xFF4FC3F7), size: size),
          ),
          // A
          Positioned(
            left: spacing,
            top: spacing / 2,
            child: _buildGamepadButton(label: 'A', buttonId: 5, color: const Color(0xFF81C784), size: size),
          ),
          // B
          Positioned(
            left: spacing / 2,
            top: spacing,
            child: _buildGamepadButton(label: 'B', buttonId: 6, color: const Color(0xFFE57373), size: size),
          ),
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
        HapticFeedback.lightImpact();
        _handleButtonEvent(buttonId, true);
      },
      onPointerUp: (_) {
        _handleButtonEvent(buttonId, false);
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
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

  // --- TV RENDERING VIEWPORT & HUD BAR ---

  Widget _buildTVViewport(CombinedTelemetry telemetry) {
    if (widget.engine == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            'NO ENGINE ASSIGNED',
            style: TextStyle(color: Colors.white30, fontSize: 12),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF030308),
      child: Column(
        children: [
          // Upper frame: Emulator Output
          Expanded(
            child: ValueListenableBuilder<ui.Image?>(
              valueListenable: widget.engine!.currentFrameNotifier,
              builder: (context, frame, child) {
                return CustomPaint(
                  painter: EmulationCanvasPainter(frame),
                  child: Container(),
                );
              },
            ),
          ),
          
          // Bottom 80px: Telemetry HUD Bar
          Container(
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFF0B0B1D),
              border: Border(
                top: BorderSide(color: Colors.white12, width: 1.5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // P1 Host status
                _buildTelemetryNode(
                  playerLabel: 'P1 CONSOLE',
                  connected: telemetry.p1Connected,
                  battery: telemetry.p1Battery,
                  wifi: telemetry.p1Wifi,
                  color: const Color(0xFFFF2E93),
                ),

                const SizedBox(width: 8),

                // Core Name / Engine Mode Info
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.engine!.isMockMode ? 'SIMULATOR MODE' : 'HARDWARE FFI MODE',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      ValueListenableBuilder<String>(
                        valueListenable: widget.engine!.logNotifier,
                        builder: (context, log, child) {
                          return Text(
                            log,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.35),
                              fontSize: 8,
                              fontFamily: 'monospace',
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // P2 Client status
                _buildTelemetryNode(
                  playerLabel: 'P2 CONTROLLER',
                  connected: telemetry.p2Connected,
                  battery: telemetry.p2Battery,
                  wifi: telemetry.p2Wifi,
                  color: const Color(0xFF00E5FF),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryNode({
    required String playerLabel,
    required bool connected,
    required int battery,
    required String wifi,
    required Color color,
  }) {
    final statusColor = connected ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor,
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(0.5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              playerLabel,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.battery_std, size: 11, color: Colors.white.withOpacity(0.5)),
                const SizedBox(width: 2),
                Text(
                  connected ? '$battery%' : '--',
                  style: TextStyle(
                    color: connected ? Colors.white : Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.wifi, size: 11, color: Colors.white.withOpacity(0.5)),
                const SizedBox(width: 2),
                Text(
                  connected ? wifi : '--',
                  style: TextStyle(
                    color: connected ? Colors.white : Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          ],
        )
      ],
    );
  }
}

// --- DUAL-SCREEN EMULATION CANVAS PAINTER ---

class EmulationCanvasPainter extends CustomPainter {
  final ui.Image? image;
  EmulationCanvasPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) {
      // Paint static grid loading layout
      final paint = Paint()..color = const Color(0xFF04040A);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'AWAITING EMULATION OUTPUT...',
          style: TextStyle(
            color: Colors.white12,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
            fontFamily: 'Outfit',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
      return;
    }

    final double srcW = image!.width.toDouble();
    final double srcH = image!.height.toDouble();
    final double dstW = size.width;
    final double dstH = size.height;

    // Aspect ratio fitting calculations
    final double scale = (dstW / srcW < dstH / srcH) ? dstW / srcW : dstH / srcH;
    final double w = srcW * scale;
    final double h = srcH * scale;
    final double x = (dstW - w) / 2;
    final double y = (dstH - h) / 2;

    // Use FilterQuality.none for crisp non-blurred pixel layouts (NES/SNES/Genesis style)
    canvas.drawImageRect(
      image!,
      Rect.fromLTWH(0, 0, srcW, srcH),
      Rect.fromLTWH(x, y, w, h),
      Paint()..filterQuality = ui.FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(covariant EmulationCanvasPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

/*
--------------------------------------------------------------------------------
DUAL SCREEN NATIVE PROJECTION GUIDE (FOR IOS & ANDROID INTEGRATIONS)
--------------------------------------------------------------------------------

1. ANDROID: Implementing DisplayManager & Presentation
In your Android Host Project, locate `android/app/src/main/kotlin/.../MainActivity.kt` and register:

```kotlin
package com.retromesh.retro_mesh_console

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.retromesh.console/projection"
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
        let channel = FlutterMethodChannel(name: "com.retromesh.console/projection",
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
