import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';

/// Plays a local / network video for billboard media blocks.
class BillboardVideoPanel extends StatefulWidget {
  const BillboardVideoPanel({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.loop = true,
    this.muted = true,
  });

  final String path;
  final BoxFit fit;
  final bool loop;
  final bool muted;

  @override
  State<BillboardVideoPanel> createState() => _BillboardVideoPanelState();
}

class _BillboardVideoPanelState extends State<BillboardVideoPanel> {
  VideoPlayerController? _controller;
  String? _error;
  int _openGen = 0;

  @override
  void initState() {
    super.initState();
    // Defer until after the first frame so hot-restart / plugin channels settle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(widget.path);
    });
  }

  @override
  void didUpdateWidget(covariant BillboardVideoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _open(widget.path);
      return;
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (oldWidget.loop != widget.loop) {
      c.setLooping(widget.loop);
    }
    if (oldWidget.muted != widget.muted) {
      c.setVolume(widget.muted ? 0 : 1);
    }
  }

  Future<void> _open(String path) async {
    final gen = ++_openGen;
    final previous = _controller;
    _controller = null;
    if (mounted) setState(() => _error = null);
    await previous?.dispose();
    if (!mounted || gen != _openGen) return;

    if (path.trim().isEmpty) {
      setState(() => _error = 'No video path');
      return;
    }

    VideoPlayerController? next;
    try {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        next = VideoPlayerController.networkUrl(Uri.parse(path));
      } else {
        final file = File(path);
        if (!file.existsSync()) {
          setState(() => _error = 'File not found:\n$path');
          return;
        }
        next = VideoPlayerController.file(file);
      }
      await next.initialize();
      if (!mounted || gen != _openGen) {
        await next.dispose();
        return;
      }
      await next.setLooping(widget.loop);
      await next.setVolume(widget.muted ? 0 : 1);
      await next.play();
      if (!mounted || gen != _openGen) {
        await next.dispose();
        return;
      }
      setState(() {
        _controller = next;
        _error = null;
      });
    } on Object catch (e, st) {
      try {
        await next?.dispose();
      } catch (_) {}
      if (kDebugMode) {
        debugPrint('Video open failed: $e\n$st');
      }
      if (!mounted || gen != _openGen) return;
      setState(() => _error = _friendlyVideoError(e));
    }
  }

  static String _friendlyVideoError(Object e) {
    if (e is PlatformException &&
        (e.code == 'channel-error' ||
            (e.message?.contains('Unable to establish connection') ?? false))) {
      return 'Video plugin not ready.\nStop the app and run again\n(full rebuild, not hot reload).';
    }
    final raw = e.toString();
    if (raw.contains('channel-error') ||
        raw.contains('Unable to establish connection')) {
      return 'Video plugin not ready.\nStop the app and run again\n(full rebuild, not hot reload).';
    }
    if (raw.length > 160) return '${raw.substring(0, 157)}…';
    return raw;
  }

  @override
  void dispose() {
    _openGen++;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final err = _error;
    if (err != null) {
      return ColoredBox(
        color: const Color(0x33000000),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              err,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      );
    }

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(
        color: Color(0x33000000),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return FittedBox(
      fit: widget.fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }
}

extension ArrangementVideoPath on ArrangementBlock {
  /// Prefer full route, then media_file.
  String get resolvedVideoPath {
    if (pictureRoute.trim().isNotEmpty) return pictureRoute.trim();
    return mediaFile.trim();
  }
}
