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
