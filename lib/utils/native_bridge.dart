import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('dev.seven_cgpalabs.mojosnap/system');
  
  static final StreamController<List<Map<String, dynamic>>> _hostsController = StreamController.broadcast();
  static Stream<List<Map<String, dynamic>>> get discoveredHosts => _hostsController.stream;

  static final StreamController<void> _disconnectController = StreamController.broadcast();
  static Stream<void> get onDisconnected => _disconnectController.stream;

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onHostsDiscovered') {
        final List<dynamic> raw = call.arguments;
        final List<Map<String, dynamic>> hosts = raw.map((e) => Map<String, dynamic>.from(e)).toList();
        _hostsController.add(hosts);
      } else if (call.method == 'onHostDisconnected') {
        _disconnectController.add(null);
      }
    });
  }

  static Future<void> startHost(String coreName, String playerName) async {
    try {
      await _channel.invokeMethod('startHost', {'core': coreName, 'playerName': playerName});
    } catch (e) {
      debugPrint('Failed to start host: $e');
    }
  }

  static Future<void> stopHost() async {
    try {
      await _channel.invokeMethod('stopHost');
    } catch (e) {
      debugPrint('Failed to stop host: $e');
    }
  }

  static Future<void> startDiscovery() async {
    try {
      await _channel.invokeMethod('startDiscovery');
    } catch (e) {
      debugPrint('Failed to start discovery: $e');
    }
  }

  static Future<void> stopDiscovery() async {
    try {
      await _channel.invokeMethod('stopDiscovery');
    } catch (e) {
      debugPrint('Failed to stop discovery: $e');
    }
  }

  static Future<void> connectToHost(String hostIp) async {
    try {
      await _channel.invokeMethod('connectToHost', {'ip': hostIp});
    } catch (e) {
      debugPrint('Failed to connect to host: $e');
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
