/// Classic Camaleon DB pairing QR payload.
///
/// Format: `__cmlnconn__:host:port:user:password:database`
class DbConnectionQr {
  static const String prefix = '__cmlnconn__';

  static String build({
    required String host,
    required int port,
    required String user,
    required String password,
    required String database,
  }) {
    return '$prefix:$host:$port:$user:$password:$database';
  }

  static DbConnectionQrPayload? parse(String raw) {
    final text = raw.trim();
    if (!text.startsWith('$prefix:')) return null;

    final rest = text.substring(prefix.length + 1);
    final parts = rest.split(':');
    if (parts.length < 5) return null;

    final host = parts[0].trim();
    final portRaw = parts[1].trim();
    final user = parts[2].trim();
    final database = parts.last.trim();
    final password = parts.length == 5
        ? parts[3]
        : parts.sublist(3, parts.length - 1).join(':');

    final port = int.tryParse(portRaw);
    if (host.isEmpty || port == null || user.isEmpty || database.isEmpty) {
      return null;
    }

    return DbConnectionQrPayload(
      host: host,
      port: port,
      user: user,
      password: password,
      database: database,
    );
  }
}

class DbConnectionQrPayload {
  const DbConnectionQrPayload({
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
}
