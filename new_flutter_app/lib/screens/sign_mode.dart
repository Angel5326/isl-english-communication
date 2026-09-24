import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../widgets/camera_view.dart';

class SignModeScreen extends StatefulWidget {
  @override
  _SignModeScreenState createState() => _SignModeScreenState();
}

class _SignModeScreenState extends State<SignModeScreen> {
  String _predictedGloss = '';
  String _englishTranslation = '';
  bool _isProcessing = false;
  CameraController? _cameraController;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  void _initCamera() async {
    final cameras = await availableCameras();
    _cameraController = CameraController(cameras[0], ResolutionPreset.medium);
    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  void _captureAndPredict() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    setState(() => _isProcessing = true);
    try {
      final image = await _cameraController!.takePicture();
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://localhost:8000/api/predict-sign'),
      );
      request.files.add(await http.MultipartFile.fromPath('video', image.path));
      var response = await request.send();
      if (response.statusCode == 200) {
        var data = jsonDecode(await response.stream.bytesToString());
        setState(() {
          _predictedGloss = data['gloss'] ?? '';
        });
        await _translateGloss(_predictedGloss);
      } else {
        setState(() => _predictedGloss = 'Error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _predictedGloss = 'Exception: $e');
    }
    setState(() => _isProcessing = false);
  }

  Future<void> _translateGloss(String gloss) async {
    if (gloss.isEmpty) return;
    try {
      var response = await http.post(
        Uri.parse('http://localhost:8000/api/translate-gloss'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'gloss': gloss}),
      );
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() => _englishTranslation = data['english'] ?? '');
      }
    } catch (e) {
      setState(() => _englishTranslation = 'Translate error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _cameraController != null && _cameraController!.value.isInitialized
              ? CameraView(controller: _cameraController!)
              : Center(child: CircularProgressIndicator()),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text('Predicted Gloss: $_predictedGloss', style: TextStyle(fontSize: 20)),
              Text('English: $_englishTranslation', style: TextStyle(fontSize: 18)),
              ElevatedButton(
                onPressed: _isProcessing ? null : _captureAndPredict,
                child: Text('Capture & Predict'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}