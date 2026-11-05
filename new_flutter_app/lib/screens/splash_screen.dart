import 'dart:async';
import 'dart:math' as math; // Background animation ku thevai
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'contacts_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _glowController;
  late AnimationController _bgController; // Background animation ku
  
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Logo Fade & Scale Animation
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeIn),
    );

    // 2. Pulsing Glow Animation
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // 3. Background Floating Orbs Animation (Continuous)
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _logoController.forward();

    // 3.5 seconds aprom Login/Home ku navigate pannum
    Timer(const Duration(milliseconds: 3500), _navigateToNext);
  }

    Future<void> _navigateToNext() async {
    if (!mounted) return;
    
    // Always navigate to Login Screen after splash
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _glowController.dispose();
    _bgController.dispose(); // Dispose background controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Deep Dark Blue
      body: Stack(
        children: [
          // --- ATTRACTIVE BACKGROUND ANIMATION ---
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return Stack(
                children: [
                  // Glowing Orb 1
                  Positioned(
                    top: 100 + (math.sin(_bgController.value * math.pi * 2) * 50),
                    left: -50 + (math.cos(_bgController.value * math.pi * 2) * 30),
                    child: _buildGlowingOrb(200, Colors.blueAccent.withOpacity(0.15)),
                  ),
                  // Glowing Orb 2
                  Positioned(
                    bottom: 50 + (math.cos(_bgController.value * math.pi * 2) * 60),
                    right: -50 + (math.sin(_bgController.value * math.pi * 2) * 40),
                    child: _buildGlowingOrb(250, const Color(0xFF06B6D4).withOpacity(0.1)),
                  ),
                  // Glowing Orb 3 (Center glow behind logo)
                  Center(
                    child: _buildGlowingOrb(300, Colors.white.withOpacity(0.03)),
                  ),
                ],
              );
            },
          ),

          // --- MAIN LOGO & LOADING BAR ---
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- CIRCLE LOGO WITH GLOW ---
                    AnimatedBuilder(
                      animation: _glowController,
                      builder: (context, child) {
                        return Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF06B6D4).withOpacity(0.5 + (0.5 * _glowController.value)),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blueAccent.withOpacity(0.4 * _glowController.value),
                                blurRadius: 40,
                                spreadRadius: 15 * _glowController.value,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.cover, // Image ah circle ku ulla perfect ah fit pannum
                            ),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 50),
                    
                    // Futuristic Loading Bar
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        width: 150,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const LinearProgressIndicator(
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    Text(
                      'Connecting Hearts...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for glowing orbs
  Widget _buildGlowingOrb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
        ),
      ),
    );
  }
}