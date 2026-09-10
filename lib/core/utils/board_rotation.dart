import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';

/// Playlist of board blocks that cycle by [ArrangementBlock.displaySeconds].
///
/// Rules (supermarket / promo TVs):
/// - `display_seconds <= 0` → always visible (static menu / chrome).
/// - `display_seconds > 0` → enters the rotation queue, sorted by
///   `display_order` then `id`. Only one rotating block is shown at a time.
/// - Board-background media never rotates away.
abstract final class BoardRotation {
  static List<ArrangementBlock> playlist(BillboardBoard board) {
    final blocks = <ArrangementBlock>[
      for (final s in board.sections) s.arrangement,
      for (final p in board.pictures)
        if (!p.arrangement.isBoardBackground) p.arrangement,
    ];
    final rotating = [
      for (final a in blocks)
        if (a.displaySeconds > 0) a,
    ];
    rotating.sort((a, b) {
      final byOrder = a.displayOrder.compareTo(b.displayOrder);
      if (byOrder != 0) return byOrder;
      return a.id.compareTo(b.id);
    });
    return rotating;
  }

  /// Shared x/y/width of the first rotating block (for stacking new slides).
  static (int x, int y, int width)? sharedSlot(BillboardBoard board) {
    final list = playlist(board);
    if (list.isEmpty) return null;
    final a = list.first;
    return (a.xDistance, a.yDistance, a.maxWidth);
  }

  static bool isVisible(
    ArrangementBlock a, {
    required bool editing,
    required bool previewRotation,
    required int? activeRotationId,
    required bool hasRotationPlaylist,
  }) {
    // Edit mode shows everything unless the user turns on live preview.
    if (editing && !previewRotation) return true;
    if (a.isBoardBackground) return true;
    if (a.displaySeconds <= 0) return true;
    if (!hasRotationPlaylist) return true;
    return a.id == activeRotationId;
  }
}
