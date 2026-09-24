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

  static const String _baseUrl = 'localhost:8000';
  static const Duration recordDuration = Duration(milliseconds: 1500);
  static const Duration gapBetweenAttempts = Duration(milliseconds: 100);
  static const double minConfidence = 0.45;

  final Queue<String> _recentPredictions = Queue<String>();
  static const int smoothingWindow = 3;
  static const int votesNeeded = 1;

  Future<void> initialize() async {
    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.medium);
    await _controller!.initialize();
    isInitialized = true;
    debugPrint('[CameraService] Camera initialized (medium resolution)');
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
    debugPrint('[CameraService] startListening called (continuous mode)');
    _runLoop();
  }

  Future<void> _runLoop() async {
    while (_isActive) {
      if (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 300));
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

      if (bytes.length < 5000) {
        debugPrint('[CameraService] ⚠️ Clip too small — tab likely lost focus. Skipping.');
        _onRawPrediction?.call('Skipped (keep tab focused)', 0.0);
        return;
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://$_baseUrl/api/predict-sign'),
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
      } else {
        debugPrint('[CameraService] predict-sign failed: ${response.statusCode}');
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
        debugPrint('[CameraService] ✅ Confirmed: ${entry.key}');
        _recentPredictions.clear();
        return entry.key;
      }
    }

    return 'No sign detected';
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }

  void dispose() {
    _isActive = false;
    _controller?.dispose();
  }
}