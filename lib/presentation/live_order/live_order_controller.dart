import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:camaleon_billboard/data/live_order/live_order_client.dart';
import 'package:camaleon_billboard/data/repositories/connection_config_repository_impl.dart';
import 'package:camaleon_billboard/domain/entities/live_order.dart';
import 'package:camaleon_billboard/domain/entities/live_order_config.dart';
import 'package:camaleon_billboard/domain/repositories/connection_config_repository.dart';

enum LiveOrderPhase { idle, connecting, live, empty, waiting, error }

typedef LiveOrderRegisterLoader = Future<LiveOrderRegisterEndpoint?> Function();

/// Polls the POS Live order HTTP service.
///
/// Host/port/enable always come from `it_tregister` (`liveorderonuse=1`).
/// No manual IP configuration.
class LiveOrderController extends ChangeNotifier {
  LiveOrderController({
    ConnectionConfigRepository? connectionRepo,
    LiveOrderClient? client,
  }) : _connectionRepo = connectionRepo ?? ConnectionConfigRepositoryImpl(),
       _client = client ?? LiveOrderClient();

  final ConnectionConfigRepository _connectionRepo;
  final LiveOrderClient _client;

  LiveOrderRegisterLoader? _registerLoader;

  LiveOrderConfig config = LiveOrderConfig.empty;
  LiveOrderPhase phase = LiveOrderPhase.idle;
  LiveOrderSnapshot? snapshot;
  String? statusMessage;
  String? lastUpdatedAt;
  bool bootstrapping = true;
  bool validating = false;
  bool actionBusy = false;

  /// Last register label applied from MySQL (`Regi_Name`).
  String? registerLabel;

  Timer? _pollTimer;
  Timer? _registerSyncTimer;
  bool _pollInFlight = false;
  bool _registerSyncInFlight = false;
  int _consecutiveFailures = 0;
  static const _keepLastGoodFailures = 3;
  static const _registerSyncEvery = Duration(seconds: 2);
  static const _defaultPollMs = 500;

  /// Wire MySQL lookup from [BillboardController] (ProxyProvider).
  void attachRegisterLoader(LiveOrderRegisterLoader? loader) {
    if (_registerLoader == loader) return;
    _registerLoader = loader;
    if (loader == null) {
      _stopRegisterSync();
      statusMessage = 'Connect MySQL to read it_tregister.';
      phase = LiveOrderPhase.waiting;
      notifyListeners();
      return;
    }
    _startRegisterSync();
    unawaited(syncFromRegister(persist: true, restartPoll: true));
  }

  Future<void> bootstrap() async {
    bootstrapping = true;
    notifyListeners();
    try {
      // Cache last known endpoint; real source of truth is it_tregister.
      final cached = (await _connectionRepo.loadLiveOrderConfig()).normalized();
      config = cached.copyWith(pollMs: _defaultPollMs);
      if (config.isReady) {
        await startPolling(validateHealth: true);
      } else {
        phase = LiveOrderPhase.waiting;
        statusMessage =
            'Waiting for it_tregister (liveorderonuse=1)…';
      }
      _startRegisterSync();
      unawaited(syncFromRegister(persist: true, restartPoll: true));
    } catch (e, st) {
      if (kDebugMode) debugPrint('LiveOrder bootstrap failed: $e\n$st');
      phase = LiveOrderPhase.waiting;
      statusMessage = 'Waiting for it_tregister…';
    } finally {
      bootstrapping = false;
      notifyListeners();
    }
  }

  /// Pull host/port from `it_tregister` where `liveorderonuse=1`.
  Future<bool> syncFromRegister({
    bool persist = true,
    bool restartPoll = false,
  }) async {
    final loader = _registerLoader;
    if (loader == null) {
      statusMessage = 'Connect MySQL to read it_tregister.';
      if (phase != LiveOrderPhase.live && phase != LiveOrderPhase.empty) {
        phase = LiveOrderPhase.waiting;
      }
      notifyListeners();
      return false;
    }
    if (_registerSyncInFlight) return false;
    _registerSyncInFlight = true;

    try {
      final row = await loader();
      if (row == null) {
        registerLabel = null;
        statusMessage =
            'Waiting for it_tregister with liveorderonuse=1 AND '
            'liveorderport_active=1 (Iniciar + Order Entry landscape)…';
        if (phase != LiveOrderPhase.live && phase != LiveOrderPhase.empty) {
          phase = LiveOrderPhase.waiting;
        }
        notifyListeners();
        return false;
      }

      final label = row.regiName.isNotEmpty ? row.regiName : row.regiCode;
      registerLabel = label.isEmpty ? null : label;

      if (row.server.trim().isEmpty) {
        statusMessage = label.isEmpty
            ? 'Register on use has empty liveorderserver.'
            : '$label on use, but liveorderserver is empty.';
        phase = LiveOrderPhase.waiting;
        notifyListeners();
        return false;
      }

      final next = LiveOrderConfig(
        host: row.server.trim(),
        port: row.port <= 0 ? 8777 : row.port,
        pollMs: _defaultPollMs,
        enabled: true,
      ).normalized();

      final hostChanged =
          next.host != config.host || next.port != config.port;
      final wasReady = config.isReady;

      config = next;
      if (persist) {
        await _connectionRepo.saveLiveOrderConfig(config);
      }
      statusMessage = label.isEmpty
          ? 'Using ${config.baseUrl} from it_tregister'
          : 'Using $label · ${config.baseUrl}';
      notifyListeners();

      if (restartPoll || hostChanged || !wasReady) {
        await startPolling(validateHealth: hostChanged || !wasReady);
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('LiveOrder syncFromRegister failed: $e');
      return false;
    } finally {
      _registerSyncInFlight = false;
    }
  }

  Future<bool> startPolling({bool validateHealth = false}) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _consecutiveFailures = 0;

    if (!config.isReady) {
      phase = LiveOrderPhase.waiting;
      statusMessage ??=
          'Waiting for it_tregister (liveorderonuse=1)…';
      notifyListeners();
      return false;
    }

    final target = config.baseUrl;

    if (validateHealth) {
      validating = true;
      phase = LiveOrderPhase.connecting;
      statusMessage = 'Checking $target…';
      notifyListeners();
      try {
        final health = await _client.fetchHealth(config);
        if (!health.ok) {
          phase = LiveOrderPhase.waiting;
          statusMessage = 'Waiting for POS at $target…';
        }
      } catch (e) {
        if (kDebugMode) debugPrint('LiveOrder health failed: $e');
        phase = LiveOrderPhase.waiting;
        statusMessage = 'Waiting for POS at $target…';
      } finally {
        validating = false;
        notifyListeners();
      }
    } else {
      phase = snapshot == null
          ? LiveOrderPhase.connecting
          : (snapshot!.hasItems ? LiveOrderPhase.live : LiveOrderPhase.empty);
      notifyListeners();
    }

    _scheduleNextPoll(immediate: true);
    _startRegisterSync();
    return true;
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _consecutiveFailures = 0;
  }

  void _startRegisterSync() {
    _registerSyncTimer?.cancel();
    if (_registerLoader == null) return;
    _registerSyncTimer = Timer.periodic(
      _registerSyncEvery,
      (_) => unawaited(syncFromRegister(persist: true, restartPoll: false)),
    );
  }

  void _stopRegisterSync() {
    _registerSyncTimer?.cancel();
    _registerSyncTimer = null;
  }

  void _scheduleNextPoll({bool immediate = false}) {
    _pollTimer?.cancel();
    if (!config.isReady) return;

    final base = config.pollMs.clamp(200, 10000);
    final delayMs = _consecutiveFailures == 0
        ? base
        : (base * (1 << _consecutiveFailures.clamp(0, 3))).clamp(base, 5000);
    final delay = immediate ? Duration.zero : Duration(milliseconds: delayMs);

    _pollTimer = Timer(delay, () => unawaited(_pollOnce()));
  }

  Future<void> _pollOnce() async {
    if (_pollInFlight || !config.isReady) return;
    _pollInFlight = true;
    final target = config.baseUrl;
    try {
      final next = await _client.fetchLiveOrder(config);
      _consecutiveFailures = 0;
      final changed = next.updatedAt != lastUpdatedAt || snapshot == null;
      snapshot = next;
      lastUpdatedAt = next.updatedAt;
      phase = next.hasItems ? LiveOrderPhase.live : LiveOrderPhase.empty;
      statusMessage = registerLabel == null
          ? null
          : 'Using $registerLabel · $target';
      if (changed) notifyListeners();
    } catch (e) {
      _consecutiveFailures++;
      if (kDebugMode) debugPrint('LiveOrder poll failed: $e');

      if (snapshot != null && _consecutiveFailures <= _keepLastGoodFailures) {
        statusMessage = 'Reconnecting to $target…';
        notifyListeners();
      } else {
        final offline =
            e is TimeoutException ||
            e is LiveOrderConnectException ||
            '$e'.contains('SocketException') ||
            '$e'.contains('Connection refused') ||
            '$e'.contains('Failed host lookup') ||
            '$e'.contains('ClientException') ||
            '$e'.contains('timed out') ||
            '$e'.contains('Cannot reach');
        phase = offline ? LiveOrderPhase.waiting : LiveOrderPhase.error;
        statusMessage = offline
            ? 'Waiting for POS at $target…'
            : 'Live order error: $e';
        if (_consecutiveFailures > _keepLastGoodFailures) {
          snapshot = null;
          lastUpdatedAt = null;
        }
        notifyListeners();
      }
    } finally {
      _pollInFlight = false;
      _scheduleNextPoll();
    }
  }

  Future<void> refreshNow() => _pollOnce();

  bool get showCustomerTicket {
    if (!config.isReady) return false;
    final s = snapshot;
    if (s == null) return false;
    return s.shouldShowTicket;
  }

  void _applySnapshot(LiveOrderSnapshot next, {String? status}) {
    _consecutiveFailures = 0;
    snapshot = next;
    lastUpdatedAt = next.updatedAt;
    phase = next.hasItems ? LiveOrderPhase.live : LiveOrderPhase.empty;
    statusMessage = status;
    notifyListeners();
  }

  Future<bool> publishTest() async {
    if (config.host.trim().isEmpty) {
      statusMessage = 'No POS IP yet — waiting for liveorderonuse=1.';
      notifyListeners();
      return false;
    }
    actionBusy = true;
    statusMessage = 'Sending test order…';
    notifyListeners();
    try {
      if (!config.isReady) {
        config = config.copyWith(enabled: true).normalized();
        await _connectionRepo.saveLiveOrderConfig(config);
        await startPolling(validateHealth: false);
      }
      final next = await _client.publishTest(config);
      _applySnapshot(next, status: 'Test order published.');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('LiveOrder POST /test failed: $e');
      statusMessage = 'Test failed: $e';
      notifyListeners();
      return false;
    } finally {
      actionBusy = false;
      notifyListeners();
    }
  }

  Future<bool> clearOrder() async {
    if (config.host.trim().isEmpty) {
      statusMessage = 'No POS IP yet — waiting for liveorderonuse=1.';
      notifyListeners();
      return false;
    }
    actionBusy = true;
    statusMessage = 'Clearing live order…';
    notifyListeners();
    try {
      final cfg = config.normalized();
      LiveOrderSnapshot next;
      try {
        next = await _client.clearLiveOrder(cfg);
      } on LiveOrderHttpException catch (e) {
        if (e.statusCode == 404) {
          next = await _client.deleteLiveOrder(cfg);
        } else {
          rethrow;
        }
      }
      _applySnapshot(next, status: 'Live order cleared.');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('LiveOrder POST /clear failed: $e');
      statusMessage = 'Clear failed: $e';
      notifyListeners();
      return false;
    } finally {
      actionBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopPolling();
    _stopRegisterSync();
    _client.close();
    super.dispose();
  }
}
