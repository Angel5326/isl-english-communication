import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import '../services/camera_service.dart';

class ChatDashboard extends StatefulWidget {
  final String? initialSessionId;
  
  const ChatDashboard({super.key, this.initialSessionId});

  @override
  State<ChatDashboard> createState() => _ChatDashboardState();
}

class _ChatDashboardState extends State<ChatDashboard> with TickerProviderStateMixin {
  static const String _baseUrl = 'https://handy-talk.onrender.com';

  // --- Colors ---
  static const Color bgColor = Color(0xFF0B0F19);
  static const Color primaryBlue = Color(0xFF6366F1);
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color successGreen = Color(0xFF10B981);

  // --- Session state ---
  String _sessionId = '';
  String _userId = '';
  bool _isConnected = false;
  bool _isJoining = false;
  int _userCount = 1;
  Timer? _statusTimer;

  // --- Role State ---
  bool _isRoleSelected = false;
  String _mode = 'sign';

  final TextEditingController _joinController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _joinFocusNode = FocusNode();

  WebSocketChannel? _channel;

  // --- Sign detection ---
  CameraService? _cameraService;
  String _predictedGloss = 'Waiting...';
  
  // --- Sentence Building ---
  List<String> _sentenceWords = [];
  String _lastDetectedWord = '';
  DateTime _lastDetectionTime = DateTime.now();

  // --- Incoming message ---
  Map<String, dynamic>? _latestIncoming;

  // --- Video playback ---
  VideoPlayerController? _videoController;
  List<String> _videoQueue = [];
  int _videoIndex = 0;
  bool _videoNotFound = false;

  // --- Speech to Text ---
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false; // Tracks if speech is available
  String _lastWords = '';

  // --- Animation Controllers ---
  late AnimationController _scanController;
  late AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    
    if (widget.initialSessionId != null) {
      _sessionId = widget.initialSessionId!;
      _isConnected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectWebSocket();
        _startStatusPolling();
      });
    }

    _scanController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _floatController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    
    _initSpeech(); // Initialize Speech
  }

  // --- SPEECH TO TEXT LOGIC ---
  void _initSpeech() async {
    try {
      _speechEnabled = await _speech.initialize(
        onError: (val) => debugPrint('Speech Error: $val'),
        onStatus: (val) => debugPrint('Speech Status: $val'),
      );
      setState(() {});
    } catch (e) {
      debugPrint('Speech Init Error: $e');
    }
  }

  void _startListening() async {
    if (!_speechEnabled) {
      _showError('Speech recognition not available on this browser.');
      return;
    }

    _textController.clear();
    setState(() => _isListening = true);

    await _speech.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  void _stopListening() async {
    setState(() => _isListening = false);
    await _speech.stop();
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
      _textController.text = _lastWords;
    });
    // If it's a final result, stop the listening indicator
    if (result.finalResult) {
      setState(() => _isListening = false);
    }
  }

  // ================= SESSION LOGIC =================

  Future<void> _createNewSession() async {
    setState(() => _isJoining = true);
    String customCode = _joinController.text.trim();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/session/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'session_id': customCode.isNotEmpty ? customCode : null,
        }),
      );
      
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        await _enterSession(data['session_id']);
      } else {
        var error = jsonDecode(response.body);
        _showError(error['detail'] ?? 'Failed to create session');
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _joinSession(String sessionId) async {
    setState(() => _isJoining = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/session/join'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'user_id': _userId}),
      );
      if (response.statusCode == 200) {
        await _enterSession(sessionId);
      } else {
        _showError('Failed to join session');
      }
    } catch (e) {
      _showError('Error: $e');
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
  }

  void _selectRole(String role) async {
    setState(() {
      _mode = role;
      _isRoleSelected = true;
    });
    
    if (_mode == 'sign') {
      await _initCameraIfNeeded();
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating)
    );
  }

  // ================= WEBSOCKET =================

  void _connectWebSocket() {
    _channel = WebSocketChannel.connect(Uri.parse('wss://handy-talk.onrender.com/ws/$_sessionId/$_userId'));
    _channel!.stream.listen(
      (data) {
        var message = jsonDecode(data) as Map<String, dynamic>;
        if (message['type'] == 'system') return;

        setState(() => _latestIncoming = message);
        List<String> videos = List<String>.from(message['videos'] ?? []);
        if (message['kind'] == 'speak' && videos.isNotEmpty) {
          List<String> words = (message['gloss'] as String? ?? '').split(' ').where((w) => w.isNotEmpty).toList();
          _playVideoSequence(words);
        }
      },
      onError: (error) => setState(() => _isConnected = false),
      onDone: () => setState(() => _isConnected = false),
    );
  }

  void _sendRaw(Map<String, dynamic> message) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode(message));
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final response = await http.get(Uri.parse('$_baseUrl/api/session/$_sessionId/status'));
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          if (mounted) setState(() => _userCount = data['user_count'] ?? 1);
        }
      } catch (_) {}
    });
  }

  // ================= SIGN MODE =================

  Future<void> _initCameraIfNeeded() async {
    if (_cameraService != null) return;
    try {
      _cameraService = CameraService();
      await _cameraService!.initialize();
      _cameraService!.startListening(_onGlossDetected);
      if (mounted) setState(() {});
    } catch (e) {
      _showError('Camera error: $e');
    }
  }

  Future<void> _onGlossDetected(String gloss) async {
    if (!mounted) return;
    if (gloss == 'Waiting...' || gloss == 'No sign detected' || gloss.startsWith('Skipped')) return;

    final now = DateTime.now();
    if (gloss == _lastDetectedWord && now.difference(_lastDetectionTime).inMilliseconds < 2500) return;
    
    _lastDetectedWord = gloss;
    _lastDetectionTime = now;

    setState(() {
      _predictedGloss = gloss;
      _sentenceWords.add(gloss.toUpperCase());
    });

    String fullGlossSentence = _sentenceWords.join(' ');
    String english = fullGlossSentence;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/translate-gloss'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'gloss': fullGlossSentence}),
      );
      if (response.statusCode == 200) {
        english = jsonDecode(response.body)['english'] ?? fullGlossSentence;
      }
    } catch (e) {
      debugPrint('translate-gloss error: $e');
    }

    _sendRaw({
      'kind': 'sign',
      'gloss': fullGlossSentence,
      'english': english,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ================= SPEAK MODE =================

  Future<void> _sendTextMessage() async {
    if (_textController.text.trim().isEmpty) return;
    String text = _textController.text.trim();
    _textController.clear();
    if (_isListening) {
      _stopListening();
    }

    try {
      final response = await http.post(
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
      _showError('Error sending: $e');
    }
  }

  // ================= VIDEO PLAYBACK =================

  void _playVideoSequence(List<String> glossWords) {
    _videoController?.dispose();
    _videoController = null;
    _videoQueue = glossWords;
    _videoIndex = 0;
    _videoNotFound = false;
    _playNextVideo();
  }

  void _playNextVideo() {
    if (_videoQueue.isEmpty) return;
    if (_videoIndex >= _videoQueue.length) _videoIndex = 0;
    
    String word = _videoQueue[_videoIndex];
    _tryLoadVideo('assets/videos/$word.mp4', () {
      _tryLoadVideo('assets/videos/${word.toLowerCase()}.mp4', () {
        setState(() { _videoNotFound = true; _videoIndex++; });
        Future.delayed(const Duration(milliseconds: 500), () { if (mounted) _playNextVideo(); });
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
        if (controller.value.isCompleted) { _videoIndex++; _playNextVideo(); }
      });
    }).catchError((_) => onFail());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _channel?.sink.close();
    _cameraService?.dispose();
    _videoController?.dispose();
    _textController.dispose();
    _joinController.dispose();
    _joinFocusNode.dispose();
    _scanController.dispose();
    _floatController.dispose();
    _speech.stop(); // Dispose speech
    super.dispose();
  }

  // ================= UI ROUTING =================

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: bgColor,
        colorScheme: const ColorScheme.dark().copyWith(
          primary: primaryBlue,
          secondary: accentCyan,
        ),
      ),
      child: _sessionId.isEmpty 
          ? _buildStartScreen() 
          : (!_isRoleSelected ? _buildRoleSelectionScreen() : _buildMainScreen()),
    );
  }

  // ================= ROLE SELECTION SCREEN =================
  Widget _buildRoleSelectionScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B0F19), Color(0xFF17153B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'How do you want to communicate?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _selectRole('sign'),
                    child: Container(
                      width: 150,
                      height: 200,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: primaryBlue, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.sign_language, size: 60, color: primaryBlue),
                          SizedBox(height: 16),
                          Text('I want to Sign', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _selectRole('speak'),
                    child: Container(
                      width: 150,
                      height: 200,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: accentCyan.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: accentCyan, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.text_fields, size: 60, color: accentCyan),
                          SizedBox(height: 16),
                          Text('I want to Speak', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  // ================= START SCREEN =================
  Widget _buildStartScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B0F19), Color(0xFF17153B), Color(0xFF0B0F19)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _floatController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, -8 + (8 * _floatController.value)),
                            child: child,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryBlue.withOpacity(0.1),
                            boxShadow: [
                              BoxShadow(color: primaryBlue.withOpacity(0.2), blurRadius: 30, spreadRadius: 10)
                            ],
                          ),
                          child: const Icon(Icons.sign_language, size: 60, color: primaryBlue),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text('Handy Talk', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white)),
                      const SizedBox(height: 8),
                      Text('Real-time ISL Communication', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16, letterSpacing: 1.2)),
                      const SizedBox(height: 48),
                      TextField(
                        controller: _joinController,
                        focusNode: _joinFocusNode,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        style: const TextStyle(fontSize: 32, letterSpacing: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        decoration: InputDecoration(
                          counterText: "",
                          hintText: '----',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.1), letterSpacing: 16),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.4),
                          contentPadding: const EdgeInsets.symmetric(vertical: 20),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(color: accentCyan, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_isJoining)
                        const CircularProgressIndicator(color: accentCyan)
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () {
                              String sid = _joinController.text.trim();
                              if (sid.length == 4) {
                                _joinFocusNode.unfocus();
                                _joinSession(sid);
                              } else {
                                _showError('Please enter a 4-digit code');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text('Join Session', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton(
                            onPressed: _createNewSession,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: accentCyan, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              backgroundColor: accentCyan.withOpacity(0.05),
                            ),
                            child: const Text('Create New Session', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================= MAIN SCREEN =================

  Widget _buildMainScreen() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            _buildPulsingDot(),
            const SizedBox(width: 12),
            Text('Room: $_sessionId', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.white70),
            tooltip: 'Switch Mode',
            onPressed: () {
              setState(() {
                _isRoleSelected = false;
                if (_mode == 'sign') _cameraService?.pause();
              });
            },
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                const Icon(Icons.people, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Text('$_userCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            flex: 3,
            child: _mode == 'sign' 
                ? _buildSignInput() 
                : _buildSpeakInput(),
          ),
          const SizedBox(height: 16),
          Expanded(
            flex: 2,
            child: _buildIncomingPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (_isConnected ? successGreen : Colors.redAccent).withOpacity(value),
            boxShadow: [BoxShadow(color: (_isConnected ? successGreen : Colors.redAccent).withOpacity(0.5 * value), blurRadius: 10, spreadRadius: 2)],
          ),
        );
      },
    );
  }

  // --- SIGN INPUT ---
  Widget _buildSignInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accentCyan.withOpacity(0.3), width: 2),
                boxShadow: [BoxShadow(color: accentCyan.withOpacity(0.1), blurRadius: 20, spreadRadius: 2)],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _cameraService != null && _cameraService!.isInitialized
                        ? FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: 640,
                              height: 480,
                              child: _cameraService!.buildPreview(),
                            ),
                          )
                        : const Center(child: CircularProgressIndicator(color: accentCyan)),
                  ),
                  AnimatedBuilder(
                    animation: _scanController,
                    builder: (context, child) {
                      return Positioned(
                        top: _scanController.value * 400,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [Colors.transparent, accentCyan.withOpacity(0.8), Colors.transparent]),
                            boxShadow: [BoxShadow(color: accentCyan.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)],
                          ),
                        ),
                      );
                    },
                  ),
                  _buildCornerBracket(Alignment.topLeft),
                  _buildCornerBracket(Alignment.topRight),
                  _buildCornerBracket(Alignment.bottomLeft),
                  _buildCornerBracket(Alignment.bottomRight),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _predictedGloss != 'Waiting...' ? successGreen.withOpacity(0.5) : Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Detected: $_predictedGloss',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _predictedGloss != 'Waiting...' ? successGreen : Colors.white54),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.redAccent),
                  onPressed: () {
                    setState(() { _sentenceWords.clear(); _predictedGloss = 'Waiting...'; _lastDetectedWord = ''; });
                    _sendRaw({'kind': 'sign', 'gloss': '', 'english': '', 'timestamp': DateTime.now().toIso8601String()});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerBracket(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 30, height: 30,
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            top: alignment == Alignment.topLeft || alignment == Alignment.topRight ? const BorderSide(color: accentCyan, width: 3) : BorderSide.none,
            bottom: alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight ? const BorderSide(color: accentCyan, width: 3) : BorderSide.none,
            left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft ? const BorderSide(color: accentCyan, width: 3) : BorderSide.none,
            right: alignment == Alignment.topRight || alignment == Alignment.bottomRight ? const BorderSide(color: accentCyan, width: 3) : BorderSide.none,
          ),
        ),
      ),
    );
  }

  // --- SPEAK INPUT (WITH VOICE OPTION) ---
  Widget _buildSpeakInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                TextField(
                  controller: _textController,
                  maxLines: 5,
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _isListening ? 'Listening...' : 'Type or speak your message...',
                    hintStyle: TextStyle(color: _isListening ? accentCyan : Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
                if (_isListening)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.8, end: 1.2),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: const Icon(Icons.graphic_eq, color: Color(0xFF06B6D4), size: 30),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // MIC BUTTON
              Container(
                height: 56,
                width: 56,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: _isListening ? Colors.redAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _isListening ? Colors.redAccent : Colors.white24),
                ),
                child: IconButton(
                  icon: Icon(
                    _isListening ? Icons.stop : Icons.mic_none,
                    color: _isListening ? Colors.redAccent : Colors.white,
                  ),
                  onPressed: _isListening ? _stopListening : _startListening,
                ),
              ),
              // SEND BUTTON
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _sendTextMessage,
                    icon: const Icon(Icons.send),
                    label: const Text('Send to Partner', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue, 
                      foregroundColor: Colors.white, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- INCOMING PANEL ---
  Widget _buildIncomingPanel() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.easeOutQuint,
              switchOutCurve: Curves.easeInQuint,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: _latestIncoming == null ? _buildWaitingState() : _buildIncomingContent(_latestIncoming!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingState() {
    return Center(
      key: const ValueKey('waiting'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hourglass_empty, size: 48, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text('Waiting for partner...', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildIncomingContent(Map<String, dynamic> message) {
    String kind = message['kind'] ?? '';
    
    if (kind == 'speak') {
      return Column(
        key: ValueKey(message['timestamp']),
        children: [
          Text('Partner said: "${message['text'] ?? ''}"', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15, fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: _videoController != null && _videoController!.value.isInitialized
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: VideoPlayer(_videoController!)),
                    )
                  : _videoNotFound ? const Text('Video not available', style: TextStyle(color: Colors.redAccent)) : const CircularProgressIndicator(color: accentCyan),
            ),
          ),
        ],
      );
    }

    return Center(
      key: ValueKey(message['timestamp']),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(shape: BoxShape.circle, color: successGreen.withOpacity(0.1)), child: const Icon(Icons.sign_language, size: 48, color: successGreen)),
          const SizedBox(height: 16),
          Text(message['english'] ?? message['gloss'] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          Text('Raw Gloss: ${message['gloss'] ?? ''}', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)),
        ],
      ),
    );
  }
}