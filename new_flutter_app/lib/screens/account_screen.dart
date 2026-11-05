import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _nameController = TextEditingController();
  final _picController = TextEditingController();
  String? _email;
  String? _token;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');

    if (_token == null) return;

    try {
      final res = await http.get(
        Uri.parse('https://handy-talk.onrender.com/api/user/profile'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _nameController.text = data['name'] ?? '';
          _email = data['email']; // Get email directly from DB
          _picController.text = data['profile_pic'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _updateProfile() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.put(
        Uri.parse('https://handy-talk.onrender.com/api/user/profile'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'name': _nameController.text.trim(), 'profile_pic': _picController.text.trim()}),
      );
      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('name', _nameController.text.trim());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated!'), backgroundColor: Colors.green));
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
      appBar: AppBar(title: const Text('My Account'), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: const Color(0xFF6366F1),
                backgroundImage: _picController.text.isNotEmpty ? NetworkImage(_picController.text) : null,
                child: _picController.text.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _picController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Profile Picture URL (Optional)', border: OutlineInputBorder()),
                onChanged: (val) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: TextEditingController(text: _email),
                enabled: false,
                style: const TextStyle(color: Colors.white54),
                decoration: const InputDecoration(labelText: 'Email (Cannot be changed)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateProfile,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Changes'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}