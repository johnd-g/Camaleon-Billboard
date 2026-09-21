import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:camaleon_billboard/data/live_order/live_order_client.dart';
import 'package:camaleon_billboard/data/repositories/connection_config_repository_impl.dart';
import 'package:camaleon_billboard/domain/entities/live_order.dart';
import 'package:camaleon_billboard/domain/entities/live_order_config.dart';
import 'package:camaleon_billboard/domain/repositories/connection_config_repository.dart';

enum LiveOrderPhase { idle, connecting, live, empty, waiting, error }

/// Polls the POS Live order HTTP service independently of MySQL boards.
class LiveOrderController extends ChangeNotifier {
  LiveOrderController({
    ConnectionConfigRepository? connectionRepo,
    LiveOrderClient? client,
  }) : _connectionRepo = connectionRepo ?? ConnectionConfigRepositoryImpl(),
       _client = client ?? LiveOrderClient();

  final ConnectionConfigRepository _connectionRepo;
  final LiveOrderClient _client;

  LiveOrderConfig config = LiveOrderConfig.empty;
  LiveOrderPhase phase = LiveOrderPhase.idle;
  LiveOrderSnapshot? snapshot;
  String? statusMessage;
  String? lastUpdatedAt;
  bool bootstrapping = true;
  bool validating = false;
  bool actionBusy = false;

  Timer? _pollTimer;
  bool _pollInFlight = false;
  int _consecutiveFailures = 0;
  static const _keepLastGoodFailures = 3;

  Future<void> bootstrap() async {
    bootstrapping = true;
    notifyListeners();
    try {
      config = (await _connectionRepo.loadLiveOrderConfig()).normalized();
      if (config.isReady) {
        await startPolling(validateHealth: true);
      } else {
        phase = LiveOrderPhase.idle;
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('LiveOrder bootstrap failed: $e\n$st');
      phase = LiveOrderPhase.idle;
    } finally {
      bootstrapping = false;
      notifyListeners();
    }
  }

  Future<void> saveConfig(LiveOrderConfig next) async {
    config = next.normalized();
    await _connectionRepo.saveLiveOrderConfig(config);
    notifyListeners();

    if (config.isReady) {
      await startPolling(validateHealth: true);
    } else {
      stopPolling();
      phase = LiveOrderPhase.idle;
      statusMessage = null;
      notifyListeners();
    }
  }

  Future<bool> startPolling({bool validateHealth = false}) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _consecutiveFailures = 0;

    if (!config.isReady) {
      phase = LiveOrderPhase.idle;
      statusMessage = 'Enter the POS IP and enable Live order.';
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
        // Still start polling — POS may come online later.
      } finally {
        validating = false;
        notifyListeners();
      }
    } else {
      phase = snapshot == null
          ? LiveOrderPhase.connecting
          : (snapshot!.hasItems ? LiveOrderPhase.live : LiveOrderPhase.empty);
      statusMessage = null;
      notifyListeners();
    }

    _scheduleNextPoll(immediate: true);
    return true;
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _consecutiveFailures = 0;
  }

  void _scheduleNextPoll({bool immediate = false}) {
    _pollTimer?.cancel();
    if (!config.isReady) return;

    final base = config.pollMs.clamp(200, 10000);
    // Back off while offline so we don't stack 3s timeouts every 500ms.
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
      statusMessage = null;
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

  /// Force a one-shot refresh (e.g. after POS Test).
  Future<void> refreshNow() => _pollOnce();

  /// Customer Display side panel: only while there is an active non-empty ticket.
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

  /// POST /test — ask POS to publish a $1 test ticket.
  Future<bool> publishTest() async {
    if (config.host.trim().isEmpty) {
      statusMessage = 'Enter the POS IP first.';
      notifyListeners();
      return false;
    }
    actionBusy = true;
    statusMessage = 'Sending test order…';
    notifyListeners();
    try {
      final cfg = config.copyWith(enabled: true).normalized();
      if (!config.enabled ||
          config.host != cfg.host ||
          config.port != cfg.port) {
        config = cfg;
        await _connectionRepo.saveLiveOrderConfig(config);
        if (config.isReady && _pollTimer == null) {
          await startPolling(validateHealth: false);
        }
      }
      final next = await _client.publishTest(cfg);
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

  /// POST /clear — ask POS to clear the live ticket.
  Future<bool> clearOrder() async {
    if (config.host.trim().isEmpty) {
      statusMessage = 'Enter the POS IP first.';
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
        // Fallback alias if older POS only exposes DELETE.
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
    _client.close();
    super.dispose();
  }
}
