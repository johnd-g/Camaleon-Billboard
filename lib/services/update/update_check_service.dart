import 'dart:io';

import 'package:camaleon_billboard/services/update/version_check_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

export 'package:camaleon_billboard/services/update/version_check_service.dart';

enum UpdateCheckResult { updateAvailable, upToDate, checkFailed }

enum UpdateInstallStatus {
  installerOpened,
  installed,
  installCancelled,
  unsupportedPlatform,
  downloadFailed,
  invalidPackage,
  installFailed,
}

class UpdateInstallResult {
  const UpdateInstallResult(this.status, {this.filePath, this.error});

  final UpdateInstallStatus status;
  final String? filePath;
  final String? error;

  bool get installerOpened => status == UpdateInstallStatus.installerOpened;
}

class UpdateCheckService {
  UpdateCheckService({
    CamaleonVersionCheckService? versionCheck,
    http.Client? httpClient,
  }) : _versionCheck = versionCheck ?? CamaleonVersionCheckService.shared,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  static const MethodChannel _androidInstaller = MethodChannel(
    'camaleon_billboard/update',
  );
  static const String _windowsInstalledLauncher =
      r'$env:ProgramFiles\CamaleonBillboard\camaleon_billboard.exe';

  final CamaleonVersionCheckService _versionCheck;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  CamaleonVersionCompareResult? lastCompareResult;
  CamaleonVersionEntry? lastLatestRelease;

  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }

  Future<UpdateCheckResult> checkForUpdates({bool forceRefresh = false}) async {
    if (!CamaleonVersionCheckService.isSupportedPlatform) {
      return UpdateCheckResult.checkFailed;
    }

    try {
      final compare = await _versionCheck.compareWithInstalled(
        forceRefresh: forceRefresh,
      );
      lastCompareResult = compare;
      lastLatestRelease = compare.latest;

      if (compare.error != null || compare.latest == null) {
        _debug('Check failed: ${compare.error ?? 'missing_latest_release'}');
        return UpdateCheckResult.checkFailed;
      }

      _debug(
        '$kCamaleonBillboardProductName pid=${compare.productId}; '
        'local=${compare.localVersion}+${compare.localBuild}; '
        'server=${compare.latest!.version}+${compare.latest!.build}',
      );
      return compare.updateAvailable
          ? UpdateCheckResult.updateAvailable
          : UpdateCheckResult.upToDate;
    } catch (error, stackTrace) {
      _debug('Check failed: $error\n$stackTrace');
      return UpdateCheckResult.checkFailed;
    }
  }

  Future<String?> resolveDownloadUrl({bool forceRefresh = false}) async {
    final cached = lastLatestRelease?.downloadUrl.trim() ?? '';
    if (!forceRefresh && cached.isNotEmpty) return cached;
    try {
      return await _versionCheck.resolveDownloadUrl(forceRefresh: forceRefresh);
    } catch (error) {
      _debug('Could not resolve download URL: $error');
      return null;
    }
  }

  /// Downloads the release supplied by product 36 and opens the native
  /// installer. This is the regular Android APK flow; it never uses PAXSTORE
  /// or Dejavoo/DVStore.
  Future<UpdateInstallResult> downloadAndInstallLatest({
    bool forceRefresh = false,
    void Function(double? progress)? onProgress,
  }) async {
    if (!CamaleonVersionCheckService.isSupportedPlatform) {
      return const UpdateInstallResult(UpdateInstallStatus.unsupportedPlatform);
    }

    try {
      final release = await _resolveRelease(forceRefresh: forceRefresh);
      if (release == null || release.downloadUrl.isEmpty) {
        return const UpdateInstallResult(
          UpdateInstallStatus.downloadFailed,
          error: 'Product 36 has no download available.',
        );
      }

      final file = await _downloadRelease(release, onProgress: onProgress);
      final validationError = await _validateRelease(file, release);
      if (validationError != null) {
        await _deleteIfPresent(file);
        return UpdateInstallResult(
          UpdateInstallStatus.invalidPackage,
          error: validationError,
        );
      }

      if (Platform.isAndroid) {
        final response = await _androidInstaller
            .invokeMapMethod<String, dynamic>('installApk', {
              'filePath': file.path,
            });
        if (response?['opened'] == true) {
          return UpdateInstallResult(
            UpdateInstallStatus.installerOpened,
            filePath: file.path,
          );
        }
        return UpdateInstallResult(
          UpdateInstallStatus.installFailed,
          filePath: file.path,
          error:
              response?['error']?.toString() ??
              'Android installer did not open.',
        );
      }

      return await _runWindowsInstaller(file.path);
    } catch (error, stackTrace) {
      _debug('Download/install failed: $error\n$stackTrace');
      return UpdateInstallResult(
        UpdateInstallStatus.downloadFailed,
        error: error.toString(),
      );
    }
  }

  Future<UpdateInstallResult> _runWindowsInstaller(String filePath) async {
    var wasFullScreen = false;
    try {
      await windowManager.ensureInitialized();
      wasFullScreen = await windowManager.isFullScreen();
      if (wasFullScreen) await windowManager.setFullScreen(false);
      await windowManager.minimize();

      final process = await Process.start(
        'powershell.exe',
        windowsInstallerArguments(filePath),
        mode: ProcessStartMode.normal,
      );
      final exitCode = await process.exitCode;
      _debug('Windows installer exit code: $exitCode');
      if (exitCode == 0) {
        return UpdateInstallResult(
          UpdateInstallStatus.installed,
          filePath: filePath,
        );
      }
      return UpdateInstallResult(
        UpdateInstallStatus.installCancelled,
        filePath: filePath,
        error: 'Windows installer exited with code $exitCode.',
      );
    } catch (error) {
      return UpdateInstallResult(
        UpdateInstallStatus.installFailed,
        filePath: filePath,
        error: error.toString(),
      );
    } finally {
      try {
        await windowManager.restore();
        if (wasFullScreen) await windowManager.setFullScreen(true);
        await windowManager.focus();
      } catch (error) {
        _debug('Could not restore the Billboard window: $error');
      }
    }
  }

  @visibleForTesting
  static List<String> windowsInstallerArguments(String filePath) {
    final escapedPath = filePath.replaceAll("'", "''");
    final command =
        "\$installerArgs = @('/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "
        "'/CLOSEAPPLICATIONS'); "
        "\$process = Start-Process -FilePath '$escapedPath' "
        "-ArgumentList \$installerArgs -Verb RunAs -PassThru -Wait; "
        "\$code = \$process.ExitCode; "
        "if ((\$code -eq 0) -and "
        '(Test-Path "$_windowsInstalledLauncher")) { '
        'Start-Process -FilePath "$_windowsInstalledLauncher" }; '
        'exit \$code';
    return <String>['-NoProfile', '-NonInteractive', '-Command', command];
  }

  Future<CamaleonVersionEntry?> _resolveRelease({
    required bool forceRefresh,
  }) async {
    if (!forceRefresh && lastLatestRelease != null) return lastLatestRelease;
    final response = await _versionCheck.fetchVersionHistory(
      forceRefresh: forceRefresh,
    );
    lastLatestRelease = response.latest;
    return response.latest;
  }

  Future<File> _downloadRelease(
    CamaleonVersionEntry release, {
    void Function(double? progress)? onProgress,
  }) async {
    final directory = await getApplicationSupportDirectory();
    final extension = Platform.isAndroid ? '.apk' : '.exe';
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'camaleon-billboard-update$extension',
    );
    await file.parent.create(recursive: true);

    final request = http.Request('GET', Uri.parse(release.downloadUrl));
    request.headers[HttpHeaders.acceptEncodingHeader] = 'identity';
    final response = await _httpClient
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Download returned HTTP ${response.statusCode}',
        uri: request.url,
      );
    }

    final expectedBytes = response.contentLength ?? release.fileSize;
    var receivedBytes = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(minutes: 5),
      )) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(
          expectedBytes == null || expectedBytes <= 0
              ? null
              : receivedBytes / expectedBytes,
        );
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      await _deleteIfPresent(file);
      rethrow;
    }
    await sink.close();
    onProgress?.call(1);
    return file;
  }

  Future<String?> _validateRelease(
    File file,
    CamaleonVersionEntry release,
  ) async {
    if (!await file.exists()) return 'Downloaded update is missing.';
    final size = await file.length();
    if (size <= 0) return 'Downloaded update is empty.';
    if (release.fileSize != null && size != release.fileSize) {
      return 'Downloaded size does not match the server metadata.';
    }

    final expectedHash = release.sha256?.trim().toLowerCase() ?? '';
    if (expectedHash.isNotEmpty) {
      final actualHash = (await sha256.bind(file.openRead()).first).toString();
      if (actualHash != expectedHash) {
        return 'Downloaded SHA-256 does not match the server metadata.';
      }
    }
    return null;
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A failed cleanup must not hide the original update error.
    }
  }

  void _debug(String message) {
    if (kDebugMode) debugPrint('[Camaleon Billboard Update] $message');
  }
}
