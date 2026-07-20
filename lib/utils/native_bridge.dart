import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:web_socket_channel/web_socket_channel.dart';

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('dev.seven_cgpalabs.mojosnap/system');
  
  static final StreamController<List<Map<String, dynamic>>> _hostsController = StreamController.broadcast();
  static Stream<List<Map<String, dynamic>>> get discoveredHosts => _hostsController.stream;

  static final StreamController<void> _disconnectController = StreamController.broadcast();
  static Stream<void> get onDisconnected => _disconnectController.stream;

  static final StreamController<String> _coreChangedController = StreamController.broadcast();
  static Stream<String> get onCoreChanged => _coreChangedController.stream;

  static nsd.Discovery? _discovery;
  static WebSocketChannel? _wsChannel;
  static RawDatagramSocket? _udpSocket;
  static InternetAddress? _hostIpAddress;
  static int _hostUdpPort = 55444;
  static bool _isLocalLan = true;

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onHostDisconnected') {
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
      _discovery = await nsd.startDiscovery('_retroconsole._tcp');
      _discovery!.addListener(() {
        final hosts = _discovery!.services.map((nsd.Service s) {
          final txt = s.txt ?? {};
          String name = 'Unknown Host';
          if (txt['serverName'] != null) {
            name = String.fromCharCodes(txt['serverName']!);
          } else if (s.name != null) {
            name = s.name!;
          }
          
          String hostType = 'unknown';
          if (txt['hostType'] != null) {
            hostType = String.fromCharCodes(txt['hostType']!);
          }
          
          String core = 'unknown';
          if (txt['core'] != null) {
            core = String.fromCharCodes(txt['core']!);
          }

          int port = s.port ?? 8080;
          if (txt['port'] != null) {
            port = int.tryParse(String.fromCharCodes(txt['port']!)) ?? port;
          }

          return {
            'name': name,
            'ip': s.host ?? '',
            'port': port,
            'hostType': hostType,
            'core': core,
          };
        }).toList();
        _hostsController.add(hosts);
      });
    } catch (e) {
      debugPrint('Failed to start discovery: $e');
    }
  }

  static Future<void> stopDiscovery() async {
    try {
      if (_discovery != null) {
        await nsd.stopDiscovery(_discovery!);
        _discovery = null;
      }
    } catch (e) {
      debugPrint('Failed to stop discovery: $e');
    }
  }

  static Future<void> connectToHost(String hostIp, {int port = 8080, bool isLocal = true}) async {
    try {
      _isLocalLan = isLocal;
      _hostIpAddress = InternetAddress(hostIp);
      
      // TCP / WebSocket (for State, Sync, and Long-Range WAN)
      _wsChannel = WebSocketChannel.connect(Uri.parse('ws://$hostIp:$port/controller'));
      _wsChannel!.stream.listen(
        (message) {
          if (message is String) {
            try {
              final json = jsonDecode(message);
              if (json['event'] == 'core_loaded') {
                _coreChangedController.add(json['core'] as String);
              }
            } catch (_) {}
          }
        },
        onDone: () {
          _wsChannel = null;
          _disconnectController.add(null);
        },
        onError: (error) {
          _wsChannel = null;
          _disconnectController.add(null);
        },
      );

      // UDP / Datagram (for Ultra-Low Latency Inputs on LAN)
      if (_isLocalLan) {
        _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      }
    } catch (e) {
      debugPrint('Failed to connect to host: $e');
    }
  }

  static Future<void> sendInput(int buttonId, bool pressed) async {
    try {
      if (_wsChannel != null || _udpSocket != null) {
        final payload = Uint8List(3);
        payload[0] = 2; // Player 2
        payload[1] = pressed ? 1 : 2; // 1 = BUTTON_DOWN, 2 = BUTTON_UP
        payload[2] = buttonId;

        if (_isLocalLan && _udpSocket != null && _hostIpAddress != null) {
          // Fire ultra-fast UDP packet (no handshake, no ACKs)
          _udpSocket!.send(payload, _hostIpAddress!, _hostUdpPort);
        } else if (_wsChannel != null) {
          // Fallback to TCP WebSocket for WAN / long-range
          _wsChannel!.sink.add(payload);
        }
      } else {
        await _channel.invokeMethod('sendInput', {
          'buttonId': buttonId,
          'pressed': pressed,
        });
      }
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
