import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Decodes a Camaleon / generic QR payload from an image (gallery or camera photo).
class QrImageScanner {
  static String? decodePayload(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Downscale huge photos so zxing stays responsive on tablets.
    final image = decoded.width > 1600 || decoded.height > 1600
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 1600 : null,
            height: decoded.height > decoded.width ? 1600 : null,
          )
        : decoded;

    final source = RGBLuminanceSource(
      image.width,
      image.height,
      image
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.abgr)
          .buffer
          .asInt32List(),
    );

    final reader = QRCodeReader();
    for (final binarizer in [
      GlobalHistogramBinarizer(source),
      HybridBinarizer(source),
    ]) {
      try {
        final result = reader.decode(BinaryBitmap(binarizer));
        final text = result.text.trim();
        if (text.isNotEmpty) return text;
      } on Object {
        // try next binarizer
      }
    }
    return null;
  }
}
