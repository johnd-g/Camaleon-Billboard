import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:camaleon_billboard/core/db/db_connection_qr.dart';
import 'package:camaleon_billboard/core/utils/device_identity.dart';
import 'package:camaleon_billboard/domain/entities/db_connection_config.dart';
import 'package:camaleon_billboard/domain/entities/live_order_config.dart';
import 'package:camaleon_billboard/domain/repositories/connection_config_repository.dart';

/// Local prefs + optional shared Camaleon connection file.
///
/// POS SharedPreferences are sandboxed per app — they cannot be read from
/// Billboard on Android / iOS / macOS. On desktop we look for a voluntary
/// shared JSON next to a well-known Camaleon folder, and we always support
/// the same QR payload POS builds (`__cmlnconn__:...`).
class ConnectionConfigRepositoryImpl implements ConnectionConfigRepository {
  static const _kHost = 'host';
  static const _kPort = 'port';
  static const _kUser = 'user';
  static const _kPassword = 'password';
  static const _kDb = 'db';
  static const _kCompName = 'billboard_comp_name';
  static const _kSortAbc = 'arrangeabc';
  static const _kRefresh = 'refresh_seconds';
  static const _kCustomerDisplay = 'customer_display';
  static const _kPoleDisplayBack = 'pole_display_back_color';
  static const _kPoleDisplayText = 'pole_display_text_color';
  static const _kPoleDisplaySeat = 'pole_display_seat_color';
  static const _kPoleDisplayDark = 'pole_display_dark_mode';
  static const _kPoleDisplayFloating = 'pole_display_floating';
  static const _kMediaFrame = 'media_frame';
  static const _kPoleDisplayScale = 'pole_display_scale';
  static const _kPoleDisplayLeft = 'pole_display_left';
  static const _kPoleDisplayTop = 'pole_display_top';
  static const _kPoleDisplayHeight = 'pole_display_height';
  static const _kLiveOrderHost = 'liveOrderHost';
  static const _kLiveOrderPort = 'liveOrderPort';
  static const _kLiveOrderPollMs = 'liveOrderPollMs';
  static const _kLiveOrderEnabled = 'liveOrderEnabled';

  @override
  Future<DbConnectionConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return DbConnectionConfig(
      host: prefs.getString(_kHost) ?? '',
      port: prefs.getInt(_kPort) ?? 3306,
      user: prefs.getString(_kUser) ?? 'root',
      password: prefs.getString(_kPassword) ?? '',
      database: prefs.getString(_kDb) ?? '',
    );
  }

  @override
  Future<void> save(DbConnectionConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, config.host.trim());
    await prefs.setInt(_kPort, config.port);
    await prefs.setString(_kUser, config.user.trim());
    await prefs.setString(_kPassword, config.password);
    await prefs.setString(_kDb, config.database.trim());
  }

  @override
  Future<String> loadComputerName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kCompName)?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    return DeviceIdentity.resolveComputerName();
  }

  @override
  Future<void> saveComputerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCompName, name.trim());
  }

  @override
  Future<bool> loadSortAlphabetical() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSortAbc) ?? false;
  }

  @override
  Future<void> saveSortAlphabetical(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSortAbc, value);
  }

  @override
  Future<int> loadRefreshSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kRefresh) ?? 5;
  }

  @override
  Future<void> saveRefreshSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRefresh, seconds.clamp(5, 3600));
  }

  @override
  Future<bool> loadCustomerDisplay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kCustomerDisplay) ?? false;
  }

  @override
  Future<void> saveCustomerDisplay(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCustomerDisplay, value);
  }

  @override
  Future<int> loadPoleDisplayBackColor() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_kPoleDisplayBack) ?? 15).clamp(0, 15);
  }

  @override
  Future<void> savePoleDisplayBackColor(int qbIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPoleDisplayBack, qbIndex.clamp(0, 15));
  }

  @override
  Future<int> loadPoleDisplayTextColor() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_kPoleDisplayText) ?? 0).clamp(0, 15);
  }

  @override
  Future<void> savePoleDisplayTextColor(int qbIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPoleDisplayText, qbIndex.clamp(0, 15));
  }

  @override
  Future<int> loadPoleDisplaySeatColor() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_kPoleDisplaySeat) ?? 2).clamp(0, 15);
  }

  @override
  Future<void> savePoleDisplaySeatColor(int qbIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPoleDisplaySeat, qbIndex.clamp(0, 15));
  }

  @override
  Future<bool> loadPoleDisplayDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPoleDisplayDark) ?? false;
  }

  @override
  Future<void> savePoleDisplayDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPoleDisplayDark, value);
  }

  @override
  Future<bool> loadPoleDisplayFloating() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPoleDisplayFloating) ?? false;
  }

  @override
  Future<void> savePoleDisplayFloating(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPoleDisplayFloating, value);
  }

  @override
  Future<bool> loadMediaFrame() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kMediaFrame) ?? false;
  }

  @override
  Future<void> saveMediaFrame(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMediaFrame, value);
  }

  @override
  Future<int> loadPoleDisplayScale() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_kPoleDisplayScale) ?? 100).clamp(70, 200);
  }

  @override
  Future<void> savePoleDisplayScale(int percent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPoleDisplayScale, percent.clamp(70, 200));
  }

  @override
  Future<double> loadPoleDisplayLeft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kPoleDisplayLeft) ?? -1;
  }

  @override
  Future<void> savePoleDisplayLeft(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPoleDisplayLeft, value);
  }

  @override
  Future<double> loadPoleDisplayTop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kPoleDisplayTop) ?? 16;
  }

  @override
  Future<void> savePoleDisplayTop(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPoleDisplayTop, value);
  }

  @override
  Future<int> loadPoleDisplayHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kPoleDisplayHeight) ?? 0;
  }

  @override
  Future<void> savePoleDisplayHeight(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPoleDisplayHeight, value);
  }

  @override
  Future<LiveOrderConfig> loadLiveOrderConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return LiveOrderConfig(
      host: prefs.getString(_kLiveOrderHost) ?? '',
      port: prefs.getInt(_kLiveOrderPort) ?? 8777,
      pollMs: (prefs.getInt(_kLiveOrderPollMs) ?? 500).clamp(200, 10000),
      enabled: prefs.getBool(_kLiveOrderEnabled) ?? false,
    );
  }

  @override
  Future<void> saveLiveOrderConfig(LiveOrderConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = config.normalized();
    await prefs.setString(_kLiveOrderHost, normalized.host);
    await prefs.setInt(
      _kLiveOrderPort,
      normalized.port <= 0 ? 8777 : normalized.port,
    );
    await prefs.setInt(
      _kLiveOrderPollMs,
      normalized.pollMs.clamp(200, 10000),
    );
    await prefs.setBool(_kLiveOrderEnabled, normalized.enabled);
  }

  @override
  Future<DbConnectionConfig?> tryImportSharedConnection() async {
    for (final file in await _candidateSharedFiles()) {
      final fromJson = await _readSharedJson(file);
      if (fromJson != null) return fromJson;

      try {
        if (!await file.exists()) continue;
        final text = await file.readAsString();
        final qr = DbConnectionQr.parse(text);
        if (qr != null) {
          return DbConnectionConfig(
            host: qr.host,
            port: qr.port,
            user: qr.user,
            password: qr.password,
            database: qr.database,
          );
        }
      } catch (_) {}
    }
    return null;
  }

  Future<List<File>> _candidateSharedFiles() async {
    final files = <File>[];
    try {
      final docs = await getApplicationDocumentsDirectory();
      final home = docs.parent;
      files.addAll([
        File(p.join(home.path, 'Camaleon', 'db_connection.json')),
        File(p.join(home.path, 'CamaleonShared', 'db_connection.json')),
        File(p.join(home.path, 'Camaleon', 'connection.qr.txt')),
      ]);
    } catch (_) {}

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        files.addAll([
          File(p.join(appData, 'Camaleon', 'db_connection.json')),
          File(p.join(appData, 'CamaleonShared', 'db_connection.json')),
        ]);
      }
    }
    return files;
  }

  Future<DbConnectionConfig?> _readSharedJson(File file) async {
    try {
      if (!await file.exists()) return null;
      if (!file.path.endsWith('.json')) return null;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final host = '${map['host'] ?? ''}'.trim();
      final user = '${map['user'] ?? ''}'.trim();
      final database = '${map['db'] ?? map['database'] ?? ''}'.trim();
      final port = int.tryParse('${map['port'] ?? 3306}') ?? 3306;
      final password = '${map['password'] ?? ''}';
      if (host.isEmpty || user.isEmpty || database.isEmpty) return null;
      return DbConnectionConfig(
        host: host,
        port: port,
        user: user,
        password: password,
        database: database,
      );
    } catch (_) {
      return null;
    }
  }
}
