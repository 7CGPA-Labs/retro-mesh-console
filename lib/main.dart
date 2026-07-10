import 'package:flutter/material.dart';
import 'views/role_gate.dart';
import '../utils/native_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NativeBridge.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mojo Snap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFFF2E93),
        scaffoldBackgroundColor: const Color(0xFF070714),
        useMaterial3: true,
      ),
      home: const RoleGate(),
    );
  }
}
