import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:camaleon_billboard/core/theme/camaleon_theme.dart';
import 'package:camaleon_billboard/core/utils/qb_color.dart';
import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';
import 'package:camaleon_billboard/presentation/billboard_controller.dart';
import 'package:camaleon_billboard/presentation/board/widgets/arrangement_style_editor.dart';
import 'package:camaleon_billboard/presentation/board/widgets/billboard_video_panel.dart';
import 'package:camaleon_billboard/presentation/board/widgets/menu_section_panel.dart';
import 'package:camaleon_billboard/presentation/connection/connection_page.dart';

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  bool _chromeHidden = true;
  int? _selectedId;

  /// Soft caps — large enough for wall / 8K layouts, not a hard product limit.
  static const int _maxBlockWidth = 20000;
  static const int _maxPos = 100000;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BillboardController>();
    final board = c.board;

    if (c.phase == BillboardPhase.loading ||
        c.phase == BillboardPhase.bootstrapping) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: scheme.primary)),
      );
    }

    if (c.phase == BillboardPhase.needsConnection) {
      return const ConnectionPage();
    }

    if (c.phase == BillboardPhase.error || board == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.orange,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    c.errorMessage ?? 'Could not load billboard',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => c.openBoard(),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: () => c.disconnectToSettings(),
                    child: const Text('Connection settings'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final bg = QbColors.of(board.mainBackColor);
    final editing = c.layoutEditing;
    // Canvas grows with content (giant screens OK). FittedBox keeps it on-screen.
    final designW = _designWidth(board);
    final designH = _designHeight(board);
    final screen = MediaQuery.sizeOf(context);
    final sideEditor = editing && screen.width >= 800;
    const sideW = 320.0;
    const topBarH = 72.0;

    MenuSection? selectedSection;
    if (_selectedId != null) {
      for (final s in board.sections) {
        if (s.arrangement.id == _selectedId) {
          selectedSection = s;
          break;
        }
      }
    }
    // On phones, put the editor opposite the block so it stays visible.
    final dockEditorTop = !sideEditor &&
        selectedSection != null &&
        selectedSection.arrangement.yDistance > designH * 0.42;

    // Paint the selected block last so it sits above overlaps and stays tappable.
    final pictures = _withSelectedOnTop(board.pictures, (p) => p.arrangement.id);
    final sections =
        _withSelectedOnTop(board.sections, (s) => s.arrangement.id);
    final bgPictures = board.boardBackgroundPictures;
    // If DB has multiple bb_background=1, only paint the first and warn in UI.
    final activeBgPictures =
        bgPictures.length <= 1 ? bgPictures : bgPictures.take(1).toList();
    final fgPictures = [
      for (final p in pictures)
        if (!p.arrangement.isBoardBackground) p,
    ];

    // Chrome/buttons stay OUTSIDE the double-tap detector so entering edit
    // mode cannot dispose DoubleTapRecognizer mid-tap (setState-during-build).
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: sideEditor ? sideW : 0,
            // Keep board under chrome but top-aligned so y=0 is the real top.
            top: editing ? topBarH : 0,
            bottom: editing && !sideEditor
                ? (selectedSection == null ? 88 : 210)
                : 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: editing
                  ? null
                  : () => setState(() => _chromeHidden = !_chromeHidden),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return InteractiveViewer(
                    // Pan/zoom fights with drag-to-move while editing.
                    panEnabled: !editing,
                    scaleEnabled: !editing,
                    minScale: 0.4,
                    maxScale: 3,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // One full-viewport fill — avoids "two backgrounds"
                          // (letterbox bars vs design canvas).
                          ColoredBox(color: bg),
                          for (final pic in activeBgPictures)
                            Positioned.fill(
                              key: ValueKey('bg-${pic.arrangement.id}'),
                              child: editing
                                  ? GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _selectBlock(
                                        pic.arrangement.id,
                                      ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: _selectedId ==
                                                    pic.arrangement.id
                                                ? CamaleonColors.green
                                                : Colors.transparent,
                                            width: 3,
                                          ),
                                        ),
                                        child: BillboardPicturePanel(
                                          block: pic,
                                        ),
                                      ),
                                    )
                                  : BillboardPicturePanel(
                                      block: pic,
                                    ),
                            ),
                          // Menu coords stay in design space; bg fills the screen.
                          FittedBox(
                            fit: BoxFit.contain,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: designW,
                              height: designH,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  if (editing)
                                    Positioned.fill(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onTap: () => setState(
                                          () => _selectedId = null,
                                        ),
                                      ),
                                    ),
                                  for (final section in sections)
                                    _BoardBlock(
                                      key: ValueKey(
                                        'sec-${section.arrangement.id}',
                                      ),
                                      x: section.arrangement.xDistance
                                          .toDouble(),
                                      y: section.arrangement.yDistance
                                          .toDouble(),
                                      width: section.arrangement.maxWidth
                                          .toDouble()
                                          .clamp(
                                            120,
                                            _maxBlockWidth.toDouble(),
                                          ),
                                      editing: editing,
                                      selected: _selectedId ==
                                          section.arrangement.id,
                                      resizable: true,
                                      contentRevision:
                                          '${section.arrangement.classFontSize}-'
                                          '${section.arrangement.itemFontSize}-'
                                          '${section.arrangement.maxWidth}-'
                                          '${section.arrangement.classBackColor}-'
                                          '${section.arrangement.itemBackColor}-'
                                          '${section.arrangement.classForeColor}-'
                                          '${section.arrangement.itemForeColor}-'
                                          '${section.arrangement.classBold}-'
                                          '${section.arrangement.itemBold}-'
                                          '${section.arrangement.classUpperCase}-'
                                          '${section.arrangement.itemUpperCase}-'
                                          '${section.arrangement.modifierColor}-'
                                          '${section.arrangement.modifierFontSize}-'
                                          '${section.arrangement.classFontName}-'
                                          '${section.arrangement.itemFontName}-'
                                          '${section.arrangement.modifierFontName}-'
                                          '${section.arrangement.contentType.dbValue}-'
                                          '${section.arrangement.borderTopWidth}-'
                                          '${section.arrangement.borderTopColor}-'
                                          '${section.items.length}',
                                      onSelect: () => _selectBlock(
                                        section.arrangement.id,
                                      ),
                                      onDragStarted: c.markLayoutDirty,
                                      onCommit: (x, y, width, height) {
                                        c.commitArrangementGeometry(
                                          arrangementId:
                                              section.arrangement.id,
                                          xDistance: x,
                                          yDistance: y,
                                          maxWidth: width.round(),
                                          maxX: _maxPos,
                                          maxY: _maxPos,
                                        );
                                      },
                                      child: MenuSectionPanel(
                                        section: section,
                                      ),
                                    ),
                                  for (final pic in fgPictures)
                                    _BoardBlock(
                                      key: ValueKey(
                                        'pic-${pic.arrangement.id}',
                                      ),
                                      x: pic.x.toDouble(),
                                      y: pic.y.toDouble(),
                                      width: pic.arrangement.maxWidth
                                          .toDouble()
                                          .clamp(
                                            40,
                                            _maxBlockWidth.toDouble(),
                                          ),
                                      height:
                                          pic.arrangement.pictureDisplayHeight,
                                      editing: editing,
                                      selected: _selectedId ==
                                          pic.arrangement.id,
                                      resizable: true,
                                      minWidth: 80,
                                      lockAspectHeight: true,
                                      contentRevision:
                                          '${pic.arrangement.maxWidth}-'
                                          '${pic.bytes?.length ?? 0}-'
                                          '${pic.route}-'
                                          '${pic.arrangement.mediaFit.dbValue}-'
                                          '${pic.arrangement.mediaOpacity}-'
                                          '${pic.arrangement.borderTopWidth}-'
                                          '${pic.arrangement.borderTopColor}-'
                                          '${pic.arrangement.mediaType.dbValue}',
                                      onSelect: () => _selectBlock(
                                        pic.arrangement.id,
                                      ),
                                      onDragStarted: c.markLayoutDirty,
                                      onCommit: (x, y, width, height) {
                                        c.commitArrangementGeometry(
                                          arrangementId:
                                              pic.arrangement.id,
                                          xDistance: x,
                                          yDistance: y,
                                          maxWidth: width.round(),
                                          minWidth: 80,
                                          maxX: _maxPos,
                                          maxY: _maxPos,
                                        );
                                      },
                                      child: BillboardPicturePanel(
                                        block: pic,
                                      ),
                                    ),
                                  if (board.sections.isEmpty &&
                                      board.pictures.isEmpty)
                                    const Center(
                                      child: Text(
                                        'No bb_arrangement rows for this computer name.\n'
                                        'Configure screens in Camaleon POS → Billboard.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (board.hasMultipleBoardBackgrounds)
            Positioned(
              left: 12,
              right: sideEditor ? sideW + 12 : 12,
              top: editing ? 72 : 12,
              child: SafeArea(
                bottom: false,
                child: Material(
                  color: const Color(0xEE7A4E00),
                  borderRadius: BorderRadius.circular(12),
                  elevation: 6,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFFFE7A3), size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Warning: more than one board background photo '
                            '(bb_background=1). Only one is allowed.',
                            style: TextStyle(
                              color: Color(0xFFFFF4D6),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (editing)
            _EditChrome(
              selectedId: _selectedId,
              board: board,
              saving: c.savingLayout,
              dirty: c.layoutDirty,
              uploadingBackground: c.uploadingBoardBackground,
              sidePanel: sideEditor,
              dockTop: dockEditorTop,
              sideWidth: sideW,
              onCancel: () async {
                setState(() => _selectedId = null);
                await c.cancelLayoutEdit();
              },
              onSave: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await c.saveLayoutEdits();
                if (!mounted) return;
                setState(() => _selectedId = null);
                if (ok) return;
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      c.errorMessage ?? 'Could not save the layout',
                    ),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
              onBoardBackgroundColor: c.setBoardBackgroundColor,
              onPickBackgroundImage: _pickBoardBackgroundImage,
              onPickBackgroundVideo: _pickBoardBackgroundVideo,
              onClearBackgroundImage: _clearBoardBackgroundImage,
              onBrowseMediaFile: _browseSelectedMediaFile,
              onStylePatch: ({
                int? classFontDelta,
                int? itemFontDelta,
                int? modifierFontSize,
                int? classForeColor,
                int? classBackColor,
                int? itemForeColor,
                int? itemBackColor,
                int? mainBackColor,
                int? modifierColor,
                bool? classBold,
                bool? itemBold,
                bool? classUpperCase,
                bool? itemUpperCase,
                bool? boardBackground,
                int? maxWidth,
                String? classFontName,
                String? itemFontName,
                String? modifierFontName,
                ArrangementContentType? contentType,
                int? offerId,
                ArrangementMediaType? mediaType,
                String? mediaFile,
                ArrangementMediaFit? mediaFit,
                double? mediaOpacity,
                int? displayOrder,
                int? displaySeconds,
                int? borderWidth,
                String? borderColor,
                bool? videoLoop,
                bool? videoMuted,
              }) {
                final id = _selectedId;
                if (id == null) return;
                if (maxWidth != null) {
                  c.resizeArrangement(
                    arrangementId: id,
                    maxWidth: maxWidth,
                  );
                }
                c.updateArrangementStyle(
                  arrangementId: id,
                  classFontDelta: classFontDelta,
                  itemFontDelta: itemFontDelta,
                  modifierFontSize: modifierFontSize,
                  classForeColor: classForeColor,
                  classBackColor: classBackColor,
                  itemForeColor: itemForeColor,
                  itemBackColor: itemBackColor,
                  mainBackColor: mainBackColor,
                  modifierColor: modifierColor,
                  classBold: classBold,
                  itemBold: itemBold,
                  classUpperCase: classUpperCase,
                  itemUpperCase: itemUpperCase,
                  boardBackground: boardBackground,
                  classFontName: classFontName,
                  itemFontName: itemFontName,
                  modifierFontName: modifierFontName,
                  contentType: contentType,
                  offerId: offerId,
                  mediaType: mediaType,
                  mediaFile: mediaFile,
                  mediaFit: mediaFit,
                  mediaOpacity: mediaOpacity,
                  displayOrder: displayOrder,
                  displaySeconds: displaySeconds,
                  borderWidth: borderWidth,
                  borderColor: borderColor,
                  videoLoop: videoLoop,
                  videoMuted: videoMuted,
                );
              },
            )
          else if (!_chromeHidden)
            Positioned(
              right: 12,
              top: 12,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        board.compName,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      IconButton(
                        tooltip: 'Edit layout',
                        onPressed: _enterLayoutEdit,
                        icon: const Icon(Icons.edit_outlined,
                            color: Colors.white),
                      ),
                      IconButton(
                        tooltip: 'Reload',
                        onPressed: () => c.reloadSilent(full: true),
                        icon: const Icon(Icons.refresh, color: Colors.white),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => c.disconnectToSettings(),
                        icon: const Icon(Icons.settings, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _designWidth(BillboardBoard board) {
    var maxX = 1280.0;
    for (final s in board.sections) {
      maxX = math.max(
        maxX,
        (s.arrangement.xDistance + s.arrangement.maxWidth).toDouble(),
      );
    }
    for (final p in board.pictures) {
      maxX = math.max(
        maxX,
        (p.x + p.arrangement.maxWidth.clamp(40, _maxBlockWidth)).toDouble(),
      );
    }
    return maxX + 80;
  }

  double _designHeight(BillboardBoard board) {
    var maxY = 720.0;
    for (final s in board.sections) {
      final estimate = s.arrangement.yDistance +
          80 +
          (s.items.length * (s.arrangement.itemFontSize + 10));
      maxY = math.max(maxY, estimate.toDouble());
    }
    for (final p in board.pictures) {
      if (p.arrangement.isBoardBackground) continue;
      maxY = math.max(
        maxY,
        p.y + p.arrangement.pictureDisplayHeight,
      );
    }
    return maxY + 80;
  }

  /// Moves the selected item to the end so it paints above overlapping siblings.
  List<T> _withSelectedOnTop<T>(List<T> items, int Function(T) idOf) {
    final id = _selectedId;
    if (id == null || items.length < 2) return items;
    final idx = items.indexWhere((e) => idOf(e) == id);
    if (idx < 0 || idx == items.length - 1) return items;
    final copy = List<T>.of(items);
    final selected = copy.removeAt(idx);
    copy.add(selected);
    return copy;
  }

  void _selectBlock(int id) {
    if (_selectedId == id) return;
    setState(() => _selectedId = id);
  }

  void _enterLayoutEdit() {
    final c = context.read<BillboardController>();
    setState(() {
      _chromeHidden = false;
      _selectedId = null;
    });
    c.beginLayoutEdit();
  }

  Future<String?> _localPathForPicked(PlatformFile file) async {
    final existing = file.path?.trim() ?? '';
    if (existing.isNotEmpty) return existing;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final dir = await getApplicationDocumentsDirectory();
      final dest = File(
        p.join(dir.path, 'bb_media', file.name.isNotEmpty ? file.name : 'media.bin'),
      );
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(bytes, flush: true);
      return dest.path;
    } on Object {
      return null;
    }
  }

  Future<void> _pickBoardBackgroundImage() async {
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);
    Uint8List? bytes;
    try {
      try {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 2560,
          imageQuality: 88,
        );
        if (file == null) return;
        bytes = await file.readAsBytes();
      } on Object {
        final files = await FilePicker.pickFiles(type: FileType.image);
        if (files.isEmpty) return;
        bytes = await files.first.readAsBytes();
      }
    } on Object catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open image: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
      return;
    }

    if (bytes.isEmpty) return;
    final ok = await c.setBoardBackgroundImage(bytes);
    if (!mounted) return;
    if (ok) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(c.errorMessage ?? 'Could not save background image'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  Future<void> _pickBoardBackgroundVideo() async {
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await FilePicker.pickFiles(type: FileType.video);
      if (files.isEmpty) return;
      final file = files.first;
      final path = await _localPathForPicked(file);
      final name = file.name.isNotEmpty
          ? file.name
          : (path != null ? p.basename(path) : 'video');
      if ((path == null || path.isEmpty) && name.isEmpty) return;

      final ok = await c.setBoardBackgroundVideo(
        mediaFile: name,
        pictureRoute: path ?? name,
      );
      if (!mounted) return;
      if (ok) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(c.errorMessage ?? 'Could not save background video'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open video: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
    }
  }

  Future<void> _clearBoardBackgroundImage() async {
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await c.clearBoardBackgroundImage();
    if (!mounted) return;
    if (ok) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(c.errorMessage ?? 'Could not remove background image'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  Future<void> _browseSelectedMediaFile() async {
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);
    final id = _selectedId;
    if (id == null) return;

    PictureBlock? pic;
    for (final p in c.board?.pictures ?? const <PictureBlock>[]) {
      if (p.arrangement.id == id) {
        pic = p;
        break;
      }
    }
    if (pic == null) return;

    var mediaType = pic.arrangement.mediaType;
    if (mediaType == ArrangementMediaType.none) {
      mediaType = ArrangementMediaType.image;
    }

    try {
      final files = await FilePicker.pickFiles(
        type: mediaType == ArrangementMediaType.video
            ? FileType.video
            : FileType.image,
      );
      if (files.isEmpty) return;
      final file = files.first;
      final path = await _localPathForPicked(file) ?? '';
      final name = file.name.isNotEmpty
          ? file.name
          : (path.isNotEmpty ? p.basename(path) : 'media');

      List<int>? bytes;
      if (mediaType == ArrangementMediaType.image) {
        try {
          bytes = await file.readAsBytes();
        } on Object {
          if (path.isNotEmpty) {
            bytes = await File(path).readAsBytes();
          }
        }
      }

      final ok = await c.applyPickedMedia(
        arrangementId: id,
        mediaType: mediaType,
        mediaFile: name,
        pictureRoute: path.isNotEmpty ? path : name,
        pictureBytes: bytes,
      );
      if (!mounted) return;
      if (ok) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(c.errorMessage ?? 'Could not save media file'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open file picker: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
    }
  }
}

class _EditChrome extends StatelessWidget {
  const _EditChrome({
    required this.selectedId,
    required this.board,
    required this.saving,
    required this.dirty,
    required this.uploadingBackground,
    required this.sidePanel,
    required this.dockTop,
    required this.sideWidth,
    required this.onCancel,
    required this.onSave,
    required this.onBoardBackgroundColor,
    required this.onPickBackgroundImage,
    required this.onPickBackgroundVideo,
    required this.onClearBackgroundImage,
    required this.onBrowseMediaFile,
    required this.onStylePatch,
  });

  final int? selectedId;
  final BillboardBoard board;
  final bool saving;
  final bool dirty;
  final bool uploadingBackground;
  final bool sidePanel;
  final bool dockTop;
  final double sideWidth;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final ValueChanged<int> onBoardBackgroundColor;
  final VoidCallback onPickBackgroundImage;
  final VoidCallback onPickBackgroundVideo;
  final VoidCallback onClearBackgroundImage;
  final VoidCallback onBrowseMediaFile;
  final StylePatch onStylePatch;

  @override
  Widget build(BuildContext context) {
    MenuSection? selectedSection;
    PictureBlock? selectedPicture;
    if (selectedId != null) {
      for (final s in board.sections) {
        if (s.arrangement.id == selectedId) {
          selectedSection = s;
          break;
        }
      }
      if (selectedSection == null) {
        for (final p in board.pictures) {
          if (p.arrangement.id == selectedId) {
            selectedPicture = p;
            break;
          }
        }
      }
    }

    final hasSelection = selectedSection != null || selectedPicture != null;
    Uint8List? bgBytes;
    var bgMediaType = ArrangementMediaType.none;
    var bgMediaFile = '';
    for (final p in board.boardBackgroundPictures) {
      bgMediaType = p.arrangement.mediaType;
      bgMediaFile = p.arrangement.resolvedVideoPath.isNotEmpty
          ? p.arrangement.resolvedVideoPath
          : p.arrangement.mediaFile;
      final b = p.bytes;
      if (b != null && b.isNotEmpty) {
        bgBytes = b;
        break;
      }
    }
    final editorBody = ArrangementStyleEditor(
      boardMainBackColor: board.mainBackColor,
      onBoardBackgroundColor: onBoardBackgroundColor,
      section: selectedSection,
      picture: selectedPicture,
      compact: !sidePanel,
      multipleBoardBackgrounds: board.hasMultipleBoardBackgrounds,
      backgroundPreviewBytes: bgBytes,
      backgroundMediaType: bgMediaType,
      backgroundMediaFile: bgMediaFile,
      uploadingBackground: uploadingBackground,
      onPickBackgroundImage: onPickBackgroundImage,
      onPickBackgroundVideo: onPickBackgroundVideo,
      onClearBackgroundImage: onClearBackgroundImage,
      onBrowseMediaFile: onBrowseMediaFile,
      onPatch: onStylePatch,
    );

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: sidePanel ? sideWidth : 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _TopEditBar(
                dirty: dirty,
                saving: saving,
                hint: !hasSelection
                    ? 'Tap a section or photo to style it'
                    : (sidePanel
                        ? 'Edit size & colors on the right'
                        : (dockTop
                            ? 'Edit size & colors above'
                            : 'Edit size & colors below')),
                onCancel: onCancel,
                onSave: onSave,
              ),
            ),
          ),
        ),
        if (sidePanel)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: sideWidth,
            child: Material(
              color: const Color(0xF0121824),
              elevation: 12,
              child: SafeArea(
                left: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Style',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasSelection
                                ? 'Changes apply live · Save when done'
                                : 'Board color always · pick a block for more',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        child: editorBody,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Positioned(
            left: 12,
            right: 12,
            top: dockTop ? 72 : null,
            bottom: dockTop ? null : 12,
            child: SafeArea(
              top: dockTop,
              bottom: !dockTop,
              child: Material(
                color: const Color(0xF0121824),
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: hasSelection ? 340 : 140,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: editorBody,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TopEditBar extends StatelessWidget {
  const _TopEditBar({
    required this.dirty,
    required this.saving,
    required this.hint,
    required this.onCancel,
    required this.onSave,
  });

  final bool dirty;
  final bool saving;
  final String hint;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF0121824),
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: CamaleonColors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.open_with_rounded,
                color: CamaleonColors.green,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Edit mode',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (dirty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: CamaleonColors.orange.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Unsaved',
                            style: TextStyle(
                              color: CamaleonColors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: saving ? null : onCancel,
              child: const Text('Discard'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: saving || !dirty ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardBlock extends StatefulWidget {
  const _BoardBlock({
    super.key,
    required this.x,
    required this.y,
    required this.width,
    required this.editing,
    required this.selected,
    required this.onSelect,
    required this.onCommit,
    required this.child,
    this.height,
    this.onDragStarted,
    this.resizable = false,
    this.lockAspectHeight = false,
    this.minWidth = 120,
    this.contentRevision = '',
  });

  final double x;
  final double y;
  final double width;
  final double? height;
  final bool editing;
  final bool selected;
  final bool resizable;
  /// When true, displayed height = width × 0.75 (no DB height column).
  final bool lockAspectHeight;
  final double minWidth;
  final String contentRevision;
  final VoidCallback onSelect;
  final VoidCallback? onDragStarted;
  final void Function(int x, int y, double width, double? height) onCommit;
  final Widget child;

  @override
  State<_BoardBlock> createState() => _BoardBlockState();
}

class _BoardBlockState extends State<_BoardBlock> {
  late double _x = widget.x;
  late double _y = widget.y;
  late double _width = widget.width;
  bool _dragging = false;
  Widget? _cachedChild;
  String? _cachedRevision;

  double get _height => widget.lockAspectHeight
      ? _width * 0.75
      : (widget.height ?? 0);

  @override
  void didUpdateWidget(covariant _BoardBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) {
      _x = widget.x;
      _y = widget.y;
      _width = widget.width;
    }
    if (oldWidget.contentRevision != widget.contentRevision ||
        oldWidget.child.runtimeType != widget.child.runtimeType) {
      _cachedChild = null;
    }
  }

  Widget _content() {
    if (_cachedChild == null || _cachedRevision != widget.contentRevision) {
      _cachedRevision = widget.contentRevision;
      _cachedChild = RepaintBoundary(child: widget.child);
    }
    return _cachedChild!;
  }

  void _commit() {
    _dragging = false;
    widget.onCommit(
      _x.round(),
      _y.round(),
      _width,
      widget.lockAspectHeight || widget.height != null ? _height : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _content();
    final h = widget.lockAspectHeight || widget.height != null ? _height : null;
    if (!widget.editing) {
      return Positioned(
        left: _x,
        top: _y,
        width: _width,
        height: h,
        child: content,
      );
    }

    return Positioned(
      left: _x,
      top: _y,
      width: _width,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onPanStart: (_) {
          _dragging = true;
          final select = widget.onSelect;
          final dirty = widget.onDragStarted;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            select();
            dirty?.call();
          });
        },
        onPanUpdate: (d) {
          final nx = (_x + d.delta.dx).clamp(0.0, 100000.0).toDouble();
          final ny = (_y + d.delta.dy).clamp(-40.0, 100000.0).toDouble();
          if (nx == _x && ny == _y) return;
          setState(() {
            _x = nx;
            _y = ny;
          });
        },
        onPanEnd: (_) => _commit(),
        onPanCancel: () {
          if (_dragging) _commit();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: widget.selected
                    ? Border.all(color: CamaleonColors.green, width: 2.5)
                    : null,
                boxShadow: widget.selected
                    ? [
                        BoxShadow(
                          color:
                              CamaleonColors.green.withValues(alpha: 0.35),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: content,
            ),
            if (widget.selected)
              Positioned(
                left: 6,
                top: -12,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: CamaleonColors.green,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Drag to move',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.selected && widget.resizable)
              Positioned(
                right: -14,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) {
                    _dragging = true;
                    widget.onDragStarted?.call();
                  },
                  onPanUpdate: (d) {
                    final nw = (_width + d.delta.dx)
                        .clamp(widget.minWidth, 20000.0)
                        .toDouble();
                    if (nw == _width) return;
                    setState(() => _width = nw);
                  },
                  onPanEnd: (_) => _commit(),
                  onPanCancel: _commit,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ResizeHandle(horizontal: true),
                        SizedBox(height: 4),
                        _ResizeLabel('Size'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: horizontal ? 22 : 44,
      height: horizontal ? 44 : 22,
      decoration: BoxDecoration(
        color: CamaleonColors.green,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
          ),
        ],
      ),
      child: Icon(
        horizontal ? Icons.open_in_full_rounded : Icons.swap_vert_rounded,
        size: 16,
        color: Colors.white,
      ),
    );
  }
}

class _ResizeLabel extends StatelessWidget {
  const _ResizeLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
