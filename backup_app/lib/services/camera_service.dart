import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';

class CameraService {
  CameraController? _controller;
  bool isInitialized = false;
  Timer? _timer;
  Function(String)? _onPrediction;
  bool _isPaused = false;
  String _lastPrediction = 'Waiting...';

  Future<void> initialize() async {
    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.low);
    await _controller!.initialize();
    isInitialized = true;
  }

  Widget buildPreview() {
    if (_controller == null || !isInitialized) {
      return Center(child: CircularProgressIndicator());
    }
    return CameraPreview(_controller!);
  }

  void startListening(Function(String) onPrediction) {
    _onPrediction = onPrediction;
    _timer = Timer.periodic(Duration(seconds: 2), (timer) async {
      if (_isPaused) return;
      await _captureAndPredict();
    });
  }

  Future<void> _captureAndPredict() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      XFile image = await _controller!.takePicture();
      File file = File(image.path);

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:8000/api/predict-sign'),
      );
      request.files.add(await http.MultipartFile.fromPath('video', file.path));

      var response = await request.send();
      if (response.statusCode == 200) {
        var data = jsonDecode(await response.stream.bytesToString());
        String gloss = data['gloss'] ?? 'No sign detected';
        if (_lastPrediction != gloss) {
          _lastPrediction = gloss;
          if (_onPrediction != null) {
            _onPrediction!(gloss);
          }
        }
      }
    } catch (e) {
      // Silent fail
    }
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }

  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
  }
}
