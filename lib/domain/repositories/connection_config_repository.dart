import 'package:camaleon_billboard/domain/entities/db_connection_config.dart';

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

  /// Best-effort import of POS connection from a shared Camaleon file / QR.
  Future<DbConnectionConfig?> tryImportSharedConnection();
}
