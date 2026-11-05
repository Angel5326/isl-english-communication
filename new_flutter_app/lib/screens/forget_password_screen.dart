import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _showResetForm = false;

  Future<void> _sendOtp() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('https://handy-talk.onrender.com/api/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': _emailController.text.trim()}),
      );
      if (res.statusCode == 200) {
        setState(() => _showResetForm = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP sent to your email!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(jsonDecode(res.body)['detail'] ?? 'Error')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('https://handy-talk.onrender.com/api/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'otp': _otpController.text.trim(),
          'new_password': _newPasswordController.text
        }),
      );
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset successful! Please login.')));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(jsonDecode(res.body)['detail'] ?? 'Error')));
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
      appBar: AppBar(title: const Text('Forgot Password'), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              enabled: !_showResetForm,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Registered Email', border: OutlineInputBorder()),
            ),
            if (_showResetForm) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _otpController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: '6-Digit OTP', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : (_showResetForm ? _resetPassword : _sendOtp),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(_showResetForm ? 'Reset Password' : 'Send OTP'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}