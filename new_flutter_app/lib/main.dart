import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Handy Talk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        colorScheme: const ColorScheme.dark().copyWith(
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF06B6D4),
        ),
      ),
      // Always start at Splash Screen
      home: const SplashScreen(), 
    );
  }
}