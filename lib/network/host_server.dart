import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nsd/nsd.dart' as nsd;
import '../emulation/libretro.dart';

class CombinedTelemetry {
  final bool p1Connected;
  final int p1Battery;
  final String p1Wifi;
  final bool p2Connected;
  final int p2Battery;
  final String p2Wifi;

  CombinedTelemetry({
    required this.p1Connected,
    required this.p1Battery,
    required this.p1Wifi,
    required this.p2Connected,
    required this.p2Battery,
    required this.p2Wifi,
  });

  CombinedTelemetry copyWith({
    bool? p1Connected,
    int? p1Battery,
    String? p1Wifi,
    bool? p2Connected,
    int? p2Battery,
    String? p2Wifi,
  }) {
    return CombinedTelemetry(
      p1Connected: p1Connected ?? this.p1Connected,
      p1Battery: p1Battery ?? this.p1Battery,
      p1Wifi: p1Wifi ?? this.p1Wifi,
      p2Connected: p2Connected ?? this.p2Connected,
      p2Battery: p2Battery ?? this.p2Battery,
      p2Wifi: p2Wifi ?? this.p2Wifi,
    );
  }
}

class HostServer {
  static final HostServer instance = HostServer._internal();
  HostServer._internal();

  HttpServer? _server;
  WebSocket? _p2Socket;
  nsd.Registration? _registration;
  Timer? _telemetryTimer;

  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();

  // Telemetry notifier containing merged P1 + P2 network/battery states
  final ValueNotifier<CombinedTelemetry> telemetryNotifier = ValueNotifier<CombinedTelemetry>(
    CombinedTelemetry(
      p1Connected: true,
      p1Battery: 100,
      p1Wifi: 'Searching...',
      p2Connected: false,
      p2Battery: 0,
      p2Wifi: 'Offline',
    ),
  );

  final ValueNotifier<String> logNotifier = ValueNotifier<String>('Server Stopped');

  bool get isRunning => _server != null;

  /// Starts the mesh server, mDNS broadcast, and telemetry update loop
  Future<void> start() async {
    if (isRunning) return;

    _log('Starting Console Server on Port 3000...');
    try {
      // Bind to any IPv4 address on port 3000
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 3000, shared: true);
      _log('Server bound successfully to port 3000');

      // Listen for WebSocket upgrade requests
      _server!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleClientConnection(socket);
        } else {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
        }
      }, onError: (e) {
        _log('HttpServer Error: $e');
      });

      // Advertise server via mDNS nsd package asynchronously to prevent blocking the engine boot
      _log('Publishing mDNS broadcast signature: _retroconsole._tcp...');
      nsd.register(
        const nsd.Service(
          name: 'RetroMeshConsoleHost',
          type: '_retroconsole._tcp',
          port: 3000,
        ),
      ).then((reg) {
        _registration = reg;
        _log('mDNS service registered successfully');
      }).catchError((e) {
        _log('mDNS registration failed: $e');
      });

      // Start Host local battery and Wi-Fi check loop (every 8 seconds)
      _startLocalTelemetryLoop();

    } catch (e) {
      _log('Failed to start server: $e');
      await stop();
      rethrow;
    }
  }

  /// Stops server, unregisters mDNS, and closes sockets
  Future<void> stop() async {
    _log('Shutting down Console Server...');
    _telemetryTimer?.cancel();
    _telemetryTimer = null;

    if (_p2Socket != null) {
      await _p2Socket!.close(WebSocketStatus.normalClosure, 'Console Host shutting down');
      _p2Socket = null;
    }

    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }

    if (_registration != null) {
      await nsd.unregister(_registration!);
      _registration = null;
    }

    telemetryNotifier.value = CombinedTelemetry(
      p1Connected: false,
      p1Battery: 0,
      p1Wifi: 'Offline',
      p2Connected: false,
      p2Battery: 0,
      p2Wifi: 'Offline',
    );
    _log('Console Server Stopped');
  }

  void _handleClientConnection(WebSocket socket) {
    if (_p2Socket != null) {
      _log('Rejecting extra controller client connection');
      socket.close(WebSocketStatus.normalClosure, 'Port 2 already occupied');
      return;
    }

    _p2Socket = socket;
    _log('Player 2 Controller Squad connected');
    _updateTelemetry(p2Connected: true);

    socket.listen(
      (message) {
        if (message is List<int> || message is Uint8List) {
          // High-speed 2-byte gamepad packets (unbuffered)
          final bytes = message as List<int>;
          if (bytes.length == 2) {
            final int phase = bytes[0]; // 1 = Press (KeyDown), 2 = Release (KeyUp)
            final int buttonId = bytes[1];
            final bool pressed = (phase == 1);

            // Feed directly into Active Libretro Core on Port 2 (index 1)
            LibretroEngine.activeInstance?.updateButtonState(1, buttonId, pressed);
          }
        } else if (message is String) {
          // Low-frequency JSON status packets
          try {
            final data = jsonDecode(message);
            final int battery = data['battery'] ?? 100;
            final String wifi = data['wifi'] ?? 'Wi-Fi';
            
            _updateTelemetry(
              p2Battery: battery,
              p2Wifi: wifi,
            );
          } catch (e) {
            _log('Error parsing client telemetry packet: $e');
          }
        }
      },
      onDone: () {
        _log('Player 2 Controller disconnected');
        _p2Socket = null;
        _updateTelemetry(
          p2Connected: false,
          p2Battery: 0,
          p2Wifi: 'Offline',
        );
      },
      onError: (e) {
        _log('Player 2 connection error: $e');
        _p2Socket = null;
        _updateTelemetry(
          p2Connected: false,
          p2Battery: 0,
          p2Wifi: 'Offline',
        );
      },
      cancelOnError: true,
    );
  }

  void _startLocalTelemetryLoop() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      _pollLocalTelemetry();
    });
    _pollLocalTelemetry(); // Initial poll
  }

  Future<void> _pollLocalTelemetry() async {
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

      _updateTelemetry(
        p1Connected: true,
        p1Battery: level,
        p1Wifi: wifiStr,
      );
    } catch (e) {
      debugPrint('Error polling local battery/wifi metrics: $e');
    }
  }

  void _updateTelemetry({
    bool? p1Connected,
    int? p1Battery,
    String? p1Wifi,
    bool? p2Connected,
    int? p2Battery,
    String? p2Wifi,
  }) {
    telemetryNotifier.value = telemetryNotifier.value.copyWith(
      p1Connected: p1Connected,
      p1Battery: p1Battery,
      p1Wifi: p1Wifi,
      p2Connected: p2Connected,
      p2Battery: p2Battery,
      p2Wifi: p2Wifi,
    );
  }

  void _log(String message) {
    logNotifier.value = '[${DateTime.now().toIso8601String().substring(11, 19)}] $message';
    debugPrint('[HostServer] $message');
  }
}
