import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mysql1/mysql1.dart';

import 'package:camaleon_billboard/domain/entities/db_connection_config.dart';

/// Default Camaleon POS MySQL password used for LAN auto-connect.
const kDefaultMysqlPassword = 'antonio';
const kDefaultMysqlUser = 'root';
const kDefaultMysqlPort = 3306;

class LanAuthHit {
  const LanAuthHit({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.databases,
  });

  final String host;
  final int port;
  final String user;
  final String password;

  /// User databases, Camaleon / bb_arrangement first.
  final List<String> databases;

  DbConnectionConfig asConfig(String database) {
    return DbConnectionConfig(
      host: host,
      port: port,
      user: user,
      password: password,
      database: database,
    );
  }
}

class LanConnectAttempt {
  const LanConnectAttempt({this.ready, this.hit});

  /// Single database resolved — ready to connect.
  final DbConnectionConfig? ready;

  /// Auth OK with one or more databases (use [hit.databases]).
  final LanAuthHit? hit;
}

/// Finds MySQL hosts on the local LAN and probes credentials.
class LanMysqlDiscovery {
  /// TCP scan of local /24 subnets for an open MySQL port.
  static Future<List<String>> findMysqlHosts({
    int port = kDefaultMysqlPort,
    Duration timeout = const Duration(milliseconds: 220),
    void Function(String status)? onProgress,
  }) async {
    final candidates = await _candidateIps();
    onProgress?.call('Scanning ${candidates.length} IPs on the network…');

    final open = <String>[];
    const batch = 48;
    for (var i = 0; i < candidates.length; i += batch) {
      final slice = candidates.skip(i).take(batch).toList();
      final results = await Future.wait(
        slice.map((ip) => _portOpen(ip, port, timeout)),
      );
      for (var j = 0; j < slice.length; j++) {
        if (results[j]) open.add(slice[j]);
      }
      onProgress?.call(
        'Scanning network… ${open.isEmpty ? '' : '${open.length} found'}',
      );
    }

    open.sort((a, b) {
      final aa = a.split('.').map(int.parse).toList();
      final bb = b.split('.').map(int.parse).toList();
      for (var i = 0; i < 4; i++) {
        final c = aa[i].compareTo(bb[i]);
        if (c != 0) return c;
      }
      return 0;
    });
    return open;
  }

  /// Tries [passwords] against [hosts] until auth works and lists DBs.
  static Future<LanConnectAttempt?> tryConnectHosts({
    required List<String> hosts,
    required List<String> passwords,
    String user = kDefaultMysqlUser,
    int port = kDefaultMysqlPort,
    String? preferredDatabase,
    void Function(String status)? onProgress,
  }) async {
    final uniquePass = <String>[];
    for (final p in passwords) {
      if (!uniquePass.contains(p)) uniquePass.add(p);
    }

    for (final host in hosts) {
      for (final password in uniquePass) {
        onProgress?.call('Trying $host · $user…');
        final dbs = await listDatabases(
          host: host,
          port: port,
          user: user,
          password: password,
        );
        if (dbs.isEmpty) continue;

        final hit = LanAuthHit(
          host: host,
          port: port,
          user: user,
          password: password,
          databases: dbs,
        );

        // Always let the user pick when there is more than one DB.
        if (dbs.length > 1) {
          return LanConnectAttempt(hit: hit);
        }
        return LanConnectAttempt(ready: hit.asConfig(dbs.first), hit: hit);
      }
    }
    return null;
  }

  /// Lists non-system databases, always A–Z.
  static Future<List<String>> listDatabases({
    required String host,
    required int port,
    required String user,
    required String password,
  }) async {
    MySqlConnection? conn;
    try {
      conn = await MySqlConnection.connect(
        ConnectionSettings(
          host: host,
          port: port,
          user: user,
          password: password,
          timeout: const Duration(seconds: 5),
        ),
      );
      final rows = await conn.query('SHOW DATABASES');
      final names = rows
          .map((r) => '${r[0]}'.trim())
          .where((n) => n.isNotEmpty)
          .where((n) => !_systemDbs.contains(n.toLowerCase()))
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return names;
    } catch (_) {
      return const [];
    } finally {
      try {
        await conn?.close();
      } catch (_) {}
    }
  }

  static Future<List<String>> _candidateIps() async {
    final prefixes = <String>{};
    final extras = <String>{};

    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (_isPrivateLan(ip)) {
            final parts = ip.split('.');
            prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('NetworkInterface.list failed: $e');
    }

    if (Platform.isAndroid) {
      extras.addAll(['10.0.2.2', '10.0.3.2']);
    }
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      extras.addAll(['127.0.0.1']);
    }

    final out = <String>[...extras];
    for (final prefix in prefixes) {
      for (var i = 1; i <= 254; i++) {
        final ip = '$prefix.$i';
        if (!out.contains(ip)) out.add(ip);
      }
    }

    if (prefixes.isEmpty) {
      for (final prefix in ['192.168.1', '192.168.0', '192.168.68']) {
        for (var i = 1; i <= 254; i++) {
          out.add('$prefix.$i');
        }
      }
    }
    return out;
  }

  static bool _isPrivateLan(String ip) {
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('172.')) {
      final second = int.tryParse(ip.split('.')[1]) ?? 0;
      return second >= 16 && second <= 31;
    }
    return false;
  }

  static Future<bool> _portOpen(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static const _systemDbs = {
    'mysql',
    'information_schema',
    'performance_schema',
    'sys',
  };
}
