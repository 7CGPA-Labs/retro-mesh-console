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
      backgroundColor: const Color(0xFF1E1E38),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Available Consoles', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
              const SizedBox(height: 20),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: NativeBridge.discoveredHosts,
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF))),
                    );
                  }
                  
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      final host = snapshot.data![index];
                      return ListTile(
                        leading: Icon(
                          host['hostType'] == 'desktop' ? Icons.desktop_windows :
                          host['hostType'] == 'webos' ? Icons.tv : Icons.videogame_asset,
                          color: const Color(0xFF00E5FF)
                        ),
                        title: Text(host['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('IP: ${host['ip']} | System: ${host['core'].toString().toUpperCase()}', style: const TextStyle(color: Colors.white70)),
                        onTap: () {
                          NativeBridge.stopDiscovery();
                          NativeBridge.connectToHost(host['ip'], port: host['port'] ?? 8080);
                          Navigator.pop(ctx);
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
                        },
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  NativeBridge.stopDiscovery();
                  Navigator.pop(ctx);
                },
                child: const Text('CANCEL', style: TextStyle(color: Colors.white54, fontFamily: 'Outfit')),
              )
            ],
          ),
        );
      }
    ).then((_) {
      NativeBridge.stopDiscovery();
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

                  // Card 2: JOIN CONTROLLER (Player 2)
                  _buildCard(
                    title: 'JOIN ACTIVE CONSOLE',
                    role: 'PLAYER 2 / WIRELESS CLIENT',
                    description:
                        'Join an active game console session on the local network to play together as Player 2.',
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
