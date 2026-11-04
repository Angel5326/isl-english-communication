import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/splash_screen.dart'; // <--- Import this


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Check if the user is already logged in
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');

  runApp(MyApp(isLoggedIn: token != null));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

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
      // If token exists, go straight to Contacts. If not, show Login.
      home: const SplashScreen(), // <--- Change this
    );
  }
}