import 'package:flutter/material.dart';

/// VB6 `QBColor` palette used by Classic Billboard / KDS / POS setup.
class QbColors {
  QbColors._();

  /// Not a Classic QBColor — Flutter-only clear fill (shows board image through).
  static const int transparentIndex = -1;

  static const List<Color> palette = <Color>[
    Color(0xFF000000), // 0 black
    Color(0xFF000080), // 1 blue
    Color(0xFF008000), // 2 green
    Color(0xFF008080), // 3 cyan
    Color(0xFF800000), // 4 red
    Color(0xFF800080), // 5 magenta
    Color(0xFF808000), // 6 yellow
    Color(0xFFC0C0C0), // 7 light grey
    Color(0xFF808080), // 8 grey
    Color(0xFF0000FF), // 9 light blue
    Color(0xFF00FF00), // 10 light green
    Color(0xFF00FFFF), // 11 light cyan
    Color(0xFFFF0000), // 12 light red
    Color(0xFFFF00FF), // 13 light magenta
    Color(0xFFFFFF00), // 14 light yellow
    Color(0xFFFFFFFF), // 15 bright white
  ];

  static bool isTransparent(int index) => index == transparentIndex;

  static Color of(int index) {
    if (isTransparent(index)) return Colors.transparent;
    return palette[index.clamp(0, palette.length - 1)];
  }

  static int clampFill(int index) {
    if (isTransparent(index)) return transparentIndex;
    return index.clamp(0, palette.length - 1);
  }

  static int clampOpaque(int index) => index.clamp(0, palette.length - 1);

  static Color onColor(int index) {
    if (isTransparent(index)) return Colors.white;
    return ThemeData.estimateBrightnessForColor(of(index)) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }
}
