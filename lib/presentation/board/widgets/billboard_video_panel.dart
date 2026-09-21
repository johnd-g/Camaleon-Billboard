import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/presentation/billboard_controller.dart';

/// Soft cap — many can exist; only this many decode/play at once.
class _VideoPlayerLimiter {
  static const maxPlaying = 4;
  static final List<_BillboardVideoPanelState> _live = [];

  static void attach(_BillboardVideoPanelState s) {
    if (_live.contains(s)) return;
    _live.add(s);
    _trim();
  }

  static void detach(_BillboardVideoPanelState s) {
    _live.remove(s);
    _trim();
  }

  static void _trim() {
    if (_live.isEmpty) return;
    final keep = _live.length <= maxPlaying
        ? List<_BillboardVideoPanelState>.of(_live)
        : _live.sublist(_live.length - maxPlaying);
    for (final s in List<_BillboardVideoPanelState>.of(_live)) {
      if (keep.contains(s)) {
        s._resumeFromBudget();
      } else {
        s._pauseForBudget();
      }
    }
  }

  static void notifyPlaying(_BillboardVideoPanelState s) {
    _live.remove(s);
    _live.add(s);
    _trim();
  }
}

/// Plays a local / network video for billboard media blocks.
///
/// Slow-UI fixes (even for a single video):
/// - Tear down decoder while layout-editing (no decode tax in Edit mode).
/// - Layout to the **on-screen** box size (not native 4K pixels).
/// - [RepaintBoundary] so video frames don't dirty the whole board.
/// - Soft limit of concurrent *playing* decoders (others pause).
class BillboardVideoPanel extends StatefulWidget {
  const BillboardVideoPanel({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.loop = true,
    this.muted = true,
    this.forcePlay,
  });

  final String path;
  final BoxFit fit;
  final bool loop;
  final bool muted;

  /// When null, plays only if [BillboardController.layoutEditing] is false.
  final bool? forcePlay;

  @override
  State<BillboardVideoPanel> createState() => _BillboardVideoPanelState();
}

class _BillboardVideoPanelState extends State<BillboardVideoPanel> {
  VideoPlayerController? _controller;
  String? _error;
  int _openGen = 0;
  bool _budgetPaused = false;

  bool get _wantPlay {
    if (widget.forcePlay != null) return widget.forcePlay!;
    try {
      return !context.read<BillboardController>().layoutEditing;
    } catch (_) {
      return true;
    }
  }

  @override
  void initState() {
    super.initState();
    _VideoPlayerLimiter.attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPlayback();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPlayback();
    });
  }

  @override
  void didUpdateWidget(covariant BillboardVideoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      unawaited(_open(widget.path));
      return;
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      _syncPlayback();
      return;
    }
    if (oldWidget.loop != widget.loop) {
      unawaited(c.setLooping(widget.loop));
    }
    if (oldWidget.muted != widget.muted) {
      unawaited(c.setVolume(widget.muted ? 0 : 1));
    }
    if (oldWidget.forcePlay != widget.forcePlay) {
      _syncPlayback();
    }
  }

  void _syncPlayback() {
    if (!_wantPlay) {
      unawaited(_tearDown(keepError: false));
      return;
    }
    if (_controller == null && _error == null) {
      unawaited(_open(widget.path));
      return;
    }
    if (_budgetPaused) return;
    final c = _controller;
    if (c != null && c.value.isInitialized && !c.value.isPlaying) {
      unawaited(c.play());
      _VideoPlayerLimiter.notifyPlaying(this);
    }
  }

  void _pauseForBudget() {
    _budgetPaused = true;
    final c = _controller;
    if (c != null && c.value.isInitialized && c.value.isPlaying) {
      unawaited(c.pause());
    }
  }

  void _resumeFromBudget() {
    if (!_budgetPaused) return;
    _budgetPaused = false;
    if (!_wantPlay) return;
    final c = _controller;
    if (c != null && c.value.isInitialized && !c.value.isPlaying) {
      unawaited(c.play());
    }
  }

  Future<void> _tearDown({required bool keepError}) async {
    final gen = ++_openGen;
    final previous = _controller;
    _controller = null;
    _budgetPaused = false;
    if (mounted && !keepError) {
      setState(() => _error = null);
    }
    await previous?.dispose();
    if (!mounted || gen != _openGen) return;
  }

  Future<void> _open(String path) async {
    if (!_wantPlay) return;

    final gen = ++_openGen;
    final previous = _controller;
    _controller = null;
    _budgetPaused = false;
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
        if (!await file.exists()) {
          if (!mounted || gen != _openGen) return;
          setState(() => _error = 'File not found:\n$path');
          return;
        }
        next = VideoPlayerController.file(file);
      }
      await next.initialize();
      if (!mounted || gen != _openGen || !_wantPlay) {
        await next.dispose();
        return;
      }
      await next.setLooping(widget.loop);
      await next.setVolume(widget.muted ? 0 : 1);
      await next.play();
      if (!mounted || gen != _openGen || !_wantPlay) {
        await next.dispose();
        return;
      }
      setState(() {
        _controller = next;
        _error = null;
      });
      _VideoPlayerLimiter.notifyPlaying(this);
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
    _VideoPlayerLimiter.detach(this);
    _openGen++;
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.select((BillboardController c) => c.layoutEditing);

    if (!_wantPlay) {
      return const ColoredBox(
        color: Color(0x33000000),
        child: Center(
          child: Icon(
            Icons.videocam_outlined,
            color: Colors.white54,
            size: 40,
          ),
        ),
      );
    }

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

    final src = c.value.size;
    final ar = (src.width > 0 && src.height > 0)
        ? src.width / src.height
        : 16 / 9;

    // Layout to the *display* box — never ask Flutter to size the player at
    // native 4K pixels (that alone made 1 video feel like the whole UI froze).
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 1280.0;
          final maxH =
              constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? constraints.maxHeight
              : 720.0;

          // Cap layout by device pixel ratio so we never size the player at
          // native 4K — fvp also caps decode to 1280×720 in main.dart.
          final dpr = ui.PlatformDispatcher.instance.views.isEmpty
              ? 1.0
              : ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
          const pixelCap = 1280.0;
          final coverW = widget.fit == BoxFit.cover
              ? (maxW / maxH > ar ? maxW : maxH * ar)
              : (maxW / maxH > ar ? maxH * ar : maxW);
          final layoutW = (coverW * dpr).clamp(1, pixelCap) / dpr;
          final layoutH = layoutW / ar;

          return ClipRect(
            child: SizedBox(
              width: maxW,
              height: maxH,
              child: FittedBox(
                fit: widget.fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: layoutW,
                  height: layoutH,
                  child: VideoPlayer(c),
                ),
              ),
            ),
          );
        },
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
