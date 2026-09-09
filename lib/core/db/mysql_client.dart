import 'package:mysql1/mysql1.dart';

import 'package:camaleon_billboard/domain/entities/db_connection_config.dart';

/// Thin MySQL connection holder used by data sources.
class MysqlClient {
  MySqlConnection? _connection;
  DbConnectionConfig? _config;

  bool get isConnected => _connection != null;
  DbConnectionConfig? get config => _config;

  Future<MySqlConnection> connect(DbConnectionConfig config) async {
    await disconnect();
    final conn = await MySqlConnection.connect(
      ConnectionSettings(
        host: config.host.trim(),
        port: config.port,
        user: config.user.trim(),
        password: config.password,
        db: config.database.trim(),
        timeout: const Duration(seconds: 12),
      ),
    );
    _connection = conn;
    _config = config;
    return conn;
  }

  Future<MySqlConnection> requireConnection() async {
    final c = _connection;
    if (c == null) {
      throw StateError('MySQL is not connected');
    }
    return c;
  }

  Future<Results> query(String sql, [List<Object?>? values]) async {
    final conn = await requireConnection();
    return conn.query(sql, values);
  }

  /// Runs [action] inside a single MySQL transaction on this connection.
  ///
  /// On success: COMMIT. On any error: ROLLBACK then rethrows.
  Future<T> transaction<T>(Future<T> Function() action) async {
    await query('START TRANSACTION');
    try {
      final result = await action();
      await query('COMMIT');
      return result;
    } catch (e) {
      try {
        await query('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  Future<bool> test(DbConnectionConfig config) async {
    MySqlConnection? probe;
    try {
      probe = await MySqlConnection.connect(
        ConnectionSettings(
          host: config.host.trim(),
          port: config.port,
          user: config.user.trim(),
          password: config.password,
          db: config.database.trim(),
          timeout: const Duration(seconds: 8),
        ),
      );
      await probe.query('SELECT 1');
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await probe?.close();
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    try {
      await _connection?.close();
    } catch (_) {}
    _connection = null;
  }
}
