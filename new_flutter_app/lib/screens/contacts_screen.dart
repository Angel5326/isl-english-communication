import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_dashboard.dart';
import 'login_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<dynamic> _contacts = [];
  String? _token;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- Search Filter Logic ---
  List<dynamic> get _filteredContacts {
    if (_searchQuery.isEmpty) return _contacts;
    return _contacts.where((c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      final email = (c['email'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) || email.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    if (_token == null) return;

    try {
      final response = await http.get(
        Uri.parse('https://handy-talk.onrender.com/api/contacts'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        setState(() => _contacts = jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('Error loading contacts: $e');
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _addContactDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
          ],
        ),
        actions: [
          TextButton(onPressed: () async {
            final name = nameCtrl.text.trim();
            final email = emailCtrl.text.trim();

            if (name.isEmpty || !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid name and email')));
              return;
            }

            final res = await http.post(
              Uri.parse('https://handy-talk.onrender.com/api/contacts/add'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
              body: jsonEncode({'contact_name': name, 'contact_email': email}),
            );
            
            if (res.statusCode == 200) {
              Navigator.pop(ctx);
              _loadContacts();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(jsonDecode(res.body)['detail'])));
            }
          }, child: const Text('Add')),
        ],
      ),
    );
  }

  Future<void> _deleteContact(String email) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Are you sure you want to remove $email?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    final encodedEmail = Uri.encodeComponent(email);
    final response = await http.delete(
      Uri.parse('https://handy-talk.onrender.com/api/contacts/$encodedEmail'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      _loadContacts();
    }
  }

  Future<void> _inviteContact(String email) async {
    final response = await http.post(
      Uri.parse('https://handy-talk.onrender.com/api/session/invite?contact_email=$email'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final String generatedCode = data['session_id'].toString();
      
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Session Code Created'),
            content: Text('Share this code with $email to connect:\n\n$generatedCode', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatDashboard(initialSessionId: generatedCode)
                  ));
                }, 
                child: const Text('Enter Session')
              )
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // --- BACK BUTTON ---
        leading: Navigator.canPop(context) 
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ) 
            : null,
        title: const Text('My Contacts', style: TextStyle(color: Colors.white)), 
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent), 
            tooltip: 'Log Out',
            onPressed: _logout
          ),
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.white), 
            tooltip: 'Add Contact',
            onPressed: _addContactDialog
          )
        ]
      ),
      body: Column(
        children: [
          // --- SEARCH BAR ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _searchQuery.isNotEmpty 
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          
          // --- CONTACT LIST ---
          Expanded(
            child: _filteredContacts.isEmpty 
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty ? 'No contacts yet. Add one!' : 'No contacts found matching "$_searchQuery"', 
                      style: const TextStyle(color: Colors.white54)
                    )
                  )
                : ListView.builder(
                    itemCount: _filteredContacts.length,
                    itemBuilder: (ctx, i) {
                      final c = _filteredContacts[i];
                      return Card(
                        color: Colors.white.withOpacity(0.05),
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF6366F1),
                            child: Text(
                              (c['name'] != null && c['name'].toString().isNotEmpty) 
                                  ? c['name'][0].toUpperCase() 
                                  : '?', 
                              style: const TextStyle(color: Colors.white)
                            ),
                          ),
                          title: Text(c['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(c['email'] ?? '', style: const TextStyle(color: Colors.white54)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: () => _inviteContact(c['email']),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF06B6D4),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  minimumSize: const Size(60, 36)
                                ),
                                child: const Text('Connect'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () => _deleteContact(c['email']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatDashboard()));
        },
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.link, color: Colors.white),
        label: const Text('Create / Join Manual', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}