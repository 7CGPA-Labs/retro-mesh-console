import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../network/host_server.dart';
import '../network/client_socket.dart';
import '../emulation/libretro.dart';
import '../casting/universal_caster_interface.dart';
import '../casting/universal_caster_bridge.dart';
import 'gamepad_deck.dart';

class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  Future<void> _handleHostSelection(BuildContext context) async {
    bool loadingShown = false;
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['nes', 'smc', 'sfc', 'md', 'gen', 'bin'],
      );

      debugPrint('[DEBUG] FilePicker raw result: $result');
      if (result != null) {
        debugPrint('[DEBUG] Selected file count: ${result.files.length}');
        for (int i = 0; i < result.files.length; i++) {
          final f = result.files[i];
          debugPrint('[DEBUG] File [$i] path: ${f.path}, name: ${f.name}, bytes: ${f.bytes?.length}');
        }
      }

      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        final romPath = result.files.first.path!;
        final romName = result.files.first.name;
        final ext = romPath.split('.').last.toLowerCase();

        // Map extension to Libretro core binary
        String coreFilename;
        if (ext == 'nes') {
          coreFilename = Platform.isAndroid
              ? 'fceumm_libretro_android.so'
              : 'fceumm_libretro_ios.dylib';
        } else if (ext == 'smc' || ext == 'sfc') {
          coreFilename = Platform.isAndroid
              ? 'snes9x_libretro_android.so'
              : 'snes9x_libretro_ios.dylib';
        } else {
          coreFilename = Platform.isAndroid
              ? 'genesis_plus_gx_libretro_android.so'
              : 'genesis_plus_gx_libretro_ios.dylib';
        }

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

        // Initialize Host Mesh WebSocket server & mDNS advertiser
        await HostServer.instance.start();

        // Show custom display picker overlay
        final caster = UniversalCasterBridge();
        await caster.startScanning();

        final UniversalTVTarget? selectedTarget = await showModalBottomSheet<UniversalTVTarget>(
          context: context,
          backgroundColor: const Color(0xFF0F0F28),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) {
            return SafeArea(
              child: SizedBox(
                height: 350,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'SELECT WIRELESS DISPLAY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    Expanded(
                      child: StreamBuilder<List<UniversalTVTarget>>(
                        stream: caster.discoveredDevicesStream,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(color: Color(0xFFFF2E93)),
                                  SizedBox(height: 16),
                                  Text(
                                    'Scanning for devices...',
                                    style: TextStyle(color: Colors.white70, fontFamily: 'Outfit'),
                                  ),
                                ],
                              ),
                            );
                          }

                          final devices = snapshot.data!;
                          return ListView.separated(
                            itemCount: devices.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                            itemBuilder: (context, index) {
                              final device = devices[index];
                              return ListTile(
                                leading: Icon(
                                  device.protocolType == CastingProtocol.googleCast ? Icons.cast : Icons.tv,
                                  color: const Color(0xFFFF2E93),
                                ),
                                title: Text(
                                  device.name,
                                  style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                                ),
                                subtitle: Text(
                                  device.protocolType == CastingProtocol.googleCast ? 'Google Cast' : 'Miracast / AirPlay',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Outfit'),
                                ),
                                onTap: () {
                                  Navigator.pop(ctx, device);
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          'CANCEL',
                          style: TextStyle(color: Colors.white54, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );

        await caster.stopScanning();

        if (selectedTarget == null) {
          // User cancelled display selection, exit game
          engine.shutdown();
          HostServer.instance.stop();
          return;
        }

        // Connect to selected device
        if (!context.mounted) return;
        _showLoading(context, 'Connecting to ${selectedTarget.name}...');
        loadingShown = true;
        await caster.connectToDevice(selectedTarget);
        
        if (!context.mounted) return;
        Navigator.pop(context); // Dismiss connecting dialog
        loadingShown = false;

        // Boot FFI Libretro emulation engine
        final engine = LibretroEngine();
        engine.initializeCore(corePath);
        engine.loadGame(romPath);

        // Navigate to Dual-Screen Gamepad Deck (Host Mode)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GamepadDeck(
              isHost: true,
              engine: engine,
              romName: romName,
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
    // Client Mode triggers discovery immediately upon routing to GamepadDeck
    ClientSocket.instance.startDiscovery();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const GamepadDeck(
          isHost: false,
          romName: 'Connected to Host Console',
        ),
      ),
    );
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
            color: const Color(0xFF1E1E38).withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFF2E93).withOpacity(0.3)),
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Title Logo Section
                  _buildHeader(),
                  const SizedBox(height: 48),

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
                  
                  const SizedBox(height: 40),
                  
                  // Footer info
                  Text(
                    'RETRO MESH CONSOLE v1.0.0',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 11,
                      letterSpacing: 2.0,
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Glowing Console Icon
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1E1E3F),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2E93).withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: const Color(0xFF00E5FF).withOpacity(0.1),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Icons.grid_view_rounded,
            size: 48,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'RETRO MESH',
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
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 6.0,
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
            color: glowColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: const Color(0xFF16162D).withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          highlightColor: glowColor.withOpacity(0.05),
          splashColor: glowColor.withOpacity(0.15),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: glowColor.withOpacity(0.25),
                width: 1.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: glowColor.withOpacity(0.1),
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
                          color: Colors.white.withOpacity(0.65),
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
