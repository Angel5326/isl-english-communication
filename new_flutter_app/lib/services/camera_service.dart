import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:collection';

class CameraService {
  CameraController? _controller;
  bool isInitialized = false;
  Function(String)? _onPrediction;
  Function(String, double)? _onRawPrediction;
  bool _isPaused = false;
  bool _isActive = false;

  static const String _baseUrl = 'https://handy-talk.onrender.com';
  
  // --- OPTIMIZATION 1: Reduced time and resolution for faster upload ---
  static const Duration recordDuration = Duration(milliseconds: 1000); // 1 second
  static const Duration gapBetweenAttempts = Duration(milliseconds: 50);
  static const double minConfidence = 0.50; 

  final Queue<String> _recentPredictions = Queue<String>();
  static const int smoothingWindow = 3;
  static const int votesNeeded = 1; // Set to 1 for faster response

  Future<void> initialize() async {
    final cameras = await availableCameras();
    // Low resolution makes the video file much smaller -> uploads faster
    _controller = CameraController(cameras[0], ResolutionPreset.low); 
    await _controller!.initialize();
    isInitialized = true;
    debugPrint('[CameraService] Camera initialized (low resolution)');
  }

  Widget buildPreview() {
    if (_controller == null || !isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return CameraPreview(_controller!);
  }

  void startListening(
    Function(String) onPrediction, {
    Function(String, double)? onRawPrediction,
  }) {
    _onPrediction = onPrediction;
    _onRawPrediction = onRawPrediction;
    _isActive = true;
    _runLoop();
  }

  Future<void> _runLoop() async {
    while (_isActive) {
      if (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }
      await _recordAndPredict();
      await Future.delayed(gapBetweenAttempts);
    }
  }

  Future<void> _recordAndPredict() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.startVideoRecording();
      await Future.delayed(recordDuration);
      final XFile clip = await _controller!.stopVideoRecording();

      final bytes = await clip.readAsBytes();

      if (bytes.length < 2000) {
        debugPrint('[CameraService] Clip too small, skipping.');
        return;
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/predict-sign'),
      );
      request.files.add(
        http.MultipartFile.fromBytes('video', bytes, filename: 'clip.mp4'),
      );

      var response = await request.send();
      if (response.statusCode == 200) {
        var data = jsonDecode(await response.stream.bytesToString());
        String gloss = data['gloss'] ?? 'No sign detected';
        double confidence = (data['confidence'] ?? 0.0).toDouble();

        _onRawPrediction?.call(gloss, confidence);

        final smoothed = _applySmoothingFilter(gloss, confidence);
        _onPrediction?.call(smoothed);
      }
    } catch (e) {
      debugPrint('[CameraService] Record/predict error: $e');
    }
  }

  String _applySmoothingFilter(String gloss, double confidence) {
    final candidate = confidence >= minConfidence ? gloss : 'No sign detected';

    _recentPredictions.addLast(candidate);
    if (_recentPredictions.length > smoothingWindow) {
      _recentPredictions.removeFirst();
    }

    final counts = <String, int>{};
    for (final p in _recentPredictions) {
      if (p == 'No sign detected') continue;
      counts[p] = (counts[p] ?? 0) + 1;
    }

    for (final entry in counts.entries) {
      if (entry.value >= votesNeeded) {
        _recentPredictions.clear();
        return entry.key;
      }
    }

    return 'No sign detected';
  }

  void pause() => _isPaused = true;
  void resume() => _isPaused = false;

  void dispose() {
    _isActive = false;
    _controller?.dispose();
  }
}