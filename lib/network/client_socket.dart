import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:web_socket_channel/web_socket_channel.dart';

class ClientSocket {
  static final ClientSocket instance = ClientSocket._internal();
  ClientSocket._internal();

  WebSocketChannel? _channel;
  nsd.Discovery? _discovery;
  Timer? _telemetryTimer;

  // Cached button states to suppress repeat events during pointer drag sweeps
  final Map<int, bool> _buttonStateCache = {};
  
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();

  final ValueNotifier<String> connectionStatusNotifier = ValueNotifier<String>('Disconnected');
  final ValueNotifier<String> logNotifier = ValueNotifier<String>('Client Stopped');

  bool get isConnected => _channel != null;

  /// Start automated mDNS scan to discover and connect to Console Host
  Future<void> startDiscovery() async {
    _log('Starting mDNS service scanner...');
    connectionStatusNotifier.value = 'Searching for Console Host...';

    try {
      if (_discovery != null) {
        await nsd.stopDiscovery(_discovery!);
        _discovery = null;
      }

      _discovery = await nsd.startDiscovery('_retroconsole._tcp');
      
      _discovery!.addListener(() async {
        final services = _discovery?.services ?? [];
        _log('Discovered services count: ${services.length}');
        
        for (final service in services) {
          _log('Resolving discovered service: ${service.name}');
          final resolvedService = await nsd.resolve(service);
          final addresses = resolvedService.addresses ?? [];
          
          if (addresses.isNotEmpty) {
            final hostAddress = addresses.first.address;
            final hostPort = resolvedService.port ?? 3000;
            
            _log('Resolved Host IP: $hostAddress on Port: $hostPort');
            
            // Connect to discovered host
            _connectToHost(hostAddress, hostPort);
            
            // Stop discovery scanner to conserve battery and networks
            if (_discovery != null) {
              await nsd.stopDiscovery(_discovery!);
              _discovery = null;
            }
            break;
          }
        }
      });
    } catch (e) {
      _log('Discovery failed: $e');
      connectionStatusNotifier.value = 'Discovery Error';
    }
  }

  void _connectToHost(String host, int port) {
    _log('Connecting to Console Server: ws://$host:$port...');
    connectionStatusNotifier.value = 'Connecting to Console...';

    try {
      final wsUrl = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(wsUrl);
      
      // Send initial connection telemetry packet
      connectionStatusNotifier.value = 'Connected';
      _log('WebSocket connection established successfully');
      
      // Start 8-second interval telemetry update loop
      _startTelemetryLoop();

      // Listen for socket events (such as closure/errors)
      _channel!.stream.listen(
        (message) {
          // Client only sends to Host, but we handle messages if any arrive
          _log('Server message received: $message');
        },
        onDone: () {
          _log('Disconnected from Console Server');
          disconnect();
        },
        onError: (e) {
          _log('WebSocket error: $e');
          disconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _log('Connection failed: $e');
      disconnect();
    }
  }

  /// Packages and transmits low-latency virtual gamepad inputs
  /// Implements edge state checks to prevent duplicate packet streams
  void sendButtonInput(int buttonId, bool pressed) {
    if (!isConnected) return;

    final cachedState = _buttonStateCache[buttonId] ?? false;
    if (cachedState == pressed) return; // Prevent duplicate inputs

    _buttonStateCache[buttonId] = pressed;

    // High-speed 2-byte protocol:
    // Byte 0: Action Phase (1 = KeyDown/Press, 2 = KeyUp/Release)
    // Byte 1: Button Identity Integer (1..12)
    final packet = Uint8List(2);
    packet[0] = pressed ? 1 : 2;
    packet[1] = buttonId;

    try {
      _channel!.sink.add(packet);
    } catch (e) {
      _log('Failed to send input: $e');
    }
  }

  void _startTelemetryLoop() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      _sendTelemetryPacket();
    });
    _sendTelemetryPacket(); // Initial telemetry flush
  }

  Future<void> _sendTelemetryPacket() async {
    if (!isConnected) return;

    try {
      final int level = await _battery.batteryLevel;
      final results = await _connectivity.checkConnectivity();
      
      String wifiStr = 'Disconnected';
      if (results.contains(ConnectivityResult.wifi)) {
        try {
          final rssi = await const MethodChannel('com.retromesh.console/wifi').invokeMethod<int>('getWifiRssi');
          wifiStr = rssi != null ? '$rssi dBm' : 'Wi-Fi';
        } catch (e) {
          wifiStr = 'Wi-Fi';
        }
      } else if (results.contains(ConnectivityResult.mobile)) {
        wifiStr = 'Mobile';
      } else if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        wifiStr = 'Ethernet';
      }

      final payload = jsonEncode({
        'battery': level,
        'wifi': wifiStr,
      });

      _channel!.sink.add(payload);
    } catch (e) {
      _log('Telemetry packing error: $e');
    }
  }

  /// Gracefully close connection sockets and timer handles
  void disconnect() {
    _log('Disconnecting client socket...');
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    
    if (_channel != null) {
      _channel!.sink.close(WebSocketStatus.normalClosure);
      _channel = null;
    }

    _buttonStateCache.clear();
    connectionStatusNotifier.value = 'Disconnected';
    _log('Client Socket Disconnected');
  }

  void _log(String message) {
    logNotifier.value = '[${DateTime.now().toIso8601String().substring(11, 19)}] $message';
    debugPrint('[ClientSocket] $message');
  }
}
