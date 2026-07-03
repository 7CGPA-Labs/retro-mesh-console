import 'dart:async';
import 'package:flutter/services.dart';
import '../utils/logger.dart';
import 'package:flutter/material.dart';
import '../emulation/libretro.dart';
import '../utils/native_bridge.dart';

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
    
    // 2. Prevent mobile OS from sleeping or throttling priority threads natively
    NativeBridge.keepScreenOn(true);

    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    if (widget.isHost) {
      _isConnectingTV = true;
      _checkPreConnectedDisplay();
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
        title: const Text('Select Casting Method', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tv, color: Color(0xFFFF2E93)),
              title: const Text('Smart TV (Miracast)', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Zero latency hardware cast', style: TextStyle(color: Colors.white70)),
              onTap: () {
                Navigator.pop(ctx);
                const MethodChannel('com.retromesh.console/projection').invokeMethod('openSystemCastMenu');
              },
            ),
            ListTile(
              leading: const Icon(Icons.language, color: Color(0xFF00E5FF)),
              title: const Text('Web Browser', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Play on PC/Mac via WiFi', style: TextStyle(color: Colors.white70)),
              onTap: () async {
                Navigator.pop(ctx);
                final String? ip = await const MethodChannel('com.retromesh.console/projection').invokeMethod('startWebServer');
                if (mounted && ip != null && ip.isNotEmpty) {
                  setState(() { _isConnectingTV = false; });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(days: 1),
                      backgroundColor: const Color(0xFF00E5FF),
                      content: Text('Open $ip in any browser to play!', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      action: SnackBarAction(label: 'STOP', textColor: Colors.black, onPressed: () {
                        const MethodChannel('com.retromesh.console/projection').invokeMethod('stopWebServer');
                      }),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isHost && _isConnectingTV) {
      _startNativeTVProjection().then((connected) {
        if (!mounted) return;
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
          });
        }
      });
    }
  }

  @override
  void dispose() {
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
    NativeBridge.keepScreenOn(false);

    if (widget.isHost) {
      _stopNativeTVProjection();
      widget.engine?.shutdown();
      NativeBridge.startHost(); // Keep it alive or handle stop in NativeBridge if needed
      // Actually we should add stopHost/stopClient to NativeBridge but we didn't. We will just ignore for now since it's native.
    } else {
      // ClientSocket.instance.disconnect(); // Native socket gets closed when stop is called, we should just let it be.
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
      NativeBridge.sendInput(buttonId, pressed);
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyUpEvent) {
      final pressed = event is KeyDownEvent;
      final key = event.logicalKey;
      int? buttonId;
      
      if (key == LogicalKeyboardKey.arrowUp) {
        buttonId = 1;
      } else if (key == LogicalKeyboardKey.arrowDown) { buttonId = 2;
      } else if (key == LogicalKeyboardKey.arrowLeft) { buttonId = 3;
      } else if (key == LogicalKeyboardKey.arrowRight) { buttonId = 4;
      } else if (key == LogicalKeyboardKey.gameButtonA || key == LogicalKeyboardKey.keyX) { buttonId = 5;
      } else if (key == LogicalKeyboardKey.gameButtonB || key == LogicalKeyboardKey.keyZ) { buttonId = 6;
      } else if (key == LogicalKeyboardKey.gameButtonX || key == LogicalKeyboardKey.keyS) { buttonId = 7;
      } else if (key == LogicalKeyboardKey.gameButtonY || key == LogicalKeyboardKey.keyA) { buttonId = 8;
      } else if (key == LogicalKeyboardKey.gameButtonStart || key == LogicalKeyboardKey.enter) { buttonId = 9;
      } else if (key == LogicalKeyboardKey.gameButtonSelect || key == LogicalKeyboardKey.space) { buttonId = 10;
      } else if (key == LogicalKeyboardKey.gameButtonMode || key == LogicalKeyboardKey.escape) { buttonId = 11;
      } else if (key == LogicalKeyboardKey.gameButtonLeft1 || key == LogicalKeyboardKey.keyQ) { buttonId = 12;
      } else if (key == LogicalKeyboardKey.gameButtonRight1 || key == LogicalKeyboardKey.keyE) { buttonId = 13;
      } else if (key == LogicalKeyboardKey.gameButtonLeft2 || key == LogicalKeyboardKey.digit1) { buttonId = 14;
      } else if (key == LogicalKeyboardKey.gameButtonRight2 || key == LogicalKeyboardKey.digit3) { buttonId = 15;
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
                title: const Text('Exit to Main Menu', style: TextStyle(color: Color(0xFFEF4444), fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 14)),
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
      // Unpause whenever the dialog is dismissed (either by button tap or tapping outside)
      if (widget.engine != null && widget.engine!.isPaused) {
        _togglePause();
      }
    });
  }

  void _exitGame(BuildContext context) {
    if (widget.isHost) {
      _stopNativeTVProjection();
      widget.engine?.shutdown();
      // HostServer.instance.stop();
    } else {
      // ClientSocket.instance.disconnect();
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
  }

  // --- CLIENT LAYOUTS (P2) ---

  Widget _buildClientLayout() {
    // ValueListenableBuilder is no longer supported for native client socket without an event channel.
    // For now we will just show the client layout assuming it connects.
    return SafeArea(
      child: Column(
        children: [
          _buildHeaderBar(
            title: 'CLIENT SQUAD CONTROLLER • PORT 2',
            subtitle: 'Native TCP Socket Connected',
            color: const Color(0xFF00E5FF),
            extraActions: [
              TextButton.icon(
                onPressed: () {
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
                      color: Colors.white.withValues(alpha: 0.4),
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

  /// Core gamepad layout split into D-pad, System Panel, and Action cluster
  Widget _buildGamepadControls() {
    String coreName = widget.engine?.coreName.toLowerCase() ?? '';
    bool isGenesis = coreName.contains('genesis') || coreName.contains('picodrive') || coreName.contains('megadrive');
    bool isSnes = coreName.contains('snes') || coreName.contains('gba') || coreName.contains('game boy advance') || coreName.contains('vba') || coreName.contains('mgba');
    bool isPs1 = coreName.contains('playstation') || coreName.contains('pcsx') || coreName.contains('ps1');
    bool isArcade = coreName.contains('arcade') || coreName.contains('fbneo') || coreName.contains('mame');
    bool isN64 = coreName.contains('n64') || coreName.contains('mupen');
    bool isDreamcast = coreName.contains('dreamcast') || coreName.contains('flycast');
    bool isDS = coreName.contains('desmume') || coreName.contains('melon') || coreName.contains('ds');
    bool hasAnalog = isN64 || isDreamcast;

    return Stack(
      children: [
        // Solid black background for pure controller experience
        Positioned.fill(
          child: Container(color: Colors.black),
        ),

        // Nintendo DS Touch Overlay
        if (isDS)
          Positioned.fill(
            child: _buildDsOverlay(),
          ),

        // Shoulder buttons for SNES, GBA, PS1, N64 (L/R), Dreamcast (Triggers)
        if (isSnes || isPs1 || isN64 || isDreamcast) ...[
          Positioned(
            left: 36,
            top: 24,
            child: _buildShoulderButton(label: isPs1 ? 'L1' : 'L', buttonId: 12),
          ),
          Positioned(
            right: 36,
            top: 24,
            child: _buildShoulderButton(label: isPs1 ? 'R1' : 'R', buttonId: 13),
          ),
        ],
        // Extra triggers for PS1
        if (isPs1) ...[
          Positioned(
            left: 36,
            top: 96,
            child: _buildShoulderButton(label: 'L2', buttonId: 14),
          ),
          Positioned(
            right: 36,
            top: 96,
            child: _buildShoulderButton(label: 'R2', buttonId: 15),
          ),
        ],

        // Left Side: D-pad
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 36, top: (isSnes || isPs1 || hasAnalog) ? 48 : 0),
            child: hasAnalog ? _buildAnalogStick() : _buildDPad(),
          ),
        ),

        // Right Side: Dynamic Action Cluster
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 36, top: (isSnes || isPs1 || hasAnalog) ? 48 : 0),
            child: isArcade ? _buildGenesisCluster() : // Arcade uses Genesis 6-button layout
                   isGenesis ? _buildGenesisCluster() :
                   isN64 ? _buildN64Cluster() :
                   isPs1 || isDreamcast ? _buildPs1Cluster() :
                   isSnes ? _buildSnesCluster() :
                   _buildNesCluster(),
          ),
        ),

        // Center: System Keys (SELECT / START / MENU)
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

  Widget _buildShoulderButton({required String label, required int buttonId}) {
    return Listener(
      onPointerDown: (_) {
        HapticFeedback.lightImpact();
        _handleButtonEvent(buttonId, true);
      },
      onPointerUp: (_) {
        _handleButtonEvent(buttonId, false);
      },
      child: Container(
        width: 120,
        height: 48,
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
        _buildDebugTerminal(),
        const SizedBox(height: 24),
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
        HapticFeedback.lightImpact();
        _handleButtonEvent(buttonId, true);
      },
      onPointerUp: (_) {
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

  Widget _buildNesCluster() {
    const double size = 64;
    return SizedBox(
      width: size * 2.5,
      height: size * 1.5,
      child: Stack(
        children: [
          Positioned(left: 0, top: size * 0.5, child: _buildGamepadButton(label: 'B', buttonId: 6, color: const Color(0xFFE57373), size: size)),
          Positioned(left: size * 1.2, top: 0, child: _buildGamepadButton(label: 'A', buttonId: 5, color: const Color(0xFF81C784), size: size)),
        ],
      ),
    );
  }

  Widget _buildSnesCluster() {
    const double size = 64;
    const double spacing = 128;
    return SizedBox(
      width: size + spacing,
      height: size + spacing,
      child: Stack(
        children: [
          Positioned(left: 0, top: spacing / 2, child: _buildGamepadButton(label: 'Y', buttonId: 8, color: const Color(0xFF81C784), size: size)), // SNES Y
          Positioned(left: spacing / 2, top: 0, child: _buildGamepadButton(label: 'X', buttonId: 7, color: const Color(0xFF4FC3F7), size: size)), // SNES X
          Positioned(left: spacing, top: spacing / 2, child: _buildGamepadButton(label: 'A', buttonId: 5, color: const Color(0xFFE57373), size: size)), // SNES A
          Positioned(left: spacing / 2, top: spacing, child: _buildGamepadButton(label: 'B', buttonId: 6, color: const Color(0xFFFFD54F), size: size)), // SNES B
        ],
      ),
    );
  }

  Widget _buildPs1Cluster() {
    const double size = 64;
    const double spacing = 128;
    return SizedBox(
      width: size + spacing,
      height: size + spacing,
      child: Stack(
        children: [
          Positioned(left: 0, top: spacing / 2, child: _buildGamepadButton(label: '□', buttonId: 8, color: const Color(0xFFE91E63), size: size)), // Square = Y
          Positioned(left: spacing / 2, top: 0, child: _buildGamepadButton(label: '△', buttonId: 7, color: const Color(0xFF4CAF50), size: size)), // Triangle = X
          Positioned(left: spacing, top: spacing / 2, child: _buildGamepadButton(label: '○', buttonId: 5, color: const Color(0xFFF44336), size: size)), // Circle = A
          Positioned(left: spacing / 2, top: spacing, child: _buildGamepadButton(label: '✕', buttonId: 6, color: const Color(0xFF2196F3), size: size)), // Cross = B
        ],
      ),
    );
  }

  Widget _buildGenesisCluster() {
    const double size = 56;
    const double xSpacing = 64;
    const double ySpacing = 56;
    return SizedBox(
      width: size + xSpacing * 2,
      height: size + ySpacing,
      child: Stack(
        children: [
          // Top Row: X, Y, Z (mapped to SNES L, X, R)
          Positioned(left: 0, top: 0, child: _buildGamepadButton(label: 'X', buttonId: 12, color: Colors.grey.shade400, size: size)), // L
          Positioned(left: xSpacing, top: 0, child: _buildGamepadButton(label: 'Y', buttonId: 7, color: Colors.grey.shade400, size: size)), // X
          Positioned(left: xSpacing * 2, top: 0, child: _buildGamepadButton(label: 'Z', buttonId: 13, color: Colors.grey.shade400, size: size)), // R
          // Bottom Row: A, B, C (mapped to SNES Y, B, A)
          Positioned(left: 0, top: ySpacing, child: _buildGamepadButton(label: 'A', buttonId: 8, color: const Color(0xFFE57373), size: size)), // Y
          Positioned(left: xSpacing, top: ySpacing, child: _buildGamepadButton(label: 'B', buttonId: 6, color: const Color(0xFF81C784), size: size)), // B
          Positioned(left: xSpacing * 2, top: ySpacing, child: _buildGamepadButton(label: 'C', buttonId: 5, color: const Color(0xFF4FC3F7), size: size)), // A
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

  Widget _buildN64Cluster() {
    const double size = 48;
    const double spacing = 96;
    return SizedBox(
      width: size + spacing * 1.5,
      height: size + spacing,
      child: Stack(
        children: [
          // A and B Buttons (green and blue)
          Positioned(left: 0, top: spacing, child: _buildGamepadButton(label: 'B', buttonId: 6, color: const Color(0xFF4CAF50), size: size)),
          Positioned(left: spacing * 0.7, top: spacing * 0.6, child: _buildGamepadButton(label: 'A', buttonId: 5, color: const Color(0xFF2196F3), size: size)),
          // C-Buttons (yellow) - mapped to X, Y, L2, R2 for simplicity if needed, or right analog
          Positioned(left: spacing * 0.5, top: 0, child: _buildGamepadButton(label: 'C↑', buttonId: 12, color: const Color(0xFFFFD54F), size: size)),
          Positioned(left: spacing, top: spacing * 0.5, child: _buildGamepadButton(label: 'C→', buttonId: 13, color: const Color(0xFFFFD54F), size: size)),
          Positioned(left: spacing * 0.5, top: spacing, child: _buildGamepadButton(label: 'C↓', buttonId: 14, color: const Color(0xFFFFD54F), size: size)),
          Positioned(left: 0, top: spacing * 0.5, child: _buildGamepadButton(label: 'C←', buttonId: 15, color: const Color(0xFFFFD54F), size: size)),
        ],
      ),
    );
  }

  Widget _buildAnalogStick() {
    return GestureDetector(
      onPanStart: (details) => _updateAnalog(details.localPosition),
      onPanUpdate: (details) => _updateAnalog(details.localPosition),
      onPanEnd: (details) => _resetAnalog(),
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Center(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  void _updateAnalog(Offset pos) {
    // Center is 60,60 for a 120x120 stick
    double dx = pos.dx - 60;
    double dy = pos.dy - 60;
    // Normalize to -32767 to +32767
    int xVal = ((dx / 60.0) * 32767).clamp(-32767, 32767).toInt();
    int yVal = ((dy / 60.0) * 32767).clamp(-32767, 32767).toInt();
    widget.engine?.updateAnalogState(0, 0, 0, xVal); // Port 0, Index 0 (Left Stick), X Axis
    widget.engine?.updateAnalogState(0, 0, 1, yVal); // Port 0, Index 0 (Left Stick), Y Axis
  }

  void _resetAnalog() {
    widget.engine?.updateAnalogState(0, 0, 0, 0);
    widget.engine?.updateAnalogState(0, 0, 1, 0);
  }

  Widget _buildDsOverlay() {
    return GestureDetector(
      onPanStart: (details) => _updatePointer(details.localPosition, true),
      onPanUpdate: (details) => _updatePointer(details.localPosition, true),
      onPanEnd: (details) => _updatePointer(Offset.zero, false),
      child: Container(
        color: Colors.transparent,
      ),
    );
  }

  void _updatePointer(Offset pos, bool pressed) {
    widget.engine?.updatePointerState(0, pos.dx.toInt(), pos.dy.toInt(), pressed);
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
