import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Resolves the identifier Billboard reports as `bb_arrangement.comp_name`.
///
/// Related POS table `it_tregister`:
/// - `Regi_Name` — display / station name (user or license)
/// - `Regi_Code` — Windows/macOS computer name; Android serial/androidId
/// - `reg_deviceid` — hardware id
///
/// Billboard Classic filtered `bb_arrangement` by `comp_name = Xregister`
/// (Windows computer name). On other platforms we still need a stable label
/// that POS → Billboard setup can type into `comp_name`.
class DeviceIdentity {
  DeviceIdentity._();

  static final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  /// Suggested `comp_name` for first launch / empty prefs.
  static Future<String> resolveComputerName() async {
    try {
      if (Platform.isWindows) {
        final info = await _plugin.windowsInfo;
        final name = info.computerName.trim();
        if (name.isNotEmpty) return name;
      } else if (Platform.isMacOS) {
        final info = await _plugin.macOsInfo;
        final name = info.computerName.trim();
        if (name.isNotEmpty) return name;
      } else if (Platform.isLinux) {
        final host = Platform.localHostname.trim();
        if (host.isNotEmpty) return host;
      } else if (Platform.isAndroid) {
        final info = await _plugin.androidInfo;
        final deviceName = info.name.trim();
        if (deviceName.isNotEmpty) return deviceName;
        final model = info.model.trim();
        final suffix = _shortToken(
          info.id.trim().isNotEmpty ? info.id : info.fingerprint,
        );
        if (model.isNotEmpty && suffix.isNotEmpty) return '$model-$suffix';
        if (model.isNotEmpty) return model;
        if (suffix.isNotEmpty) return 'Android-$suffix';
      } else if (Platform.isIOS) {
        final info = await _plugin.iosInfo;
        final name = info.name.trim();
        if (name.isNotEmpty) return name;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('DeviceIdentity.resolveComputerName: $e');
    }

    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    } catch (_) {}

    return 'BILLBOARD';
  }

  static String _shortToken(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.isEmpty) return '';
    return cleaned.length <= 6
        ? cleaned
        : cleaned.substring(cleaned.length - 6);
  }

  /// Short label for UI help text.
  static String platformHint() {
    if (Platform.isWindows) {
      return "Windows: use this PC's computer name (Classic Xregister / Regi_Code).";
    }
    if (Platform.isAndroid) {
      return 'Android: Device = this unit\'s device name '
          '(Settings → About / device name).';
    }
    if (Platform.isMacOS) {
      return 'macOS: system computer name (aligned with Regi_Code in POS).';
    }
    if (Platform.isLinux) {
      return 'Linux: machine hostname.';
    }
    return 'Must match bb_arrangement.comp_name in POS → Billboard.';
  }
}
