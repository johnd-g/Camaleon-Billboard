import 'package:camaleon_billboard/domain/entities/db_connection_config.dart';
import 'package:camaleon_billboard/domain/entities/live_order_config.dart';

abstract class ConnectionConfigRepository {
  Future<DbConnectionConfig> load();
  Future<void> save(DbConnectionConfig config);
  Future<String> loadComputerName();
  Future<void> saveComputerName(String name);
  Future<bool> loadSortAlphabetical();
  Future<void> saveSortAlphabetical(bool value);
  Future<int> loadRefreshSeconds();
  Future<void> saveRefreshSeconds(int seconds);

  Future<bool> loadCustomerDisplay();
  Future<void> saveCustomerDisplay(bool value);

  Future<int> loadPoleDisplayBackColor();
  Future<void> savePoleDisplayBackColor(int qbIndex);

  Future<int> loadPoleDisplayTextColor();
  Future<void> savePoleDisplayTextColor(int qbIndex);

  Future<int> loadPoleDisplaySeatColor();
  Future<void> savePoleDisplaySeatColor(int qbIndex);

  /// False = light modifier colors, true = dark.
  Future<bool> loadPoleDisplayDarkMode();
  Future<void> savePoleDisplayDarkMode(bool value);

  Future<bool> loadPoleDisplayFloating();
  Future<void> savePoleDisplayFloating(bool value);

  Future<bool> loadMediaFrame();
  Future<void> saveMediaFrame(bool value);

  Future<int> loadPoleDisplayScale();
  Future<void> savePoleDisplayScale(int percent);

  Future<double> loadPoleDisplayLeft();
  Future<void> savePoleDisplayLeft(double value);

  Future<double> loadPoleDisplayTop();
  Future<void> savePoleDisplayTop(double value);

  Future<int> loadPoleDisplayHeight();
  Future<void> savePoleDisplayHeight(int value);

  Future<LiveOrderConfig> loadLiveOrderConfig();
  Future<void> saveLiveOrderConfig(LiveOrderConfig config);

  /// Best-effort import of POS connection from a shared Camaleon file / QR.
  Future<DbConnectionConfig?> tryImportSharedConnection();
}
