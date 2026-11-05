import 'package:flutter/material.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = [
      {"title": "Missed Call", "desc": "Aruna called you 5 mins ago.", "icon": Icons.phone_missed, "color": Colors.redAccent},
      {"title": "New Message", "desc": "John sent you a sign: 'HELLO'.", "icon": Icons.message, "color": Colors.blueAccent},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(title: const Text('Notifications'), backgroundColor: Colors.transparent),
      body: ListView.builder(
        itemCount: notifications.length,
        itemBuilder: (ctx, i) {
          final n = notifications[i];
          return ListTile(
            leading: Icon(n['icon'] as IconData, color: n['color'] as Color),
            title: Text(n['title'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(n['desc'] as String, style: const TextStyle(color: Colors.white54)),
            trailing: const Text('2m ago', style: TextStyle(color: Colors.white24, fontSize: 12)),
          );
        },
      ),
    );
  }
}