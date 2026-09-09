import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'package:camaleon_billboard/app.dart';
import 'package:camaleon_billboard/core/errors/app_failure.dart';

Future<void> main() async {
  // Binding + runApp must share the same zone.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Official video_player has no Windows/Linux backend — fvp fills that gap.
    // Keep Android/iOS on the official implementation.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      fvp.registerWith(
        options: {
          'platforms': ['windows', 'linux', 'macos'],
        },
      );
    }

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (kDebugMode) {
        debugPrint('FlutterError: ${AppFailure.message(details.exception)}');
        debugPrint('${details.stack}');
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) {
        debugPrint('Uncaught: ${AppFailure.message(error)}');
        debugPrint('$stack');
      }
      return true;
    };

    runApp(const CamaleonBillboardApp());
  }, (error, stack) {
    if (kDebugMode) {
      debugPrint('Zone error: ${AppFailure.message(error)}');
      debugPrint('$stack');
    }
  });
}
