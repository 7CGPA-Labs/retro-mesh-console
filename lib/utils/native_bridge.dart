import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('com.retromesh/system');

  static Future<void> startHost() async {
    try {
      await _channel.invokeMethod('startHost');
    } catch (e) {
      debugPrint('Failed to start host: $e');
    }
  }

  static Future<void> startClient() async {
    try {
      await _channel.invokeMethod('startClient');
    } catch (e) {
      debugPrint('Failed to start client: $e');
    }
  }

  static Future<void> sendInput(int buttonId, bool pressed) async {
    try {
      await _channel.invokeMethod('sendInput', {
        'buttonId': buttonId,
        'pressed': pressed,
      });
    } catch (e) {
      debugPrint('Failed to send input: $e');
    }
  }

  static Future<void> keepScreenOn(bool enable) async {
    try {
      await _channel.invokeMethod('keepScreenOn', {'enable': enable});
    } catch (e) {
      debugPrint('Failed to set screen keep-on: $e');
    }
  }
}
