import 'package:flutter/material.dart';

import 'auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MoneyMapApp());
}

class MoneyMapApp extends StatelessWidget {
  const MoneyMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyMap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4DADFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF10233F),
        ),
        scaffoldBackgroundColor: const Color(0xFF071527),
        cardTheme: const CardThemeData(
          color: Color(0xFF10233F),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF142B49),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
