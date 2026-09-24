import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoService {
  VideoPlayerController? _controller;
  bool _isPlaying = false;

  void init() {}

  void playVideo(String gloss) {
    // Construct asset path
    String assetPath = 'assets/videos/$gloss.mp4';
    
    // Show the video in a dialog
    _showVideoDialog(gloss, assetPath);
  }

  void _showVideoDialog(String gloss, String assetPath) {
    // Initialize controller with asset
    _controller = VideoPlayerController.asset(assetPath)
      ..initialize().then((_) {
        _isPlaying = true;
        _controller!.play();
      });

    showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: Text('ISL Video: $gloss'),
        content: Container(
          height: 300,
          width: 300,
          child: _controller != null && _controller!.value.isInitialized
              ? AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text('Loading video...'),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _controller?.pause();
              _controller?.dispose();
              Navigator.pop(context);
            },
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
}

// Global navigator key for dialogs
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
