import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Curated fonts for billboard sections.
///
/// [id] is what we store in Classic columns `classfname` / `itemfname` /
/// `modfname` (Windows-style names when possible so POS stays compatible).
class BoardFontOption {
  const BoardFontOption({
    required this.id,
    required this.label,
    required this.sample,
  });

  final String id;
  final String label;
  final String sample;
}

abstract final class BoardFonts {
  static const options = <BoardFontOption>[
    BoardFontOption(id: '', label: 'Default', sample: 'Aa'),
    BoardFontOption(id: 'Arial', label: 'Arial', sample: 'Aa'),
    BoardFontOption(id: 'Roboto', label: 'Roboto', sample: 'Aa'),
    BoardFontOption(id: 'Montserrat', label: 'Montserrat', sample: 'Aa'),
    BoardFontOption(id: 'Oswald', label: 'Oswald', sample: 'Aa'),
    BoardFontOption(id: 'Impact', label: 'Impact', sample: 'Aa'),
    BoardFontOption(id: 'Verdana', label: 'Verdana', sample: 'Aa'),
    BoardFontOption(id: 'Times New Roman', label: 'Times', sample: 'Aa'),
    BoardFontOption(id: 'Georgia', label: 'Georgia', sample: 'Aa'),
    BoardFontOption(id: 'Courier New', label: 'Courier', sample: 'Aa'),
    BoardFontOption(id: 'Comic Sans MS', label: 'Comic', sample: 'Aa'),
  ];

  static String labelFor(String id) {
    final n = id.trim();
    for (final o in options) {
      if (o.id.toLowerCase() == n.toLowerCase()) return o.label;
    }
    return n.isEmpty ? 'Default' : n;
  }

  /// Match a stored Classic name to a known option id (or keep raw).
  static String normalizeId(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return '';
    for (final o in options) {
      if (o.id.toLowerCase() == n.toLowerCase()) return o.id;
    }
    return n;
  }

  static TextStyle apply(String fontName, TextStyle base) {
    final key = fontName.trim().toLowerCase();
    if (key.isEmpty) return base;

    TextStyle merge(TextStyle styled) => styled.merge(
          TextStyle(
            color: base.color,
            fontSize: base.fontSize,
            fontWeight: base.fontWeight,
            fontStyle: base.fontStyle,
            height: base.height,
            letterSpacing: base.letterSpacing,
            decoration: base.decoration,
          ),
        );

    switch (key) {
      case 'arial':
      case 'helvetica':
        return merge(GoogleFonts.arimo());
      case 'roboto':
        return merge(GoogleFonts.roboto());
      case 'montserrat':
        return merge(GoogleFonts.montserrat());
      case 'oswald':
        return merge(GoogleFonts.oswald());
      case 'impact':
        return merge(GoogleFonts.anton());
      case 'verdana':
      case 'tahoma':
        return merge(GoogleFonts.openSans());
      case 'times new roman':
      case 'times':
        return merge(GoogleFonts.tinos());
      case 'georgia':
        return merge(GoogleFonts.merriweather());
      case 'courier new':
      case 'courier':
        return merge(GoogleFonts.courierPrime());
      case 'comic sans ms':
      case 'comic sans':
        return merge(GoogleFonts.comicNeue());
      default:
        // Unknown Classic name: try as raw family, fall back to default.
        return base.copyWith(fontFamily: fontName.trim());
    }
  }
}
