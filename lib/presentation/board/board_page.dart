import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:camaleon_billboard/core/theme/camaleon_theme.dart';
import 'package:camaleon_billboard/core/utils/qb_color.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';
import 'package:camaleon_billboard/presentation/billboard_controller.dart';
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
                      child: FittedBox(
                        fit: BoxFit.contain,
                        // Top-align: centered letterboxing blocked dragging "up".
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
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        setState(() => _selectedId = null),
                                  ),
                                ),
                              for (final pic in pictures)
                                _BoardBlock(
                                  key: ValueKey('pic-${pic.arrangement.id}'),
                                  x: pic.x.toDouble(),
                                  y: pic.y.toDouble(),
                                  width: 420,
                                  height: 320,
                                  editing: editing,
                                  selected:
                                      _selectedId == pic.arrangement.id,
                                  resizable: false,
                                  onSelect: () =>
                                      _selectBlock(pic.arrangement.id),
                                  onDragStarted: c.markLayoutDirty,
                                  onCommit: (x, y, width) {
                                    c.commitArrangementGeometry(
                                      arrangementId: pic.arrangement.id,
                                      xDistance: x,
                                      yDistance: y,
                                      maxX: _maxPos,
                                      maxY: _maxPos,
                                    );
                                  },
                                  child: BillboardPicturePanel(block: pic),
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
                                      .clamp(120, _maxBlockWidth.toDouble()),
                                  editing: editing,
                                  selected: _selectedId ==
                                      section.arrangement.id,
                                  resizable: true,
                                  contentRevision:
                                      '${section.arrangement.classFontSize}-'
                                      '${section.arrangement.itemFontSize}-'
                                      '${section.arrangement.maxWidth}-'
                                      '${section.items.length}',
                                  onSelect: () => _selectBlock(
                                    section.arrangement.id,
                                  ),
                                  onDragStarted: c.markLayoutDirty,
                                  onCommit: (x, y, width) {
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
                                  child: MenuSectionPanel(section: section),
                                ),
                              if (board.sections.isEmpty &&
                                  board.pictures.isEmpty)
                                const Center(
                                  child: Text(
                                    'No bb_arrangement rows for this computer name.\n'
                                    'Configure screens in Camaleon POS → Billboard.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (editing)
            _EditChrome(
              selectedId: _selectedId,
              board: board,
              saving: c.savingLayout,
              dirty: c.layoutDirty,
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
              onNudgeClass: (d) {
                final id = _selectedId;
                if (id == null) return;
                c.nudgeFonts(arrangementId: id, classDelta: d);
              },
              onNudgeItem: (d) {
                final id = _selectedId;
                if (id == null) return;
                c.nudgeFonts(arrangementId: id, itemDelta: d);
              },
              onResizeWidth: (w) {
                final id = _selectedId;
                if (id == null) return;
                c.resizeArrangement(arrangementId: id, maxWidth: w);
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
                        onPressed: () => c.reloadSilent(),
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
      maxX = math.max(maxX, (p.x + 420).toDouble());
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
      maxY = math.max(maxY, (p.y + 320).toDouble());
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
}

class _EditChrome extends StatelessWidget {
  const _EditChrome({
    required this.selectedId,
    required this.board,
    required this.saving,
    required this.dirty,
    required this.sidePanel,
    required this.dockTop,
    required this.sideWidth,
    required this.onCancel,
    required this.onSave,
    required this.onNudgeClass,
    required this.onNudgeItem,
    required this.onResizeWidth,
  });

  final int? selectedId;
  final BillboardBoard board;
  final bool saving;
  final bool dirty;
  final bool sidePanel;
  final bool dockTop;
  final double sideWidth;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final ValueChanged<int> onNudgeClass;
  final ValueChanged<int> onNudgeItem;
  final ValueChanged<int> onResizeWidth;

  @override
  Widget build(BuildContext context) {
    MenuSection? selected;
    if (selectedId != null) {
      for (final s in board.sections) {
        if (s.arrangement.id == selectedId) {
          selected = s;
          break;
        }
      }
    }

    final editorBody = selected == null
        ? const _EmptySelectionHint()
        : _SelectedEditor(
            section: selected,
            onNudgeClass: onNudgeClass,
            onNudgeItem: onNudgeItem,
            onResizeWidth: onResizeWidth,
            compact: !sidePanel,
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
                hint: selected == null
                    ? 'Tap a block and drag it to move'
                    : (sidePanel
                        ? 'Adjust the block in the right panel'
                        : (dockTop
                            ? 'Adjust the block in the top panel'
                            : 'Adjust the block in the bottom panel')),
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
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Block settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
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
                    maxHeight: selected == null ? 88 : 200,
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

class _EmptySelectionHint extends StatelessWidget {
  const _EmptySelectionHint();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.touch_app_outlined, color: CamaleonColors.green, size: 28),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No block selected',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Tap a menu section to change its font, width, and position.',
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectedEditor extends StatelessWidget {
  const _SelectedEditor({
    required this.section,
    required this.onNudgeClass,
    required this.onNudgeItem,
    required this.onResizeWidth,
    this.compact = false,
  });

  final MenuSection section;
  final ValueChanged<int> onNudgeClass;
  final ValueChanged<int> onNudgeItem;
  final ValueChanged<int> onResizeWidth;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final a = section.arrangement;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: CamaleonColors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  section.className,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              compact ? 'Settings' : 'Settings for this block',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        SizedBox(height: compact ? 8 : 12),
        _CompactRow(
          icon: Icons.title_rounded,
          label: 'Header',
          valueLabel: '${a.classFontSize} px',
          onMinus: () => onNudgeClass(-1),
          onPlus: () => onNudgeClass(1),
        ),
        SizedBox(height: compact ? 6 : 8),
        _CompactRow(
          icon: Icons.format_list_bulleted_rounded,
          label: 'Items',
          valueLabel: '${a.itemFontSize} px',
          onMinus: () => onNudgeItem(-1),
          onPlus: () => onNudgeItem(1),
        ),
        SizedBox(height: compact ? 6 : 8),
        _CompactRow(
          icon: Icons.swap_horiz_rounded,
          label: 'Width',
          valueLabel: '${a.maxWidth} px',
          onMinus: () => onResizeWidth(a.maxWidth - 20),
          onPlus: () => onResizeWidth(a.maxWidth + 20),
        ),
        if (!compact) ...[
          const SizedBox(height: 10),
          Text(
            'X ${a.xDistance} (from left) · Y ${a.yDistance} (from top)',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.onMinus,
    required this.onPlus,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: CamaleonColors.greenSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          _RoundIconButton(icon: Icons.remove_rounded, onPressed: onMinus),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 64,
              child: Text(
                valueLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          _RoundIconButton(icon: Icons.add_rounded, onPressed: onPlus),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white12,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// Local-geometry block: pan/resize update only this State until commit.
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
    this.contentRevision = '',
  });

  final double x;
  final double y;
  final double width;
  final double? height;
  final bool editing;
  final bool selected;
  final bool resizable;
  final String contentRevision;
  final VoidCallback onSelect;
  final VoidCallback? onDragStarted;
  final void Function(int x, int y, double width) onCommit;
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
    widget.onCommit(_x.round(), _y.round(), _width);
  }

  @override
  Widget build(BuildContext context) {
    final content = _content();
    if (!widget.editing) {
      return Positioned(
        left: _x,
        top: _y,
        width: _width,
        height: widget.height,
        child: content,
      );
    }

    return Positioned(
      left: _x,
      top: _y,
      width: _width,
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onPanStart: (_) {
          _dragging = true;
          // Select after this frame — setState during panStart cancels the drag.
          final select = widget.onSelect;
          final dirty = widget.onDragStarted;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            select();
            dirty?.call();
          });
        },
        onPanUpdate: (d) {
          // Allow a little negative headroom so blocks can sit under the top bar.
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
          // Don't commit a cancelled tiny pan as a move; just end drag flag.
          if (_dragging) _commit();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.selected
                      ? CamaleonColors.green
                      : Colors.white38,
                  width: widget.selected ? 2.5 : 1,
                ),
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
                    final nw =
                        (_width + d.delta.dx).clamp(120.0, 20000.0).toDouble();
                    if (nw == _width) return;
                    setState(() => _width = nw);
                  },
                  onPanEnd: (_) => _commit(),
                  onPanCancel: _commit,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ResizeHandle(),
                        SizedBox(height: 4),
                        _ResizeLabel(),
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
  const _ResizeHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 44,
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
      child: const Icon(
        Icons.swap_horiz_rounded,
        size: 16,
        color: Colors.white,
      ),
    );
  }
}

class _ResizeLabel extends StatelessWidget {
  const _ResizeLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'Width',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
