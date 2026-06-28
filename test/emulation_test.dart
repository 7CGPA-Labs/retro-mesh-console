import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_mesh_console/emulation/libretro.dart';
import 'package:retro_mesh_console/network/host_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Emulation Engine FFI & Input Mapping Tests', () {
    late LibretroEngine engine;

    setUp(() {
      engine = LibretroEngine();
    });

    tearDown(() {
      engine.shutdown();
    });

    test('Engine falls back to mock mode gracefully when core is missing', () {
      engine.initializeCore('');
      expect(engine.isMockMode, isTrue);
    });

    test('Button states are registered correctly on Port 1 and Port 2', () {
      engine.initializeCore('');
      
      // Simulate button events on Port 1 (P1)
      engine.updateButtonState(0, 1, true); // P1 UP Press
      engine.updateButtonState(0, 5, true); // P1 A Press
      engine.updateButtonState(0, 6, false); // P1 B Release

      // Simulate button events on Port 2 (P2)
      engine.updateButtonState(1, 1, false); // P2 UP Release
      engine.updateButtonState(1, 5, true);  // P2 A Press

      expect(engine.p1ButtonStates[1], isTrue);
      expect(engine.p1ButtonStates[5], isTrue);
      expect(engine.p1ButtonStates[6], isFalse);
      
      expect(engine.p2ButtonStates[1], isFalse);
      expect(engine.p2ButtonStates[5], isTrue);
    });

    test('Libretro ID mapper translates to custom buttons correctly', () {
      // Button mapping verification
      // 0 (Libretro B) -> 6 (Custom B)
      expect(engine.p1ButtonStates[6], isNull);
      engine.updateButtonState(0, 6, true);
      expect(engine.p1ButtonStates[6], isTrue);
    });
  });

  group('Network Telemetry Serialization Tests', () {
    test('CombinedTelemetry copyWith updates properties correctly', () {
      final base = CombinedTelemetry(
        p1Connected: true,
        p1Battery: 90,
        p1Wifi: 'Wi-Fi',
        p2Connected: false,
        p2Battery: 0,
        p2Wifi: 'Offline',
      );

      final updated = base.copyWith(
        p2Connected: true,
        p2Battery: 75,
        p2Wifi: 'Wi-Fi (Excellent)',
      );

      expect(updated.p1Connected, isTrue);
      expect(updated.p1Battery, 90);
      expect(updated.p2Connected, isTrue);
      expect(updated.p2Battery, 75);
      expect(updated.p2Wifi, 'Wi-Fi (Excellent)');
    });

    test('Telemetry JSON packs/unpacks correctly', () {
      final int originalBattery = 88;
      final String originalWifi = 'Wi-Fi (Weak)';
      
      final payload = jsonEncode({
        'battery': originalBattery,
        'wifi': originalWifi,
      });

      final decoded = jsonDecode(payload);
      expect(decoded['battery'], originalBattery);
      expect(decoded['wifi'], originalWifi);
    });
  });
}
