import 'package:flutter/material.dart';
import '../models/message.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  const ChatBubble({super.key, required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: isMine ? Colors.blue : Colors.grey[300],
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Text(
            message.text,
            style: TextStyle(color: isMine ? Colors.white : Colors.black),
          ),
        ),
      ),
    );
  }
}
