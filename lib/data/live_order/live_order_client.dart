import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camaleon_billboard/domain/entities/live_order.dart';
import 'package:camaleon_billboard/domain/entities/live_order_config.dart';

/// Thin HTTP client for the POS `liveOrderPreview` LAN service.
///
/// Uses [HttpClient] with an explicit [HttpClient.connectionTimeout] so a dead
/// host fails fast instead of hanging until a Future timeout.
class LiveOrderClient {
  LiveOrderClient();

  static const connectionTimeout = Duration(seconds: 2);
  static const responseTimeout = Duration(seconds: 3);

  /// Builds `http://host:port/path`, accepting pasted full URLs in [config.host].
  static Uri resolveUri(LiveOrderConfig config, String path) {
    final normalized = LiveOrderConfig.normalizeEndpoint(
      host: config.host,
      port: config.port,
    );
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri(
      scheme: 'http',
      host: normalized.host,
      port: normalized.port,
      path: cleanPath,
    );
  }

  Future<LiveOrderHealth> fetchHealth(LiveOrderConfig config) async {
    final json = await _requestJson(config, 'GET', '/health');
    return LiveOrderHealth.fromJson(json);
  }

  Future<LiveOrderSnapshot> fetchLiveOrder(LiveOrderConfig config) async {
    final json = await _requestJson(config, 'GET', '/live-order');
    return LiveOrderSnapshot.fromJson(json);
  }

  /// POST /test — forces POS to publish a $1 "test order" ticket.
  Future<LiveOrderSnapshot> publishTest(LiveOrderConfig config) async {
    final json = await _requestJson(config, 'POST', '/test');
    return LiveOrderSnapshot.fromJson(json);
  }

  /// POST /clear — clears the in-memory live ticket on POS.
  Future<LiveOrderSnapshot> clearLiveOrder(LiveOrderConfig config) async {
    final json = await _requestJson(config, 'POST', '/clear');
    return LiveOrderSnapshot.fromJson(json);
  }

  /// DELETE /live-order — alias for clear.
  Future<LiveOrderSnapshot> deleteLiveOrder(LiveOrderConfig config) async {
    final json = await _requestJson(config, 'DELETE', '/live-order');
    return LiveOrderSnapshot.fromJson(json);
  }

  Future<Map<String, dynamic>> _requestJson(
    LiveOrderConfig config,
    String method,
    String path,
  ) async {
    final uri = resolveUri(config, path);
    final client = HttpClient()
      ..connectionTimeout = connectionTimeout
      ..idleTimeout = responseTimeout
      ..userAgent = 'CamaleonBillboard/live-order';
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(connectionTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (method == 'POST' || method == 'DELETE') {
        request.headers.contentType = ContentType.json;
        request.contentLength = 0;
      }
      final response = await request.close().timeout(responseTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(responseTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LiveOrderHttpException(response.statusCode, uri.path);
      }
      if (body.trim().isEmpty) {
        throw FormatException('Empty response from $uri');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw FormatException('Invalid JSON from $uri');
      }
      return Map<String, dynamic>.from(decoded);
    } on SocketException catch (e) {
      throw LiveOrderConnectException(uri, e.message);
    } on TimeoutException catch (e) {
      throw LiveOrderConnectException(
        uri,
        e.message ?? 'timed out',
      );
    } on HttpException catch (e) {
      throw LiveOrderConnectException(uri, e.message);
    } finally {
      client.close(force: true);
    }
  }

  void close() {}
}

class LiveOrderHttpException implements Exception {
  const LiveOrderHttpException(this.statusCode, this.path);

  final int statusCode;
  final String path;

  @override
  String toString() => 'live-order HTTP $statusCode ($path)';
}

class LiveOrderConnectException implements Exception {
  const LiveOrderConnectException(this.uri, this.detail);

  final Uri uri;
  final String detail;

  @override
  String toString() => 'Cannot reach $uri ($detail)';
}
