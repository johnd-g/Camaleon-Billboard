/// Sanitize text for MySQL columns that are often `latin1` (Error 1366).
///
/// macOS paths frequently include:
/// - NFD accents (`o` + U+0301)
/// - Unicode spaces (U+202F narrow no-break before "p.m.", NBSP, …)
class UnicodeText {
  UnicodeText._();

  static final _combining = RegExp(r'[\u0300-\u036f]');

  /// NFC where possible, then force latin1-safe code points.
  static String mysqlSafe(String input) {
    if (input.isEmpty) return input;
    var s = input;
    if (_combining.hasMatch(s)) {
      s = _stripLeftoverMarks(_toNfc(s));
    }
    return _toLatin1(s);
  }

  /// Filesystem-safe basename (latin1 + no path separators).
  static String safeFileName(String raw) {
    var name = mysqlSafe(raw).trim();
    if (name.isEmpty) return 'media.bin';
    name = name
        .replaceAll(RegExp(r'[\\/]+'), '_')
        .replaceAll(RegExp(r'[\x00-\x1F]+'), '_');
    return name;
  }

  static String _stripLeftoverMarks(String s) => s.replaceAll(_combining, '');

  static String _toLatin1(String s) {
    final out = StringBuffer();
    var changed = false;
    for (final r in s.runes) {
      // Unicode spaces → ASCII space
      if (r == 0x00A0 || // NBSP
          r == 0x202F || // narrow no-break space (… p.m.)
          r == 0x2007 ||
          r == 0x2008 ||
          r == 0x2009 ||
          r == 0x200A ||
          r == 0x205F ||
          r == 0x3000) {
        out.write(' ');
        changed = true;
        continue;
      }
      if (r <= 0xFF) {
        out.writeCharCode(r);
        continue;
      }
      // Drop / replace anything outside latin1 (e.g. smart quotes, emoji).
      out.write('_');
      changed = true;
    }
    return changed ? out.toString() : s;
  }

  /// Compose base + one Latin combining mark when a precomposed form exists.
  static String _toNfc(String input) {
    final out = StringBuffer();
    final runes = input.runes.toList(growable: false);
    for (var i = 0; i < runes.length; i++) {
      final base = runes[i];
      if (i + 1 < runes.length) {
        final mark = runes[i + 1];
        if (mark >= 0x0300 && mark <= 0x036F) {
          final composed = _compose(base, mark);
          if (composed != null) {
            out.writeCharCode(composed);
            i++;
            continue;
          }
        }
      }
      out.writeCharCode(base);
    }
    return out.toString();
  }

  static int? _compose(int base, int mark) {
    // Prefer latin1 precomposed forms (0x00–0xFF) for MySQL latin1 columns.
    if (mark == 0x0301) {
      return switch (base) {
        0x41 => 0xC1,
        0x45 => 0xC9,
        0x49 => 0xCD,
        0x4F => 0xD3,
        0x55 => 0xDA,
        0x59 => 0xDD,
        0x61 => 0xE1,
        0x65 => 0xE9,
        0x69 => 0xED,
        0x6F => 0xF3,
        0x75 => 0xFA,
        0x79 => 0xFD,
        _ => null,
      };
    }
    if (mark == 0x0300) {
      return switch (base) {
        0x41 => 0xC0,
        0x45 => 0xC8,
        0x49 => 0xCC,
        0x4F => 0xD2,
        0x55 => 0xD9,
        0x61 => 0xE0,
        0x65 => 0xE8,
        0x69 => 0xEC,
        0x6F => 0xF2,
        0x75 => 0xF9,
        _ => null,
      };
    }
    if (mark == 0x0302) {
      return switch (base) {
        0x41 => 0xC2,
        0x45 => 0xCA,
        0x49 => 0xCE,
        0x4F => 0xD4,
        0x55 => 0xDB,
        0x61 => 0xE2,
        0x65 => 0xEA,
        0x69 => 0xEE,
        0x6F => 0xF4,
        0x75 => 0xFB,
        _ => null,
      };
    }
    if (mark == 0x0303) {
      return switch (base) {
        0x41 => 0xC3,
        0x4E => 0xD1,
        0x4F => 0xD5,
        0x61 => 0xE3,
        0x6E => 0xF1,
        0x6F => 0xF5,
        _ => null,
      };
    }
    if (mark == 0x0308) {
      return switch (base) {
        0x41 => 0xC4,
        0x45 => 0xCB,
        0x49 => 0xCF,
        0x4F => 0xD6,
        0x55 => 0xDC,
        0x61 => 0xE4,
        0x65 => 0xEB,
        0x69 => 0xEF,
        0x6F => 0xF6,
        0x75 => 0xFC,
        0x79 => 0xFF,
        _ => null,
      };
    }
    if (mark == 0x0327) {
      return switch (base) {
        0x43 => 0xC7,
        0x63 => 0xE7,
        _ => null,
      };
    }
    return null;
  }
}
