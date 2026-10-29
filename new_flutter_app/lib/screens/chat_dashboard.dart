import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import '../services/camera_service.dart';

class ChatDashboard extends StatefulWidget {
  const ChatDashboard({super.key});

  @override
  State<ChatDashboard> createState() => _ChatDashboardState();
}

class _ChatDashboardState extends State<ChatDashboard> {
  // --- Base URL for the cloud backend ---
  static const String _baseUrl = 'https://handy-talk.onrender.com';

  // --- Session state ---
  String _sessionId = '';
  String _userId = '';
  bool _isConnected = false;
  bool _isJoining = false;
  int _userCount = 1;
  Timer? _statusTimer;

  // --- Mode: 'sign' (camera in, video out) or 'speak' (text in, text out) ---
  String _mode = 'sign';

  final TextEditingController _joinController = TextEditingController();
  final TextEditingController _textController = TextEditingController();

  WebSocketChannel? _channel;

  // --- Sign detection ---
  CameraService? _cameraService;
  String _predictedGloss = 'Waiting...';

    // --- Sentence Building ---
  List<String> _sentenceWords = [];
  String _lastDetectedWord = '';
  DateTime _lastDetectionTime = DateTime.now();

  // --- Incoming message from partner (drives the bottom panel) ---
  Map<String, dynamic>? _latestIncoming;

  // --- Embedded video playback for incoming "speak" messages ---
  VideoPlayerController? _videoController;
  List<String> _videoQueue = [];
  int _videoIndex = 0;
  bool _videoNotFound = false;

  @override
  void initState() {
    super.initState();
    _userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('ChatDashboard started, userId=$_userId');
  }

  // ================= SESSION =================

  Future<void> _createNewSession() async {
    setState(() => _isJoining = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/session/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': _userId}),
      );
      debugPrint('create-session: ${response.statusCode} ${response.body}');
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        await _enterSession(data['session_id']);
      } else {
        _showError('Failed to create session: ${response.body}');
      }
    } catch (e) {
      _showError('Error creating session: $e');
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _joinSession(String sessionId) async {
    setState(() => _isJoining = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/session/join'), // <--- FIXED: Added missing comma
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'user_id': _userId}),
      );
      debugPrint('join-session: ${response.statusCode} ${response.body}');
      if (response.statusCode == 200) {
        await _enterSession(sessionId);
      } else {
        _showError('Failed to join session: ${response.body}');
      }
    } catch (e) {
      _showError('Error joining session: $e');
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _enterSession(String sessionId) async {
    setState(() {
      _sessionId = sessionId;
      _isConnected = true;
    });
    _connectWebSocket();
    _startStatusPolling();
    await _initCameraIfNeeded();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ================= WEBSOCKET =================

  void _connectWebSocket() {
    _channel = WebSocketChannel.connect(
      // <--- FIXED: Changed 'ri' to 'Uri', added underscores to sessionId and userId
      Uri.parse('wss://handy-talk.onrender.com/ws/$_sessionId/$_userId'),
    );
    _channel!.stream.listen(
      (data) {
        var message = jsonDecode(data) as Map<String, dynamic>;
        debugPrint('Received: $message');
        if (message['type'] == 'system') {
          _showError(message['text'] ?? 'System message');
          return;
        }
        // A real partner message (kind: sign / speak)
        setState(() => _latestIncoming = message);
        List<String> videos = List<String>.from(message['videos'] ?? []);
        if (message['kind'] == 'speak' && videos.isNotEmpty) {
          List<String> words = (message['gloss'] as String? ?? '')
              .split(' ')
              .where((w) => w.isNotEmpty)
              .toList();
          if (words.isEmpty) {
            words = videos.map((v) => v.replaceAll('.mp4', '')).toList();
          }
          _playVideoSequence(words);
        }
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
        setState(() => _isConnected = false);
      },
      onDone: () {
        setState(() => _isConnected = false);
      },
    );
  }

  void _sendRaw(Map<String, dynamic> message) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode(message));
  }

  // ================= STATUS POLLING =================

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final response = await http.get(
          // <--- FIXED: Removed 'http://' before '$_baseUrl'
          Uri.parse('$_baseUrl/api/session/$_sessionId/status'),
        );
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          if (mounted) setState(() => _userCount = data['user_count'] ?? 1);
        }
      } catch (_) {
        // ignore transient polling errors
      }
    });
  }

  // ================= SIGN MODE: camera → gloss → english =================

  Future<void> _initCameraIfNeeded() async {
    if (_cameraService != null) return;
    try {
      _cameraService = CameraService();
      await _cameraService!.initialize();
      _cameraService!.startListening(_onGlossDetected);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init failed: $e');
      _showError('Camera error: $e');
    }
  }

    Future<void> _onGlossDetected(String gloss) async {
    if (!mounted) return;
    setState(() => _predictedGloss = gloss);
    
    // Ignore these default messages
    if (gloss == 'Waiting...' || gloss == 'No sign detected' || gloss.startsWith('Skipped')) return;

    // --- DUPLICATE PREVENTION ---
    // If the camera detects the same word again within 2.5 seconds, ignore it.
    // This prevents "HELLO HELLO HELLO" when the user holds a sign.
    final now = DateTime.now();
    if (gloss == _lastDetectedWord && now.difference(_lastDetectionTime).inMilliseconds < 2500) {
      return; 
    }
    _lastDetectedWord = gloss;
    _lastDetectionTime = now;

    // Translate the gloss to English
    String english = gloss;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/translate-gloss'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'gloss': gloss}),
      );
      if (response.statusCode == 200) {
        english = jsonDecode(response.body)['english'] ?? gloss;
      }
    } catch (e) {
      debugPrint('translate-gloss error: $e');
    }

    // --- BUILD THE SENTENCE ---
    setState(() {
      _sentenceWords.add(english.toUpperCase()); 
    });

    // Send the accumulated sentence to the other phone
    _sendRaw({
      'kind': 'sign',
      'gloss': gloss,
      'english': _sentenceWords.join(' '), // This joins the words with spaces!
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ================= SPEAK MODE: text → gloss → video list =================

  Future<void> _sendTextMessage() async {
    if (_textController.text.trim().isEmpty) return;
    String text = _textController.text.trim();
    _textController.clear();

    try {
      final response = await http.post(
        // <--- FIXED: Removed 'http://' before '$_baseUrl'
        Uri.parse('$_baseUrl/api/english-to-isl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );
      String gloss = text.toUpperCase();
      List<String> videos = [];
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        gloss = data['gloss'] ?? gloss;
        videos = List<String>.from(data['videos'] ?? []);
      }
      _sendRaw({
        'kind': 'speak',
        'text': text,
        'gloss': gloss,
        'videos': videos,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('english-to-isl error: $e');
      _showError('Error sending: $e');
    }
  }

  // ================= EMBEDDED VIDEO PLAYBACK (incoming) =================

  void _playVideoSequence(List<String> glossWords) {
    _videoController?.dispose();
    _videoController = null;
    _videoQueue = glossWords;
    _videoIndex = 0;
    _videoNotFound = false;
    _playNextVideo();
  }

    void _playNextVideo() {
    // If the queue is empty, do nothing
    if (_videoQueue.isEmpty) return;

    // If we reach the end of the queue, loop back to the beginning!
    if (_videoIndex >= _videoQueue.length) {
      _videoIndex = 0; 
    }
    
    String word = _videoQueue[_videoIndex];
    
    _tryLoadVideo('assets/videos/$word.mp4', () {
      _tryLoadVideo('assets/videos/${word.toLowerCase()}.mp4', () {
        setState(() {
          _videoNotFound = true;
          _videoIndex++;
        });
        // A tiny delay prevents the app from freezing if a video is missing
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _playNextVideo();
        });
      });
    });
  }
  
  void _tryLoadVideo(String assetPath, VoidCallback onFail) {
    final controller = VideoPlayerController.asset(assetPath);
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _videoController?.dispose();
        _videoController = controller;
        _videoNotFound = false;
      });
      controller.play();
      controller.addListener(() {
        if (controller.value.isCompleted) {
          _videoIndex++;
          _playNextVideo();
        }
      });
    }).catchError((_) {
      onFail();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _channel?.sink.close();
    _cameraService?.dispose();
    _videoController?.dispose();
    _textController.dispose();
    _joinController.dispose();
    super.dispose();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    if (_sessionId.isEmpty) return _buildStartScreen();
    return _buildMainScreen();
  }

  Widget _buildStartScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('ISL Communication')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Join Communication Session',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Enter a Session ID to join, or create a new one:'),
              const SizedBox(height: 12),
              TextField(
                controller: _joinController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 7384',
                ),
              ),
              const SizedBox(height: 20),
              if (_isJoining) const CircularProgressIndicator(),
              if (!_isJoining) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      String sid = _joinController.text.trim();
                      if (sid.isNotEmpty) {
                        _joinSession(sid);
                      } else {
                        _showError('Enter a session ID, or tap "Create New" below.');
                      }
                    },
                    child: const Text('Join Session'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _createNewSession,
                    child: const Text('Create New Session'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainScreen() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Session: $_sessionId  •  $_userCount connected'),
        actions: [
          Icon(_isConnected ? Icons.wifi : Icons.wifi_off),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Share Session'),
                  content: Text('Give this code to the other person:\n\n$_sessionId'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'sign', label: Text('Sign')),
                ButtonSegment(value: 'speak', label: Text('Speak')),
              ],
              selected: {_mode},
              onSelectionChanged: (set) {
                setState(() => _mode = set.first);
                if (_mode == 'sign') {
                  _cameraService?.resume();
                } else {
                  _cameraService?.pause();
                }
              },
            ),
          ),
          // TOP: input area
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.grey[100],
              child: _mode == 'sign' ? _buildSignInput() : _buildSpeakInput(),
            ),
          ),
          const Divider(height: 2, color: Colors.blue),
          // BOTTOM: partner's incoming message
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.white,
              child: _buildIncomingPanel(),
            ),
          ),
        ],
      ),
    );
  }

  // --- Top panel: Sign mode (your camera) ---
    Widget _buildSignInput() {
    return Column(
      children: [
        Expanded(
          child: _cameraService != null && _cameraService!.isInitialized
              ? _cameraService!.buildPreview()
              : const Center(child: CircularProgressIndicator()),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Colors.blue[50],
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Detected: $_predictedGloss',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // --- NEW CLEAR BUTTON ---
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _sentenceWords.clear();
                    _predictedGloss = 'Waiting...';
                    _lastDetectedWord = '';
                  });
                  // Send a clear signal to the partner
                  _sendRaw({
                    'kind': 'sign',
                    'gloss': '',
                    'english': '',
                    'timestamp': DateTime.now().toIso8601String(),
                  });
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Clear'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }

    // --- Top panel: Speak mode (text/voice input) ---
  Widget _buildSpeakInput() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Type your message in English...',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _sendTextMessage,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    _showError('Voice input coming soon — type for now.');
                  },
                  icon: const Icon(Icons.mic),
                  label: const Text('Voice'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  // --- Bottom panel: partner's incoming message (video OR text) ---
  Widget _buildIncomingPanel() {
    if (_latestIncoming == null) {
      return const Center(
        child: Text('Waiting for a message from your partner...',
            style: TextStyle(color: Colors.grey)),
      );
    }

    String kind = _latestIncoming!['kind'] ?? '';

    // Partner typed/spoke -> show their ISL video
    if (kind == 'speak') {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.green[50],
            child: Text(
              'Partner said: "${_latestIncoming!['text'] ?? ''}"',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Center(
              child: _videoController != null && _videoController!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    )
                  : _videoNotFound
                      ? const Text('Video not available for this word')
                      : const CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }

    // Partner signed -> show gloss/English text
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sign_language, size: 40, color: Colors.green),
            const SizedBox(height: 12),
            Text(
              _latestIncoming!['english'] ?? _latestIncoming!['gloss'] ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Gloss: ${_latestIncoming!['gloss'] ?? ''}',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}