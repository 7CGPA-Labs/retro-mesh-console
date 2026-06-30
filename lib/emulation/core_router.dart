import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class CoreRouter {
  static const Map<String, String> _extensionToCoreMap = {
    // NES
    '.nes': 'fceumm_libretro_android.so',
    // SNES
    '.smc': 'snes9x_libretro_android.so',
    '.sfc': 'snes9x_libretro_android.so',
    // Sega Genesis / Mega Drive
    '.md': 'picodrive_libretro_android.so',
    '.gen': 'picodrive_libretro_android.so',
    // PlayStation 1
    '.iso': 'pcsx_rearmed_libretro_android.so',
    '.bin': 'pcsx_rearmed_libretro_android.so',
    '.cue': 'pcsx_rearmed_libretro_android.so',
    '.chd': 'pcsx_rearmed_libretro_android.so',
    '.img': 'pcsx_rearmed_libretro_android.so',
  };

  // Optional overrides for specific problematic ROMs
  static const Map<String, String> _romOverrides = {
    // Example: 'heavy_game.iso': 'pcsx_rearmed_neon_libretro_android.so'
  };

  /// Returns the appropriate core filename for a given ROM path.
  /// Throws an exception if the extension is unsupported.
  static String getCoreForRom(String romPath) {
    final filename = p.basename(romPath);
    
    // Check specific ROM overrides first
    if (_romOverrides.containsKey(filename)) {
      debugPrint('[CoreRouter] Using override core for $filename: ${_romOverrides[filename]}');
      return _romOverrides[filename]!;
    }

    final ext = p.extension(romPath).toLowerCase();
    final core = _extensionToCoreMap[ext];

    if (core != null) {
      debugPrint('[CoreRouter] Routed extension $ext to core $core');
      return core;
    }

    throw UnsupportedError('No core found for ROM extension: $ext');
  }
}
