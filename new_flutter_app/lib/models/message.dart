class Message {
  final String sender;
  final String text;
  final DateTime timestamp;

  Message({required this.sender, required this.text, required this.timestamp});

  // For JSON serialization (dummy for now)
  Map<String, dynamic> toJson() => {
    'sender': sender,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
  };

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      sender: json['sender'] ?? 'unknown',
      text: json['text'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }
}
