import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SpeakModeScreen extends StatefulWidget {
  @override
  _SpeakModeScreenState createState() => _SpeakModeScreenState();
}

class _SpeakModeScreenState extends State<SpeakModeScreen> {
  final TextEditingController _textController = TextEditingController();
  String _gloss = '';
  List<String> _videoPaths = [];
  bool _loading = false;

  void _translateText() async {
    String text = _textController.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);
    try {
      var response = await http.post(
        Uri.parse('http://localhost:8000/api/english-to-isl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() {
          _gloss = data['gloss'] ?? '';
          _videoPaths = List<String>.from(data['videos'] ?? []);
        });
      } else {
        setState(() => _gloss = 'Error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _gloss = 'Exception: $e');
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              labelText: 'Enter English sentence',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: _loading ? null : _translateText,
            child: Text('Translate to ISL'),
          ),
          if (_loading) CircularProgressIndicator(),
          if (_gloss.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Gloss: $_gloss', style: TextStyle(fontSize: 18)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _videoPaths.length,
              itemBuilder: (ctx, idx) {
                return ListTile(
                  leading: Icon(Icons.videocam),
                  title: Text(_videoPaths[idx]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}