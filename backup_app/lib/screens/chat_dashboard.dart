import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../services/video_service.dart';
import '../services/camera_service.dart';

class ChatDashboard extends StatefulWidget {
  const ChatDashboard({super.key});

  @override
  State<ChatDashboard> createState() => _ChatDashboardState();
}

class _ChatDashboardState extends State<ChatDashboard> {
  // --- State Variables ---
  String _sessionId = '';
  String _userId = '';
  String _inputMode = 'sign'; // 'sign' or 'text'
  List<Map<String, dynamic>> _messages = [];
  WebSocketChannel? _channel;
  final TextEditingController _textController = TextEditingController();
  bool _isConnected = false;
  String _predictedGloss = 'Waiting...';
  
  // --- Services ---
  final VideoService _videoService = VideoService();
  CameraService? _cameraService;

  @override
  void initState() {
    super.initState();
    _userId = 'user_${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    _videoService.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showJoinSessionDialog();
    });
  }

  // --- Join Session Dialog ---
  void _showJoinSessionDialog() {
    TextEditingController sessionController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Join Communication Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter the Session ID provided by the other user:'),
            SizedBox(height: 10),
            TextField(
              controller: sessionController,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. 1234',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _createNewSession();
            },
            child: Text('Create New'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              String sid = sessionController.text.trim();
              if (sid.isNotEmpty) {
                _joinSession(sid);
              } else {
                _createNewSession();
              }
            },
            child: Text('Join Session'),
          ),
        ],
      ),
    );
  }

  // --- Create New Session ---
  Future<void> _createNewSession() async {
    try {
      final response = await http.post(
        Uri.parse('http://10.13.137.252:8000/api/session/create'),
        body: {'user_id': _userId},
      );
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() {
          _sessionId = data['session_id'];
          _isConnected = true;
        });
        _connectWebSocket();
        _startAutoDetection();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Session Created: $_sessionId. Share this with others!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating session: $e')),
      );
    }
  }

  // --- Join Existing Session ---
  Future<void> _joinSession(String sessionId) async {
    try {
      final response = await http.post(
        Uri.parse('http://10.13.137.252:8000/api/session/join'),
        body: {'session_id': sessionId, 'user_id': _userId},
      );
      if (response.statusCode == 200) {
        setState(() {
          _sessionId = sessionId;
          _isConnected = true;
        });
        _connectWebSocket();
        _startAutoDetection();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined Session: $_sessionId')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join session. Please check the ID.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error joining session: $e')),
      );
    }
  }

  // --- WebSocket ---
  void _connectWebSocket() {
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://10.13.137.252:8000/ws/$_sessionId/$_userId'),
    );
    _channel!.stream.listen((data) {
      var message = jsonDecode(data);
      setState(() {
        if (message['type'] == 'chat' || message['type'] == 'system') {
          _messages.add(message);
        }
      });
    });
  }

  // --- Send Message ---
  void _sendMessage({String? text, String? gloss}) {
    if (text == null && gloss == null) return;
    Map<String, dynamic> message = {
      'text': text ?? '',
      'gloss': gloss ?? '',
      'timestamp': DateTime.now().toIso8601String(),
    };
    _channel!.sink.add(jsonEncode(message));
    setState(() {
      _messages.add({...message, 'sender': 'me'});
    });
  }

  // --- Auto Detection ---
  Future<void> _startAutoDetection() async {
    _cameraService = CameraService();
    await _cameraService!.initialize();
    _cameraService!.startListening((gloss) {
      setState(() {
        _predictedGloss = gloss;
        if (gloss != 'Waiting...' && gloss != 'No sign detected') {
          _sendMessage(gloss: gloss, text: gloss);
        }
      });
    });
  }

  // --- Send Text Message ---
  void _sendTextMessage() {
    if (_textController.text.isEmpty) return;
    String text = _textController.text;
    _sendMessage(text: text);
    _textController.clear();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _cameraService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Session: $_sessionId'),
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.wifi : Icons.wifi_off),
            onPressed: null,
          ),
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Share Session'),
                  content: Text('Share this Session ID with the other person to connect:\n\n$_sessionId'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Half: Input
          Container(
            height: MediaQuery.of(context).size.height * 0.45,
            color: Colors.grey[100],
            child: Column(
              children: [
                // Mode Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'sign', label: Text('👋 Sign')),
                        ButtonSegment(value: 'text', label: Text('✏️ Text')),
                      ],
                      selected: {_inputMode},
                      onSelectionChanged: (set) => setState(() => _inputMode = set.first),
                    ),
                  ],
                ),
                // Input Area
                Expanded(
                  child: _inputMode == 'sign'
                      ? _buildSignInput()
                      : _buildTextInput(),
                ),
              ],
            ),
          ),
          // Divider
          Divider(height: 2, color: Colors.blue),
          // Bottom Half: Replies
          Container(
            height: MediaQuery.of(context).size.height * 0.45,
            color: Colors.white,
            child: _buildReplyArea(),
          ),
        ],
      ),
    );
  }

  // --- Sign Input ---
  Widget _buildSignInput() {
    return Column(
      children: [
        Expanded(
          child: _cameraService != null && _cameraService!.isInitialized
              ? _cameraService!.buildPreview()
              : Center(child: CircularProgressIndicator()),
        ),
        Container(
          padding: EdgeInsets.all(8),
          color: Colors.blue[50],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'Detected: $_predictedGloss',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Text Input (no Vosk) ---
  Widget _buildTextInput() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Type your message...',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _sendTextMessage,
                  icon: Icon(Icons.send),
                  label: Text('Send'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Reply Area ---
  Widget _buildReplyArea() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet. Start signing or typing!',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: EdgeInsets.all(8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        var msg = _messages[_messages.length - 1 - index];
        bool isMe = msg['sender'] == 'me' || msg['sender'] == _userId;
        bool isSystem = msg['type'] == 'system';

        if (isSystem) {
          return Container(
            margin: EdgeInsets.symmetric(vertical: 4),
            padding: EdgeInsets.all(8),
            color: Colors.grey[200],
            child: Center(
              child: Text(
                msg['text'] ?? '',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          );
        }

        bool isSign = msg['gloss'] != null && msg['gloss']!.isNotEmpty;

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: EdgeInsets.all(12),
            constraints: BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue[200] : Colors.green[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isSign) ...[
                  Row(
                    children: [
                      Icon(Icons.sign_language, size: 16),
                      SizedBox(width: 4),
                      Text(
                        '🖐️ ${msg['gloss']}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(msg['text'] ?? ''),
                  SizedBox(height: 4),
                  ElevatedButton.icon(
                    onPressed: () {
                      _videoService.playVideo(msg['gloss']!);
                    },
                    icon: Icon(Icons.play_arrow),
                    label: Text('Play ISL Video'),
                  ),
                ] else ...[
                  Text(msg['text'] ?? ''),
                ],
                Text(
                  msg['timestamp']?.substring(0, 16) ?? '',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}