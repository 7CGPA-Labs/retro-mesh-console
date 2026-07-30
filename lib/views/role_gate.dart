import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../utils/native_bridge.dart';
import '../emulation/libretro.dart';
import '../emulation/core_router.dart';

import 'gamepad_deck.dart';

class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  Future<void> _handleHostSelection(BuildContext context) async {
    String? playerName;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/player_name.txt');
      if (await file.exists()) {
        playerName = await file.readAsString();
      }
    } catch (_) {}

    if (playerName == null || playerName.isEmpty) {
      if (!context.mounted) return;
      playerName = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController(text: 'Player 1');
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E38),
            title: const Text('Enter Player Name', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
            content: TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'e.g. John',
                hintStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF2E93))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('CANCEL', style: TextStyle(color: Colors.white54))),
              TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.isEmpty ? 'Player 1' : ctrl.text), child: const Text('NEXT', style: TextStyle(color: Color(0xFF00E5FF)))),
            ],
          );
        }
      );

      if (playerName == null) return;
      
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/player_name.txt');
        await file.writeAsString(playerName);
      } catch (_) {}
    }

    bool loadingShown = false;
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: CoreRouter.getSupportedExtensions(),
      );

      debugPrint('[DEBUG] FilePicker raw result: $result');
      if (result != null) {
        debugPrint('[DEBUG] Selected file count: ${result.files.length}');
        for (int i = 0; i < result.files.length; i++) {
          final f = result.files[i];
          debugPrint('[DEBUG] File [$i] path: ${f.path}, name: ${f.name}');
        }
      }

      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        final romPath = result.files.first.path!;
        final romName = result.files.first.name;

        // Map extension to Libretro core binary
        String coreFilename = CoreRouter.resolveCore(romPath);

        // Show elegant glass loading indicator
        if (!context.mounted) return;
        _showLoading(context, 'Extracting core binaries...');
        loadingShown = true;

        String corePath = '';
        try {
          corePath = await LibretroEngine.extractCoreFromAssets('assets/cores/$coreFilename');
        } catch (e) {
          debugPrint('[DEBUG] Core asset missing/failed extraction: $e');
        }

        // Initialize Host Mesh WebSocket server & mDNS advertiser natively
        String coreName = coreFilename.split('_').first;
        await NativeBridge.startHost(coreName, playerName);

        // Boot FFI Libretro emulation engine
        final engine = LibretroEngine();
        engine.initializeCore(corePath);
        engine.loadGame(romPath);

        // Removed openSystemCastMenu, GamepadDeck now handles checking and opening the cast dialog natively.

        if (!context.mounted) return;
        if (loadingShown) {
          Navigator.pop(context); // Dismiss extracting dialog
          loadingShown = false;
        }

        // Navigate to Dual-Screen Gamepad Deck (Host Mode)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GamepadDeck(
              isHost: true,
              engine: engine,
              romName: romName,
              coreName: coreName,
            ),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('[DEBUG] Fatal error in _handleHostSelection: $e');
      debugPrint('[DEBUG] Stack trace: $stack');
      if (context.mounted) {
        if (loadingShown) {
          Navigator.pop(context); // Ensure loading is dismissed
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text(
              'Failed to launch Console: $e',
              style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
            ),
          ),
        );
      }
    }
  }

  void _handleJoinSelection(BuildContext context) {
    NativeBridge.startDiscovery();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E38),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) => Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                const Text('Available Consoles', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                const SizedBox(height: 8),
                const Text('Tap a console, then choose your player slot', style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 20),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: NativeBridge.discoveredHosts,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF))),
                              SizedBox(height: 16),
                              Text('Scanning network...', style: TextStyle(color: Colors.white54, fontFamily: 'Outfit')),
                            ],
                          ),
                        );
                      }
                      
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: snapshot.data!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final host = snapshot.data![index];
                          final IconData hostIcon = host['hostType'] == 'desktop'
                              ? Icons.desktop_windows_rounded
                              : host['hostType'] == 'webos'
                              ? Icons.tv_rounded
                              : Icons.videogame_asset_rounded;
                          return Material(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: () {
                                NativeBridge.stopDiscovery();
                                Navigator.pop(ctx);
                                _pickPlayerSlotAndConnect(context, host);
                              },
                              borderRadius: BorderRadius.circular(14),
                              splashColor: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(hostIcon, color: const Color(0xFF00E5FF), size: 22),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(host['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${host['core'].toString().toUpperCase()} · ${host['ip']}',
                                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    NativeBridge.stopDiscovery();
                    Navigator.pop(ctx);
                  },
                  child: const Text('CANCEL', style: TextStyle(color: Colors.white54, fontFamily: 'Outfit')),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      NativeBridge.stopDiscovery();
    });
  }

  void _pickPlayerSlotAndConnect(BuildContext context, Map<String, dynamic> host) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16162D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Choose Player Slot', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
        content: const Text('Select player slot to connect to the console.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _connectAndNavigate(context, host, 1);
            },
            child: const Text('PLAYER 1', style: TextStyle(color: Color(0xFFFF2E93), fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _connectAndNavigate(context, host, 2);
            },
            child: const Text('PLAYER 2', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
          ),
        ],
      ),
    );
  }

  void _connectAndNavigate(BuildContext context, Map<String, dynamic> host, int playerSlot) {
    // Listen for PIN challenges
    final pinSubscription = NativeBridge.onPinPrompt.listen((_) {
      // Show PIN entry dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          final controller = TextEditingController();
          return AlertDialog(
            backgroundColor: const Color(0xFF16162D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Enter Pairing PIN', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Please enter the 6-digit pairing PIN shown on the host screen.', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                OtpInputField(
                  controller: controller,
                  onSubmitted: () {
                    Navigator.pop(dialogCtx);
                    NativeBridge.submitPin(controller.text);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  NativeBridge.submitPin(controller.text);
                },
                child: const Text('SUBMIT', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
              ),
            ],
          );
        },
      );
    });

    _showLoading(context, 'Connecting as Player $playerSlot...');
    NativeBridge.connectToHost(
      host['ip'],
      port: host['port'] ?? 8080,
      playerSlot: playerSlot,
    ).then((_) {
      pinSubscription.cancel();
      Navigator.pop(context); // Dismiss loading
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GamepadDeck(
            isHost: false,
            romName: 'Connected to ${host['name']}',
            coreName: host['core'],
            hostType: host['hostType'] ?? 'unknown',
          ),
        ),
      );
    }).catchError((err) {
      pinSubscription.cancel();
      Navigator.pop(context); // Dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $err')),
      );
    });
  }

  void _showLoading(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E38).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFF2E93).withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF2E93)),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Outfit',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Enforce portrait initially inside Gate, locks landscape in Gamepad deck
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF070714),
              Color(0xFF0F0F28),
              Color(0xFF070714),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 400, // Constrain width for scaling
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // App Title Logo Section
                      _buildHeader(),
                      const SizedBox(height: 24),

                  // Card 1: HOST CONSOLE (Player 1)
                  _buildCard(
                    title: 'START GAME CONSOLE',
                    role: 'PLAYER 1 / HOST CONSOLE',
                    description:
                        'Load a game ROM, connect to your television screen, and act as Player 1.',
                    icon: Icons.gamepad_rounded,
                    glowColor: const Color(0xFFFF2E93),
                    onTap: () => _handleHostSelection(context),
                  ),

                  const SizedBox(height: 28),

                  // Card 2: JOIN CONTROLLER (Player 1 or 2 Client)
                  _buildCard(
                    title: 'JOIN ACTIVE CONSOLE',
                    role: 'PLAYER 1 OR 2 / WIRELESS CLIENT',
                    description:
                        'Join an active game console on the local network. Choose your player slot — P1 or P2 — after selecting the host.',
                    icon: Icons.wifi_find_rounded,
                    glowColor: const Color(0xFF00E5FF),
                    onTap: () => _handleJoinSelection(context),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Footer info
                  Text(
                    'Made with ♥ by 7CGPA Labs',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 11,
                      letterSpacing: 2.0,
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                  ), // Column
                ), // SizedBox
              ), // FittedBox
            ), // Padding
          ), // Center
        ), // SafeArea
      ), // Container
    ); // Scaffold
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Glowing Console Icon
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF070714),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2E93).withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return RadialGradient(
                center: Alignment.center,
                radius: 0.5,
                colors: [Colors.white, Colors.white.withValues(alpha: 0.0)],
                stops: const [0.7, 1.0],
              ).createShader(bounds);
            },
            child: ClipOval(
              child: Image.asset(
                'assets/icon.png',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'MOJO SNAP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 38,
            fontWeight: FontWeight.w900,
            letterSpacing: 4.0,
            shadows: [
              Shadow(
                color: Color(0xFFFF2E93),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const Text(
          'CONSOLE SYSTEM',
          style: TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 4.0,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required String title,
    required String role,
    required String description,
    required IconData icon,
    required Color glowColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: const Color(0xFF16162D).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          highlightColor: glowColor.withValues(alpha: 0.05),
          splashColor: glowColor.withValues(alpha: 0.15),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: glowColor.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: glowColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 32,
                    color: glowColor,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role,
                        style: TextStyle(
                          color: glowColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OtpInputField extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSubmitted;
  const OtpInputField({super.key, required this.controller, required this.onSubmitted});

  @override
  State<OtpInputField> createState() => _OtpInputFieldState();
}

class _OtpInputFieldState extends State<OtpInputField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _focusNode.requestFocus();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {});
                  if (val.length == 6) {
                    widget.onSubmitted();
                  }
                },
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              final text = widget.controller.text;
              final char = index < text.length ? text[index] : '';
              final isFocused = _focusNode.hasFocus && index == text.length;
              final isFilled = index < text.length;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 38,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isFocused
                      ? const Color(0xFF00E5FF).withOpacity(0.05)
                      : const Color(0xFF1E1E38),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isFocused
                        ? const Color(0xFF00E5FF)
                        : isFilled
                            ? const Color(0xFFFF2E93)
                            : const Color(0xFF2C2C4E),
                    width: isFocused ? 2 : 1.5,
                  ),
                  boxShadow: isFocused
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withOpacity(0.2),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )
                        ]
                      : [],
                ),
                child: Text(
                  char,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
