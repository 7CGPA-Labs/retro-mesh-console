import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'views/role_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.locationWhenInUse.request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Retro Mesh Console',
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
