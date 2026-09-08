/// MySQL connection parameters (same keys as Camaleon POS SharedPreferences).
class DbConnectionConfig {
  const DbConnectionConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.database,
  });

  final String host;
  final int port;
  final String user;
  final String password;
  final String database;

  bool get isComplete =>
      host.trim().isNotEmpty &&
      user.trim().isNotEmpty &&
      database.trim().isNotEmpty;

  DbConnectionConfig copyWith({
    String? host,
    int? port,
    String? user,
    String? password,
    String? database,
  }) {
    return DbConnectionConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      password: password ?? this.password,
      database: database ?? this.database,
    );
  }

  static const empty = DbConnectionConfig(
    host: '',
    port: 3306,
    user: 'root',
    password: '',
    database: '',
  );
}
