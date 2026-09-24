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
import 'package:camaleon_billboard/core/utils/unicode_text.dart';
import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';
import 'package:camaleon_billboard/presentation/billboard_controller.dart';
import 'package:camaleon_billboard/presentation/board/widgets/arrangement_style_editor.dart';
import 'package:camaleon_billboard/presentation/board/widgets/billboard_video_panel.dart';
import 'package:camaleon_billboard/presentation/board/widgets/customer_order_preview.dart';
import 'package:camaleon_billboard/presentation/board/widgets/menu_section_panel.dart';
import 'package:camaleon_billboard/presentation/connection/connection_page.dart';
import 'package:camaleon_billboard/presentation/live_order/live_order_controller.dart';

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  bool _chromeHidden = true;
  int? _selectedId;
  final FocusNode _boardFocus = FocusNode(debugLabel: 'boardShortcuts');

  /// Soft caps — large enough for wall / 8K layouts, not a hard product limit.
  static const int _maxBlockWidth = 20000;
  static const int _maxPos = 100000;

  /// Hidden exit: 4 taps on the top-left corner (playback only).
  int _exitCornerTaps = 0;
  DateTime? _exitCornerTapAt;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _boardFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onExitCornerTap() {
    final now = DateTime.now();
    final last = _exitCornerTapAt;
    if (last == null || now.difference(last) > const Duration(seconds: 2)) {
      _exitCornerTaps = 1;
    } else {
      _exitCornerTaps += 1;
    }
    _exitCornerTapAt = now;
    if (_exitCornerTaps < 4) return;
    _exitCornerTaps = 0;
    _exitCornerTapAt = null;
    // Hard-quit the process (kiosk / billboard). pop() alone may only background.
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final phase = context.select((BillboardController c) => c.phase);
    final errorMessage =
        context.select((BillboardController c) => c.errorMessage);

    if (phase == BillboardPhase.loading ||
        phase == BillboardPhase.bootstrapping) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: scheme.primary)),
      );
    }

    if (phase == BillboardPhase.needsConnection) {
      // Stable key keeps State across BoardPage rebuilds from controller notifies.
      return const ConnectionPage(key: ValueKey('connection'));
    }

    final hasBoard =
        context.select((BillboardController c) => c.board != null);
    if (phase == BillboardPhase.error || !hasBoard) {
      final c = context.read<BillboardController>();
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
                    errorMessage ?? 'Could not load billboard',
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

    final editing =
        context.select((BillboardController c) => c.layoutEditing);
    final screen = MediaQuery.sizeOf(context);
    final sideEditor = editing && screen.width >= 800;
    const sideW = 320.0;
    const topBarH = 72.0;

    final board = context.watch<BillboardController>().board!;
    final hasBackdrop = board.boardBackgroundPictures.isNotEmpty;
    final bg = hasBackdrop ? Colors.black : QbColors.of(board.mainBackColor);
    MenuSection? selectedSection;
    if (_selectedId != null) {
      for (final s in board.sections) {
        if (s.arrangement.id == _selectedId) {
          selectedSection = s;
          break;
        }
      }
    }

    return Focus(
      focusNode: _boardFocus,
      onKeyEvent: _onBoardKeyEvent,
      child: Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // Positioned MUST be a direct Stack child (Selector cannot wrap it).
          Positioned(
            left: 0,
            right: sideEditor ? sideW : 0,
            top: editing ? topBarH : 0,
            bottom: editing && !sideEditor
                ? (selectedSection == null ? 88 : 210)
                : 0,
            child: Selector<BillboardController, _CanvasKey>(
              selector: (_, c) => _CanvasKey(
                board: c.board!,
                editing: c.layoutEditing,
                customerDisplay: c.customerDisplay,
                activeRotationId: c.activeRotationId,
                previewRotation: c.previewRotation,
                selectedId: _selectedId,
              ),
              builder: (context, key, _) {
                return _BoardCanvasLayer(
                  board: key.board,
                  editing: key.editing,
                  customerDisplay: key.customerDisplay,
                  selectedId: key.selectedId,
                  screen: screen,
                  maxBlockWidth: _maxBlockWidth,
                  maxPos: _maxPos,
                  onToggleChrome: () =>
                      setState(() => _chromeHidden = !_chromeHidden),
                  onSelectBlock: _selectBlock,
                  onClearSelection: () => setState(() => _selectedId = null),
                  designWidth: _designWidth,
                  designHeight: _designHeight,
                  withSelectedOnTop: _withSelectedOnTop,
                );
              },
            ),
          ),
          // Brand watermark — fixed to screen bottom-left (outside InteractiveViewer).
          Positioned(
              left: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                right: false,
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
                    child: Opacity(
                      opacity: 0.85,
                      child: Image.asset(
                        CamaleonAssets.logo,
                        height: 40,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
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
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFFFE7A3),
                          size: 20,
                        ),
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
            Selector<BillboardController, _ChromeKey>(
              selector: (_, c) => _ChromeKey(
                board: c.board!,
                dirty: c.layoutDirty,
                saving: c.savingLayout,
                creating: c.creatingBlock,
                uploading: c.uploadingBoardBackground,
                customerDisplay: c.customerDisplay,
                selectedId: _selectedId,
              ),
              builder: (context, key, _) {
                final c = context.read<BillboardController>();
                final designH = _designHeight(key.board);
                MenuSection? chromeSelected;
                if (_selectedId != null) {
                  for (final s in key.board.sections) {
                    if (s.arrangement.id == _selectedId) {
                      chromeSelected = s;
                      break;
                    }
                  }
                }
                final dockEditorTop = !sideEditor &&
                    chromeSelected != null &&
                    chromeSelected.arrangement.yDistance > designH * 0.42;
                return _EditChrome(
                  selectedId: _selectedId,
                  board: key.board,
                  saving: key.saving,
                  dirty: key.dirty,
                  uploadingBackground: key.uploading,
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
                  onPickBlockImage: () =>
                      _browseSelectedMediaFile(ArrangementMediaType.image),
                  onPickBlockVideo: () =>
                      _browseSelectedMediaFile(ArrangementMediaType.video),
                  onClearBlockMedia: _clearSelectedBlockMedia,
                  onAddMenuSection: _addMenuSection,
                  onAddOfferSection: _addOfferSection,
                  onAddRotatingOffers: _addRotatingOffers,
                  onAddPhotoBlock: _addPhotoBlock,
                  onDeleteBlock: _deleteSelectedBlock,
                  creatingBlock: key.creating,
                  customerDisplay: key.customerDisplay,
                  onCustomerDisplayChanged: c.setCustomerDisplay,
                  onStylePatch:
                      ({
                        int? classFontDelta,
                        int? itemFontDelta,
                        int? classFontSize,
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
                        int? rangeOffset,
                        int? rangeCount,
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
                          classFontSize: classFontSize,
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
                          rangeOffset: rangeOffset,
                          rangeCount: rangeCount,
                          borderWidth: borderWidth,
                          borderColor: borderColor,
                          videoLoop: videoLoop,
                          videoMuted: videoMuted,
                        );
                      },
                );
              },
            )
          else if (!_chromeHidden)
            Positioned(
              right: 12,
              top: 12,
              child: Builder(
                builder: (context) {
                  final c = context.watch<BillboardController>();
                  return Material(
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
                            c.board?.compName ?? '',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          IconButton(
                            tooltip: 'Edit layout',
                            onPressed: _enterLayoutEdit,
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Reload',
                            onPressed: () => c.reloadSilent(full: true),
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Settings',
                            onPressed: () => c.disconnectToSettings(),
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (!editing)
            Positioned(
              left: 0,
              top: 0,
              child: SafeArea(
                right: false,
                bottom: false,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onExitCornerTap,
                  ),
                ),
              ),
            ),
        ],
      ),
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
      final visibleCount = s.arrangement.applyRange(s.items).length;
      final estimate =
          s.arrangement.yDistance +
          80 +
          (visibleCount * (s.arrangement.itemFontSize + 10));
      maxY = math.max(maxY, estimate.toDouble());
    }
    for (final p in board.pictures) {
      if (p.arrangement.isBoardBackground) continue;
      maxY = math.max(maxY, p.y + p.arrangement.pictureDisplayHeight);
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
    if (_selectedId != id) {
      setState(() => _selectedId = id);
    }
    _boardFocus.requestFocus();
  }

  bool get _isTypingInField {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary == _boardFocus) return false;
    final ctx = primary.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  KeyEventResult _onBoardKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final editing = context.read<BillboardController>().layoutEditing;
    if (!editing || _selectedId == null || _isTypingInField) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _deleteSelectedBlock();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _enterLayoutEdit() {
    final c = context.read<BillboardController>();
    setState(() {
      _chromeHidden = false;
      _selectedId = null;
    });
    c.beginLayoutEdit();
  }

  Future<void> _addMenuSection() async {
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);
    final classes = await c.listMenuClasses();
    if (!mounted) return;
    if (classes.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(c.errorMessage ?? 'No menu classes found in POS'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
      return;
    }

    final picked = await showDialog<MenuClassOption>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121824),
          title: const Text(
            'Add menu section',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 360,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: classes.length,
              itemBuilder: (_, i) {
                final opt = classes[i];
                return ListTile(
                  title: Text(
                    opt.name.isEmpty ? 'Class #${opt.classId}' : opt.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(ctx).pop(opt),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (picked == null || !mounted) return;

    final id = await c.addMenuBlock(
      classId: picked.classId,
      className: picked.name,
    );
    if (!mounted) return;
    if (id == null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(c.errorMessage ?? 'Could not add menu section'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
      return;
    }
    setState(() => _selectedId = id);
  }

  Future<void> _addOfferSection() async {
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);
    final offers = await c.listSpecialOffers(forceRefresh: true);
    if (!mounted) return;
    if (offers.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            c.errorMessage ?? 'No specials found in POS (dates_special)',
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
      return;
    }

    final picked = await showDialog<SpecialOfferOption>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121824),
          title: const Text(
            'Add special / offer',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 420,
            height: 420,
            child: ListView.separated(
              itemCount: offers.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              itemBuilder: (_, i) {
                final opt = offers[i];
                return ListTile(
                  leading: const Icon(
                    Icons.local_offer_outlined,
                    color: Colors.white70,
                  ),
                  title: Text(
                    opt.name.trim().isEmpty
                        ? 'Special #${opt.id}'
                        : opt.name.trim(),
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    [
                      'ID ${opt.id}',
                      if (opt.subtitle.isNotEmpty) opt.subtitle,
                    ].join(' · '),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(opt),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (picked == null || !mounted) return;

    final id = await c.addOfferBlock(
      offerId: picked.id,
      offerName: picked.name,
    );
    if (!mounted) return;
    if (id == null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(c.errorMessage ?? 'Could not add special'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
      return;
    }
    setState(() => _selectedId = id);
  }

  Future<void> _addRotatingOffers() async {
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);
    final offers = await c.listSpecialOffers(forceRefresh: true);
    if (!mounted) return;
    if (offers.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            c.errorMessage ?? 'No specials found in POS (dates_special)',
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
      return;
    }

    final result =
        await showDialog<({List<SpecialOfferOption> offers, int seconds})>(
          context: context,
          builder: (ctx) => _RotatingOffersDialog(offers: offers),
        );
    if (result == null || !mounted) return;
    if (result.offers.isEmpty) return;

    final ids = await c.addRotatingOfferBlocks(
      offers: result.offers,
      secondsPerSlide: result.seconds,
    );
    if (!mounted) return;
    if (ids.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(c.errorMessage ?? 'Could not add rotating specials'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
      return;
    }
    setState(() => _selectedId = ids.last);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ids.length == 1
              ? 'Added 1 special — turn on Preview rotation or add another slide'
              : 'Added ${ids.length} specials in one spot · Preview is on',
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _addPhotoBlock() async {
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);
    final id = await c.addPhotoBlock();
    if (!mounted) return;
    if (id == null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(c.errorMessage ?? 'Could not add photo block'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
      return;
    }
    setState(() => _selectedId = id);
  }

  Future<void> _deleteSelectedBlock() async {
    final id = _selectedId;
    if (id == null) return;
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) {
        void accept() => Navigator.of(ctx, rootNavigator: true).pop(true);
        void cancel() => Navigator.of(ctx, rootNavigator: true).pop(false);
        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter) {
              accept();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.escape) {
              cancel();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: AlertDialog(
            backgroundColor: const Color(0xFF121824),
            title: const Text(
              'Delete block?',
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              'Remove block #$id from bb_arrangement?\n'
              'This cannot be undone from the app.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: cancel,
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: accept,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final ok = await c.deleteArrangement(id);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(c.errorMessage ?? 'Could not delete block #$id'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
      return;
    }
    setState(() => _selectedId = null);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted block #$id'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Returns a path that is safe to store in MySQL `latin1` columns.
  ///
  /// If the picked path already is latin1-safe, keep it. Otherwise copy into
  /// app documents under a sanitized filename (macOS often has U+202F in
  /// names like "… p.m.mp4").
  Future<String?> _localPathForPicked(PlatformFile file) async {
    final existing = file.path?.trim() ?? '';
    final rawName = file.name.isNotEmpty
        ? file.name
        : (existing.isNotEmpty ? p.basename(existing) : 'media.bin');
    final safeName = UnicodeText.safeFileName(rawName);
    final needsCopy = existing.isEmpty ||
        UnicodeText.mysqlSafe(existing) != existing ||
        safeName != rawName;

    if (!needsCopy) return existing;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final dest = File(
        p.join(
          dir.path,
          'bb_media',
          '${DateTime.now().millisecondsSinceEpoch}_$safeName',
        ),
      );
      await dest.parent.create(recursive: true);
      if (existing.isNotEmpty) {
        await File(existing).copy(dest.path);
      } else {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) return null;
        await dest.writeAsBytes(bytes, flush: true);
      }
      return dest.path;
    } on Object {
      // Fall back to original path if copy fails (may still fail MySQL save).
      return existing.isNotEmpty ? existing : null;
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
      final name = UnicodeText.safeFileName(
        file.name.isNotEmpty
            ? file.name
            : (path != null ? p.basename(path) : 'video'),
      );
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

  Future<void> _browseSelectedMediaFile(ArrangementMediaType mediaType) async {
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);
    final id = _selectedId;
    if (id == null) return;
    if (mediaType == ArrangementMediaType.none) return;

    PictureBlock? pic;
    for (final p in c.board?.pictures ?? const <PictureBlock>[]) {
      if (p.arrangement.id == id) {
        pic = p;
        break;
      }
    }
    if (pic == null) return;

    try {
      final files = await FilePicker.pickFiles(
        type: mediaType == ArrangementMediaType.video
            ? FileType.video
            : FileType.image,
      );
      if (files.isEmpty) return;
      final file = files.first;
      final path = await _localPathForPicked(file) ?? '';
      final name = UnicodeText.safeFileName(
        file.name.isNotEmpty
            ? file.name
            : (path.isNotEmpty ? p.basename(path) : 'media'),
      );

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
        mediaFile: mediaType == ArrangementMediaType.video
            ? (path.isNotEmpty ? path : name)
            : name,
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

  Future<void> _clearSelectedBlockMedia() async {
    final id = _selectedId;
    if (id == null) return;
    final c = context.read<BillboardController>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await c.clearBlockMedia(id);
    if (!mounted) return;
    if (ok) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(c.errorMessage ?? 'Could not clear media'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }
}

/// Selector key so the canvas ignores dirty/saving-only notifies.
class _CanvasKey {
  const _CanvasKey({
    required this.board,
    required this.editing,
    required this.customerDisplay,
    required this.activeRotationId,
    required this.previewRotation,
    required this.selectedId,
  });

  final BillboardBoard board;
  final bool editing;
  final bool customerDisplay;
  final int? activeRotationId;
  final bool previewRotation;
  final int? selectedId;

  @override
  bool operator ==(Object other) =>
      other is _CanvasKey &&
      identical(board, other.board) &&
      editing == other.editing &&
      customerDisplay == other.customerDisplay &&
      activeRotationId == other.activeRotationId &&
      previewRotation == other.previewRotation &&
      selectedId == other.selectedId;

  @override
  int get hashCode => Object.hash(
    identityHashCode(board),
    editing,
    customerDisplay,
    activeRotationId,
    previewRotation,
    selectedId,
  );
}

class _ChromeKey {
  const _ChromeKey({
    required this.board,
    required this.dirty,
    required this.saving,
    required this.creating,
    required this.uploading,
    required this.customerDisplay,
    required this.selectedId,
  });

  final BillboardBoard board;
  final bool dirty;
  final bool saving;
  final bool creating;
  final bool uploading;
  final bool customerDisplay;
  final int? selectedId;

  @override
  bool operator ==(Object other) =>
      other is _ChromeKey &&
      identical(board, other.board) &&
      dirty == other.dirty &&
      saving == other.saving &&
      creating == other.creating &&
      uploading == other.uploading &&
      customerDisplay == other.customerDisplay &&
      selectedId == other.selectedId;

  @override
  int get hashCode => Object.hash(
    identityHashCode(board),
    dirty,
    saving,
    creating,
    uploading,
    customerDisplay,
    selectedId,
  );
}

class _BoardCanvasLayer extends StatelessWidget {
  const _BoardCanvasLayer({
    required this.board,
    required this.editing,
    required this.customerDisplay,
    required this.selectedId,
    required this.screen,
    required this.maxBlockWidth,
    required this.maxPos,
    required this.onToggleChrome,
    required this.onSelectBlock,
    required this.onClearSelection,
    required this.designWidth,
    required this.designHeight,
    required this.withSelectedOnTop,
  });

  final BillboardBoard board;
  final bool editing;
  final bool customerDisplay;
  final int? selectedId;
  final Size screen;
  final int maxBlockWidth;
  final int maxPos;
  final VoidCallback onToggleChrome;
  final ValueChanged<int> onSelectBlock;
  final VoidCallback onClearSelection;
  final double Function(BillboardBoard) designWidth;
  final double Function(BillboardBoard) designHeight;
  final List<T> Function<T>(List<T> items, int Function(T) idOf)
      withSelectedOnTop;

  @override
  Widget build(BuildContext context) {
    final c = context.read<BillboardController>();
    // Live ticket panel only while POS has an active non-empty order.
    // When empty/cleared, hide entirely and use the full board.
    final liveReady =
        context.select((LiveOrderController l) => l.config.isReady);
    final liveTicket =
        context.select((LiveOrderController l) => l.showCustomerTicket);
    final showOrderPanel = customerDisplay &&
        (!liveReady || liveTicket);
    final designW = designWidth(board);
    final designH = designHeight(board);

    final pictures = withSelectedOnTop([
      for (final p in board.pictures)
        if (c.isArrangementVisible(p.arrangement)) p,
    ], (p) => p.arrangement.id);
    final sections = withSelectedOnTop([
      for (final s in board.sections)
        if (c.isArrangementVisible(s.arrangement)) s,
    ], (s) => s.arrangement.id);
    final bgPictures = board.boardBackgroundPictures;
    final activeBgPictures =
        bgPictures.length <= 1 ? bgPictures : bgPictures.take(1).toList();
    final fgPictures = [
      for (final p in pictures)
        if (!p.arrangement.isBoardBackground) p,
    ];
    final orderColW = showOrderPanel
        ? (c.poleDisplayWidth >= 280
              ? c.poleDisplayWidth.toDouble()
              : _customerDisplayWidth(screen.width))
        : 0.0;
    final bg = QbColors.of(board.mainBackColor);

    final floating = context.select(
      (BillboardController c) => c.poleDisplayFloating,
    );
    final boardView = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: editing ? null : onToggleChrome,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return InteractiveViewer(
                    panEnabled: false,
                    scaleEnabled: false,
                    minScale: 0.4,
                    maxScale: 3,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (activeBgPictures.isEmpty) ColoredBox(color: bg),
                          for (final pic in activeBgPictures)
                            Positioned.fill(
                              key: ValueKey('bg-${pic.arrangement.id}'),
                              child: editing
                                  ? GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () =>
                                          onSelectBlock(pic.arrangement.id),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: selectedId ==
                                                    pic.arrangement.id
                                                ? CamaleonColors.green
                                                : Colors.transparent,
                                            width: 3,
                                          ),
                                        ),
                                        child: BillboardPicturePanel(
                                          block: pic,
                                          fit: BoxFit.fill,
                                        ),
                                      ),
                                    )
                                  : BillboardPicturePanel(
                                      block: pic,
                                      fit: BoxFit.fill,
                                    ),
                            ),
                          FittedBox(
                            fit: BoxFit.contain,
                            // topLeft so x=0 blocks sit on the left edge
                            // (topCenter letterboxed and blocked "further left").
                            alignment: Alignment.topLeft,
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
                                        onTap: onClearSelection,
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
                                            maxBlockWidth.toDouble(),
                                          ),
                                      editing: editing,
                                      selected:
                                          selectedId == section.arrangement.id,
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
                                          '${section.arrangement.rangeItems}-'
                                          '${section.arrangement.offerId}-'
                                          '${section.arrangement.displayOrder}-'
                                          '${section.arrangement.displaySeconds}-'
                                          '${section.className}-'
                                          '${Object.hashAll([
                                            for (final i in section.items)
                                              Object.hash(
                                                i.itemId,
                                                i.name,
                                                i.price,
                                                i.description,
                                              ),
                                          ])}',
                                      onSelect: () =>
                                          onSelectBlock(section.arrangement.id),
                                      onDragStarted: c.markLayoutDirty,
                                      onCommit: (x, y, width, height) {
                                        c.commitArrangementGeometry(
                                          arrangementId:
                                              section.arrangement.id,
                                          xDistance: x,
                                          yDistance: y,
                                          maxWidth: width.round(),
                                          maxX: maxPos,
                                          maxY: maxPos,
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
                                          .clamp(40, maxBlockWidth.toDouble()),
                                      height:
                                          pic.arrangement.pictureDisplayHeight,
                                      editing: editing,
                                      selected:
                                          selectedId == pic.arrangement.id,
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
                                      onSelect: () =>
                                          onSelectBlock(pic.arrangement.id),
                                      onDragStarted: c.markLayoutDirty,
                                      onCommit: (x, y, width, height) {
                                        c.commitArrangementGeometry(
                                          arrangementId: pic.arrangement.id,
                                          xDistance: x,
                                          yDistance: y,
                                          maxWidth: width.round(),
                                          minWidth: 80,
                                          maxX: maxPos,
                                          maxY: maxPos,
                                        );
                                      },
                                      child: BillboardPicturePanel(
                                        block: pic,
                                        framed: context.select(
                                          (BillboardController c) =>
                                              c.mediaFrame,
                                        ),
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
            );
    if (showOrderPanel && floating) {
      return Stack(
        fit: StackFit.expand,
        children: [
          boardView,
          _FloatingCustomerDisplay(
            editing: editing,
            width: orderColW,
            left: c.poleDisplayLeft,
            top: c.poleDisplayTop,
            height: c.poleDisplayHeight.toDouble(),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: boardView),
        if (showOrderPanel) ...[
          Container(
            width: 1,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          CustomerOrderBoardPanel(width: orderColW),
        ],
      ],
    );
  }
}

double _customerDisplayWidth(double screenW) {
  if (screenW >= 1600) return 560;
  if (screenW >= 1280) return 480;
  if (screenW >= 1024) return 420;
  if (screenW >= 800) return 360;
  return (screenW * 0.5).clamp(300.0, 360.0);
}

class _FloatingCustomerDisplay extends StatefulWidget {
  const _FloatingCustomerDisplay({
    required this.editing,
    required this.width,
    required this.left,
    required this.top,
    required this.height,
  });

  final bool editing;
  final double width;
  final double left;
  final double top;
  final double height;

  @override
  State<_FloatingCustomerDisplay> createState() =>
      _FloatingCustomerDisplayState();
}

class _FloatingCustomerDisplayState extends State<_FloatingCustomerDisplay> {
  late double _left = widget.left;
  late double _top = widget.top;
  late double _width = widget.width;
  late double _height = widget.height;

  @override
  void didUpdateWidget(covariant _FloatingCustomerDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.left != widget.left) _left = widget.left;
    if (oldWidget.top != widget.top) _top = widget.top;
    if (oldWidget.width != widget.width) _width = widget.width;
    if (oldWidget.height != widget.height) _height = widget.height;
  }

  void _place(BoxConstraints box) {
    final h = _height >= 240 ? _height : box.maxHeight * 0.72;
    final w = _width.clamp(280.0, box.maxWidth);
    final left = _left < 0 ? box.maxWidth - w - 12 : _left;
    if (_height != h || _width != w || _left != left) {
      _height = h;
      _width = w;
      _left = left;
    }
  }

  void _save() {
    context.read<BillboardController>().setPoleDisplayFrame(
          left: _left,
          top: _top,
          width: _width.round(),
          height: _height.round(),
        );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _place(box);
        final maxL = (box.maxWidth - _width).clamp(0.0, box.maxWidth);
        final maxT = (box.maxHeight - _height).clamp(0.0, box.maxHeight);
        _left = _left.clamp(0.0, maxL);
        _top = _top.clamp(0.0, maxT);
        return Stack(
          children: [
            Positioned(
              left: _left,
              top: _top,
              width: _width,
              height: _height,
              child: Material(
                elevation: 8,
                clipBehavior: Clip.antiAlias,
                color: Colors.transparent,
                child: Stack(
                  children: [
                    CustomerOrderBoardPanel(width: _width),
                    if (widget.editing)
                      Positioned(
                        left: 0,
                        right: 28,
                        top: 0,
                        height: 28,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (d) {
                            setState(() {
                              _left = (_left + d.delta.dx).clamp(0.0, maxL);
                              _top = (_top + d.delta.dy).clamp(0.0, maxT);
                            });
                          },
                          onPanEnd: (_) => _save(),
                          child: const ColoredBox(
                            color: Color(0x66000000),
                            child: Center(
                              child: Text(
                                'Drag',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (widget.editing)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        width: 28,
                        height: 28,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (d) {
                            setState(() {
                              _width = (_width + d.delta.dx)
                                  .clamp(280.0, box.maxWidth);
                              _height = (_height + d.delta.dy)
                                  .clamp(240.0, box.maxHeight);
                            });
                          },
                          onPanEnd: (_) => _save(),
                          child: const ColoredBox(
                            color: Color(0xCC000000),
                            child: Icon(
                              Icons.open_in_full,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EditChrome extends StatelessWidget {
  const _EditChrome({
    required this.selectedId,
    required this.board,
    required this.saving,
    required this.dirty,
    required this.uploadingBackground,
    required this.creatingBlock,
    required this.sidePanel,
    required this.dockTop,
    required this.sideWidth,
    required this.onCancel,
    required this.onSave,
    required this.onBoardBackgroundColor,
    required this.onPickBackgroundImage,
    required this.onPickBackgroundVideo,
    required this.onClearBackgroundImage,
    required this.onPickBlockImage,
    required this.onPickBlockVideo,
    required this.onClearBlockMedia,
    required this.onAddMenuSection,
    required this.onAddOfferSection,
    required this.onAddRotatingOffers,
    required this.onAddPhotoBlock,
    required this.onDeleteBlock,
    required this.onStylePatch,
    required this.customerDisplay,
    required this.onCustomerDisplayChanged,
  });

  final int? selectedId;
  final BillboardBoard board;
  final bool saving;
  final bool dirty;
  final bool uploadingBackground;
  final bool creatingBlock;
  final bool customerDisplay;
  final bool sidePanel;
  final bool dockTop;
  final double sideWidth;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final ValueChanged<int> onBoardBackgroundColor;
  final VoidCallback onPickBackgroundImage;
  final VoidCallback onPickBackgroundVideo;
  final VoidCallback onClearBackgroundImage;
  final VoidCallback onPickBlockImage;
  final VoidCallback onPickBlockVideo;
  final VoidCallback onClearBlockMedia;
  final VoidCallback onAddMenuSection;
  final VoidCallback onAddOfferSection;
  final VoidCallback onAddRotatingOffers;
  final VoidCallback onAddPhotoBlock;
  final VoidCallback onDeleteBlock;
  final StylePatch onStylePatch;
  final ValueChanged<bool> onCustomerDisplayChanged;

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
      onPickBlockImage: onPickBlockImage,
      onPickBlockVideo: onPickBlockVideo,
      onClearBlockMedia: onClearBlockMedia,
      onAddMenuSection: onAddMenuSection,
      onAddOfferSection: onAddOfferSection,
      onAddRotatingOffers: onAddRotatingOffers,
      onAddPhotoBlock: onAddPhotoBlock,
      onDeleteBlock: onDeleteBlock,
      creatingBlock: creatingBlock,
      customerDisplay: customerDisplay,
      onCustomerDisplayChanged: onCustomerDisplayChanged,
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
                    ? (dirty
                          ? 'Unsaved changes · Save to keep them'
                          : 'Create or tap a block · Close when finished')
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
                                : 'Create content · then tune the board',
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
                    maxHeight: hasSelection ? 340 : 360,
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
                      const Flexible(
                        child: Text(
                          'Edit mode',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
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
                            color: CamaleonColors.orange.withValues(
                              alpha: 0.25,
                            ),
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: saving ? null : onCancel,
                    child: Text(dirty ? 'Discard' : 'Close'),
                  ),
                  if (dirty) ...[
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: saving ? null : onSave,
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
                ],
              ),
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

  double get _height =>
      widget.lockAspectHeight ? _width * 0.75 : (widget.height ?? 0);

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
                          color: CamaleonColors.green.withValues(alpha: 0.35),
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
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

/// Multi-select POS specials + seconds-per-slide for one-tap rotation setup.
class _RotatingOffersDialog extends StatefulWidget {
  const _RotatingOffersDialog({required this.offers});

  final List<SpecialOfferOption> offers;

  @override
  State<_RotatingOffersDialog> createState() => _RotatingOffersDialogState();
}

class _RotatingOffersDialogState extends State<_RotatingOffersDialog> {
  final Set<int> _selected = {};
  int _seconds = 8;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF121824),
      title: const Text(
        'Rotating specials',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 440,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pick 2 or more. They stack in the same place and take turns.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Seconds each',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () =>
                      setState(() => _seconds = (_seconds - 1).clamp(1, 120)),
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  '$_seconds s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _seconds = (_seconds + 1).clamp(1, 120)),
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: widget.offers.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                itemBuilder: (_, i) {
                  final opt = widget.offers[i];
                  final checked = _selected.contains(opt.id);
                  return CheckboxListTile(
                    value: checked,
                    activeColor: CamaleonColors.green,
                    checkColor: Colors.black,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      opt.name.trim().isEmpty
                          ? 'Special #${opt.id}'
                          : opt.name.trim(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      [
                        'ID ${opt.id}',
                        if (opt.subtitle.isNotEmpty) opt.subtitle,
                      ].join(' · '),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(opt.id);
                        } else {
                          _selected.remove(opt.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final picked = [
                    for (final o in widget.offers)
                      if (_selected.contains(o.id)) o,
                  ];
                  Navigator.of(
                    context,
                  ).pop((offers: picked, seconds: _seconds));
                },
          child: Text(
            _selected.isEmpty
                ? 'Add'
                : 'Add ${_selected.length} · ${_seconds}s each',
          ),
        ),
      ],
    );
  }
}
