import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraView extends StatelessWidget {
  final CameraController controller;
  const CameraView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return CameraPreview(controller);
  }
}
