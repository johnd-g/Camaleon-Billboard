import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:xml/xml.dart' as xml;

const String kCamaleonBillboardProductName = 'Camaleon Billboard';
const int kCamaleonBillboardProductId = 36;

// const String kCamaleonVersionCheckBaseUrl =
//     'https://www.camaleonpos.com/verscheck.php';
// const String kCamaleonDownloadsBaseUrl = 'https://www.camaleonpos.com/';
const String kCamaleonVersionCheckBaseUrl =
    'https://brian-pc.camaleonpos.com:8443/verscheck.php';
const String kCamaleonDownloadsBaseUrl =
    'https://brian-pc.camaleonpos.com:8443/';

class CamaleonVersionEntry {
  const CamaleonVersionEntry({
    required this.index,
    required this.whatsNew,
    required this.version,
    required this.build,
    required this.downloadPath,
    required this.downloadDate,
    required this.changeLog,
    this.fileSize,
    this.mandatory,
    this.sha256,
  });

  final int index;
  final String whatsNew;
  final String version;
  final int build;
  final String downloadPath;
  final String downloadDate;
  final String changeLog;
  final int? fileSize;
  final bool? mandatory;
  final String? sha256;

  String get downloadUrl {
    final path = downloadPath.trim();
    if (path.isEmpty) return '';
    final absolute = Uri.tryParse(path);
    if (absolute != null && absolute.hasScheme) return absolute.toString();
    return Uri.parse(kCamaleonDownloadsBaseUrl).resolve(path).toString();
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'whatsNew': whatsNew,
    'version': version,
    'build': build,
    'downloadPath': downloadPath,
    'downloadUrl': downloadUrl,
    'downloadDate': downloadDate,
    'changeLog': changeLog,
    if (fileSize != null) 'fileSize': fileSize,
    if (mandatory != null) 'mandatory': mandatory,
    if (sha256 != null && sha256!.isNotEmpty) 'sha256': sha256,
  };
}

class CamaleonVersionCheckResponse {
  const CamaleonVersionCheckResponse({
    required this.productId,
    required this.entries,
    required this.rawXml,
  });

  final int productId;
  final List<CamaleonVersionEntry> entries;
  final String rawXml;

  CamaleonVersionEntry? get latest => entries.isEmpty ? null : entries.first;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'latest': latest?.toJson(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };
}

class CamaleonVersionCompareResult {
  const CamaleonVersionCompareResult({
    required this.updateAvailable,
    required this.productId,
    required this.localVersion,
    required this.localBuild,
    this.latest,
    this.response,
    this.error,
  });

  final bool updateAvailable;
  final int productId;
  final String localVersion;
  final int localBuild;
  final CamaleonVersionEntry? latest;
  final CamaleonVersionCheckResponse? response;
  final String? error;

  String? get downloadUrl => latest?.downloadUrl;
}

class CamaleonVersionCheckService {
  CamaleonVersionCheckService({
    http.Client? httpClient,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  static final CamaleonVersionCheckService shared =
      CamaleonVersionCheckService();

  static const Duration httpResponseCacheTtl = Duration(hours: 6);
  static const Duration requestTimeout = Duration(seconds: 15);
  static const int maxRetries = 2;
  static const String _logName = 'CamaleonBillboardVersionCheck';

  static CamaleonVersionCheckResponse? _httpCache;
  static DateTime? _httpCacheAt;
  static Future<CamaleonVersionCheckResponse>? _httpInFlight;

  final http.Client _httpClient;
  final bool _ownsClient;
  final Future<PackageInfo> Function() _packageInfoLoader;

  void dispose() {
    if (_ownsClient && !identical(this, shared)) _httpClient.close();
  }

  @visibleForTesting
  static void resetHttpCache() {
    _httpCache = null;
    _httpCacheAt = null;
    _httpInFlight = null;
  }

  static bool get isSupportedPlatform =>
      Platform.isAndroid || Platform.isWindows;

  static int productIdForCurrentPlatform() {
    if (!isSupportedPlatform) {
      throw UnsupportedError(
        '$kCamaleonBillboardProductName updates only support Android and Windows.',
      );
    }
    return kCamaleonBillboardProductId;
  }

  static String versionCheckUrl() =>
      '$kCamaleonVersionCheckBaseUrl?a=vers&pid=$kCamaleonBillboardProductId';

  Future<CamaleonVersionCheckResponse> fetchVersionHistory({
    bool forceRefresh = false,
  }) async {
    productIdForCurrentPlatform();

    final inFlight = _httpInFlight;
    if (inFlight != null) return inFlight;

    if (!forceRefresh &&
        _httpCache != null &&
        _httpCacheAt != null &&
        DateTime.now().difference(_httpCacheAt!) < httpResponseCacheTtl) {
      return _httpCache!;
    }

    final future = _fetchVersionHistoryFromNetwork();
    _httpInFlight = future;
    try {
      final response = await future;
      _httpCache = response;
      _httpCacheAt = DateTime.now();
      return response;
    } finally {
      if (identical(_httpInFlight, future)) _httpInFlight = null;
    }
  }

  Future<CamaleonVersionCheckResponse> _fetchVersionHistoryFromNetwork() async {
    final uri = Uri.parse(versionCheckUrl());
    _log('GET $uri');
    final body = await _getWithRetry(uri);
    final entries = parseVersionXml(body);
    final response = CamaleonVersionCheckResponse(
      productId: kCamaleonBillboardProductId,
      entries: entries,
      rawXml: body,
    );
    final latest = response.latest;
    _log(
      latest == null
          ? 'Product $kCamaleonBillboardProductId returned no releases.'
          : 'Product $kCamaleonBillboardProductId: '
                '${latest.version}+${latest.build}; '
                'download=${latest.downloadUrl.isNotEmpty}',
    );
    return response;
  }

  Future<CamaleonVersionCompareResult> compareWithInstalled({
    bool forceRefresh = false,
  }) async {
    final packageInfo = await _packageInfoLoader();
    final localBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    final localVersion = packageInfo.version;

    try {
      final response = await fetchVersionHistory(forceRefresh: forceRefresh);
      final latest = response.latest;
      if (latest == null || latest.build <= 0) {
        return CamaleonVersionCompareResult(
          updateAvailable: false,
          productId: kCamaleonBillboardProductId,
          localVersion: localVersion,
          localBuild: localBuild,
          response: response,
          error: 'missing_latest_build',
        );
      }

      return CamaleonVersionCompareResult(
        updateAvailable: latest.build > localBuild,
        productId: kCamaleonBillboardProductId,
        localVersion: localVersion,
        localBuild: localBuild,
        latest: latest,
        response: response,
      );
    } catch (error, stackTrace) {
      _log('Version comparison failed: $error\n$stackTrace');
      return CamaleonVersionCompareResult(
        updateAvailable: false,
        productId: kCamaleonBillboardProductId,
        localVersion: localVersion,
        localBuild: localBuild,
        error: error.toString(),
      );
    }
  }

  Future<String?> resolveDownloadUrl({bool forceRefresh = false}) async {
    final latest = (await fetchVersionHistory(
      forceRefresh: forceRefresh,
    )).latest;
    final url = latest?.downloadUrl.trim() ?? '';
    return url.isEmpty ? null : url;
  }

  static List<CamaleonVersionEntry> parseVersionXml(String xmlBody) {
    final trimmed = xmlBody.trim();
    if (trimmed.isEmpty) throw const FormatException('Empty version response');
    if (!trimmed.startsWith('<')) {
      throw FormatException('Version server response: $trimmed');
    }

    final document = xml.XmlDocument.parse(trimmed);
    final roots = document.findAllElements('vdata');
    if (roots.isEmpty) throw const FormatException('Missing <vdata> element');

    final entries = <CamaleonVersionEntry>[];
    for (final node in roots.first.children.whereType<xml.XmlElement>()) {
      final tag = node.name.local;
      if (!RegExp(r'^v\d+$').hasMatch(tag)) continue;
      entries.add(
        CamaleonVersionEntry(
          index: int.parse(tag.substring(1)),
          whatsNew: _elementText(node, 'whatsnew'),
          version: _elementText(node, 'version'),
          build: int.tryParse(_elementText(node, 'dldbuild')) ?? 0,
          downloadPath: _elementText(node, 'dldpath'),
          downloadDate: _elementText(node, 'dlddate'),
          changeLog: _elementText(node, 'dldclog'),
          fileSize: _optionalInt(node, const ['filesize', 'fileSize']),
          mandatory: _optionalBool(node, const ['mandatory']),
          sha256: _optionalText(node, const ['sha256', 'hash']),
        ),
      );
    }
    entries.sort((a, b) => a.index.compareTo(b.index));
    return entries;
  }

  Future<String> _getWithRetry(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await _httpClient.get(uri).timeout(requestTimeout);
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('HTTP ${response.statusCode}', uri: uri);
        }
        if (response.body.trim().isEmpty) {
          throw const FormatException('Empty version response');
        }
        return response.body;
      } catch (error) {
        lastError = error;
        if (attempt < maxRetries) {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (1 << attempt)),
          );
        }
      }
    }
    throw lastError ?? StateError('Version check failed');
  }

  static String _elementText(xml.XmlElement parent, String name) {
    final values = parent.findElements(name);
    return values.isEmpty ? '' : values.first.innerText.trim();
  }

  static int? _optionalInt(xml.XmlElement parent, List<String> names) {
    final value = _optionalText(parent, names);
    return value == null ? null : int.tryParse(value);
  }

  static bool? _optionalBool(xml.XmlElement parent, List<String> names) {
    final value = _optionalText(parent, names)?.toLowerCase();
    if (value == '1' || value == 'true' || value == 'yes') return true;
    if (value == '0' || value == 'false' || value == 'no') return false;
    return null;
  }

  static String? _optionalText(xml.XmlElement parent, List<String> names) {
    for (final name in names) {
      final value = _elementText(parent, name);
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  static void _log(String message) {
    if (kDebugMode) developer.log(message, name: _logName);
  }
}
