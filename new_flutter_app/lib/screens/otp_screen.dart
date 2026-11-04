import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'login_screen.dart';

class OTPScreen extends StatefulWidget {
  final String email;
  const OTPScreen({super.key, required this.email});
  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;

  Future<void> _verify() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('https://handy-talk.onrender.com/api/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email, 'otp': _otpController.text.trim()}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verified! Please login.')));
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(jsonDecode(response.body)['detail'])));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(title: const Text('Verify Email'), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text('Enter OTP sent to console for ${widget.email}', style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            TextField(controller: _otpController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: '6-Digit OTP', border: OutlineInputBorder())),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _verify,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: _isLoading ? const CircularProgressIndicator() : const Text('Verify OTP'),
            ),
          ],
        ),
      ),
    );
  }
}