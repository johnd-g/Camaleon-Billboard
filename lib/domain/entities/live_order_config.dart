/// LAN settings for the POS Live order HTTP service.
class LiveOrderConfig {
  const LiveOrderConfig({
    this.host = '',
    this.port = 8777,
    this.pollMs = 500,
    this.enabled = false,
  });

  static const empty = LiveOrderConfig();

  final String host;
  final int port;
  final int pollMs;
  final bool enabled;

  bool get isReady => enabled && host.trim().isNotEmpty && port > 0;

  /// Builds config from an [it_tregister] live-order row.
  factory LiveOrderConfig.fromRegister(
    LiveOrderRegisterEndpoint row, {
    int pollMs = 500,
  }) {
    return LiveOrderConfig(
      host: row.server,
      port: row.port <= 0 ? 8777 : row.port,
      pollMs: pollMs,
      enabled: row.active && row.server.trim().isNotEmpty,
    );
  }

  String get baseUrl {
    final n = normalizeEndpoint(host: host, port: port);
    if (n.host.isEmpty) return '';
    return 'http://${n.host}:${n.port}';
  }

  /// Accepts `192.168.1.50`, `192.168.1.50:8777`, or a full pasted URL.
  static ({String host, int port}) normalizeEndpoint({
    required String host,
    required int port,
  }) {
    var raw = host.trim();
    var resolvedPort = port <= 0 ? 8777 : port;

    if (raw.isEmpty) return (host: '', port: resolvedPort);

    // Strip scheme if pasted.
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.host.isNotEmpty) {
        return (host: uri.host, port: uri.hasPort ? uri.port : resolvedPort);
      }
      raw = raw.replaceFirst(RegExp(r'^https?://'), '');
    }

    // Drop path/query: `192.168.1.50:8777/live-order`
    final slash = raw.indexOf('/');
    if (slash >= 0) raw = raw.substring(0, slash);
    final q = raw.indexOf('?');
    if (q >= 0) raw = raw.substring(0, q);

    // host:port (IPv4 / hostname). Leave bare IPv6 alone.
    if (raw.contains(':') && !raw.startsWith('[')) {
      final parts = raw.split(':');
      if (parts.length == 2) {
        final p = int.tryParse(parts[1].trim());
        if (p != null && p > 0) {
          return (host: parts[0].trim(), port: p);
        }
      }
    }

    return (host: raw.trim(), port: resolvedPort);
  }

  LiveOrderConfig normalized() {
    final n = normalizeEndpoint(host: host, port: port);
    return LiveOrderConfig(
      host: n.host,
      port: n.port,
      pollMs: pollMs.clamp(200, 10000),
      enabled: enabled,
    );
  }

  LiveOrderConfig copyWith({
    String? host,
    int? port,
    int? pollMs,
    bool? enabled,
  }) {
    return LiveOrderConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      pollMs: pollMs ?? this.pollMs,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// One POS register row from `it_tregister` live-order columns.
///
/// Billboard only **reads** [server]/[port] — they do not decide who runs
/// the HTTP service. The POS starts `liveOrderPreview` on **this** register’s
/// row only while Order Entry landscape is open, and only when all of:
/// - `reg_deviceid` matches that POS machine
/// - [active] (`liveorderport_active=1`, Iniciar)
/// - [onUse] (`liveorderonuse=1` on this row alone; set on landscape enter,
///   cleared on exit; if another register already holds 1, this POS does not
///   listen)
class LiveOrderRegisterEndpoint {
  const LiveOrderRegisterEndpoint({
    required this.server,
    required this.port,
    required this.active,
    required this.onUse,
    this.regiName = '',
    this.regiCode = '',
  });

  /// `liveorderserver` — LAN IP Billboard should poll (pointer only).
  final String server;

  /// `liveorderport` — port Billboard should poll (pointer only).
  final int port;

  /// `liveorderport_active` — Iniciar; if 0, POS does not open the port.
  final bool active;

  /// `liveorderonuse` — this station owns landscape Order Entry lock.
  final bool onUse;
  final String regiName;
  final String regiCode;

  /// Ready for Billboard to poll: lock + Iniciar + non-empty endpoint.
  bool get isUsable =>
      active && onUse && server.trim().isNotEmpty && port > 0;
}
