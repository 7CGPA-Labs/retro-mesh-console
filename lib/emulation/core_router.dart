import 'dart:io';

class CoreRouter {
  // Maps file extensions to their ideal libretro core prefix
  static const Map<String, String> _extensionToCore = {
    // NES
    'nes': 'fceumm',
    // SNES
    'smc': 'snes9x',
    'sfc': 'snes9x',
    // Sega Genesis / Mega Drive
    'md': 'genesis_plus_gx',
    'gen': 'genesis_plus_gx',
    // Game Boy Advance
    'gba': 'mgba',
    // PlayStation 1
    'bin': 'pcsx_rearmed',
    'cue': 'pcsx_rearmed',
    'iso': 'pcsx_rearmed',
  };

  /// Returns a list of all ROM file extensions supported by the router.
  static List<String> getSupportedExtensions() {
    return _extensionToCore.keys.toList();
  }

  /// Resolves the correct Libretro core filename for a given ROM path.
  static String resolveCore(String romPath) {
    final ext = romPath.split('.').last.toLowerCase();
    
    final corePrefix = _extensionToCore[ext] ?? 'fceumm'; // Default to NES

    if (Platform.isAndroid) {
      return '${corePrefix}_libretro_android.so';
    } else if (Platform.isIOS) {
      return '${corePrefix}_libretro_ios.dylib';
    } else {
      // Fallback for desktop/other
      return '${corePrefix}_libretro.so';
    }
  }
}
