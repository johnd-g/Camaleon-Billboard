import 'package:flutter/material.dart';

import 'package:camaleon_billboard/core/utils/qb_color.dart';
import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';

extension ArrangementBlockUi on ArrangementBlock {
  BoxFit get mediaBoxFit => switch (mediaFit) {
        ArrangementMediaFit.cover => BoxFit.cover,
        ArrangementMediaFit.contain => BoxFit.contain,
        ArrangementMediaFit.stretch => BoxFit.fill,
      };

  Border? get decorationBorder {
    if (!hasAnyBorder) return null;
    return Border(
      top: _side(borderTopWidth, borderTopColor),
      right: _side(borderRightWidth, borderRightColor),
      bottom: _side(borderBottomWidth, borderBottomColor),
      left: _side(borderLeftWidth, borderLeftColor),
    );
  }

  static BorderSide _side(int width, String colorRaw) {
    if (width <= 0) return BorderSide.none;
    return BorderSide(
      width: width.toDouble(),
      color: parseArrangementBorderColor(colorRaw),
    );
  }
}

/// POS stores QB index ("15"), hex ("#RRGGBB" / "RRGGBB"), or empty.
Color parseArrangementBorderColor(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return Colors.white;
  final qb = int.tryParse(s);
  if (qb != null) return QbColors.of(qb);
  var hex = s.startsWith('#') ? s.substring(1) : s;
  if (hex.length == 6) {
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  if (hex.length == 8) {
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(v);
  }
  return Colors.white;
}
