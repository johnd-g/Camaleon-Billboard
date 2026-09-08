import 'dart:convert';
import 'dart:typed_data';

class Utils {
  Utils._();

  static String? blobToString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Uint8List) return utf8.decode(value);
    if (value is List<int>) return utf8.decode(value);
    return value.toString();
  }

  static int? blobToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(blobToString(value)?.split('.').first ?? '');
  }

  static double? blobToDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(blobToString(value) ?? '');
  }

  static String str(dynamic v) => (blobToString(v) ?? '').trim();

  static int asInt(dynamic v, [int fallback = 0]) =>
      int.tryParse(str(v).split('.').first) ?? blobToInt(v) ?? fallback;

  static bool asFlag(dynamic v) => asInt(v, 0) != 0;
}
