import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:camaleon_billboard/core/db/db_connection_qr.dart';
import 'package:camaleon_billboard/core/db/lan_mysql_discovery.dart';
import 'package:camaleon_billboard/core/db/mysql_client.dart';
import 'package:camaleon_billboard/core/utils/device_identity.dart';
import 'package:camaleon_billboard/data/repositories/billboard_repository_impl.dart';
import 'package:camaleon_billboard/data/repositories/connection_config_repository_impl.dart';
import 'package:camaleon_billboard/domain/entities/db_connection_config.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';
import 'package:camaleon_billboard/domain/repositories/billboard_repository.dart';
import 'package:camaleon_billboard/domain/repositories/connection_config_repository.dart';
import 'package:camaleon_billboard/domain/usecases/load_billboard_usecase.dart';

enum BillboardPhase { bootstrapping, needsConnection, loading, ready, error }

enum AutoConnectOutcome { success, needsPassword, needsDatabase, failed }

class AutoConnectResult {
  const AutoConnectResult({
    required this.outcome,
    this.hosts = const [],
    this.databases = const [],
    this.pendingConfig,
    this.message,
  });

  final AutoConnectOutcome outcome;
  final List<String> hosts;
  final List<String> databases;
  final DbConnectionConfig? pendingConfig;
  final String? message;

  bool get ok => outcome == AutoConnectOutcome.success;
}

class BillboardController extends ChangeNotifier {
  BillboardController({
    MysqlClient? client,
    ConnectionConfigRepository? connectionRepo,
    BillboardRepository? billboardRepo,
  })  : _client = client ?? MysqlClient(),
        _connectionRepo = connectionRepo ?? ConnectionConfigRepositoryImpl() {
    _billboardRepo = billboardRepo ?? BillboardRepositoryImpl(_client);
    _loadBoard = LoadBillboardUseCase(_billboardRepo);
  }

  final MysqlClient _client;
  final ConnectionConfigRepository _connectionRepo;
  late final BillboardRepository _billboardRepo;
  late final LoadBillboardUseCase _loadBoard;

  BillboardPhase phase = BillboardPhase.bootstrapping;
  DbConnectionConfig connection = DbConnectionConfig.empty;
  String computerName = '';
  String detectedComputerName = '';
  bool sortAlphabetical = false;
  int refreshSeconds = 60;
  String? errorMessage;
  BillboardBoard? board;
  bool testing = false;
  bool autoConnecting = false;
  String? autoConnectStatus;
  bool isFirstLaunch = true;
  bool hasSavedConnection = false;

  List<String> knownCompNames = const [];
  List<String> registerNames = const [];
  String? templateCompName;
  List<String> lastDiscoveredHosts = const [];
  List<String> availableDatabases = const [];
  bool searchingDatabases = false;

  /// True while the user is rearranging sections on the board.
  bool layoutEditing = false;
  bool layoutDirty = false;
  bool savingLayout = false;

  Timer? _refreshTimer;

  /// First launch: always show DB settings (prefill shared file if found).
  /// Returning users with saved MySQL prefs: auto-connect.
  Future<void> bootstrap() async {
    phase = BillboardPhase.bootstrapping;
    notifyListeners();

    connection = await _connectionRepo.load();
    detectedComputerName = await DeviceIdentity.resolveComputerName();
    if (Platform.isAndroid && detectedComputerName.trim().isNotEmpty) {
      // Billboard on Android always identifies as the device name (no Windows computerName).
      computerName = detectedComputerName.trim();
      await _connectionRepo.saveComputerName(computerName);
    } else {
      computerName = await _connectionRepo.loadComputerName();
      if (computerName.trim().isEmpty) {
        computerName = detectedComputerName;
      }
    }
    sortAlphabetical = await _connectionRepo.loadSortAlphabetical();
    refreshSeconds = await _connectionRepo.loadRefreshSeconds();

    hasSavedConnection = connection.isComplete;
    isFirstLaunch = !hasSavedConnection;

    if (!connection.isComplete) {
      final shared = await _connectionRepo.tryImportSharedConnection();
      if (shared != null) {
        connection = shared;
      }
      phase = BillboardPhase.needsConnection;
      notifyListeners();
      return;
    }

    final ok = await autoConnect(silent: true, scanLan: false);
    if (!ok.ok) {
      phase = BillboardPhase.needsConnection;
      notifyListeners();
    }
  }

  Future<void> saveConnection(DbConnectionConfig config) async {
    connection = config;
    await _connectionRepo.save(config);
    hasSavedConnection = config.isComplete;
    notifyListeners();
  }

  Future<void> saveComputerName(String name) async {
    // On Android the station id is always the device name.
    final resolved = Platform.isAndroid && detectedComputerName.trim().isNotEmpty
        ? detectedComputerName.trim()
        : name.trim();
    computerName = resolved;
    await _connectionRepo.saveComputerName(computerName);
    notifyListeners();
  }

  Future<void> savePreferences({
    required bool alphabetical,
    required int refresh,
  }) async {
    sortAlphabetical = alphabetical;
    refreshSeconds = refresh;
    await _connectionRepo.saveSortAlphabetical(alphabetical);
    await _connectionRepo.saveRefreshSeconds(refresh);
    notifyListeners();
  }

  bool applyQrPayload(String raw) {
    final qr = DbConnectionQr.parse(raw);
    if (qr == null) return false;
    connection = DbConnectionConfig(
      host: qr.host,
      port: qr.port,
      user: qr.user,
      password: qr.password,
      database: qr.database,
    );
    notifyListeners();
    return true;
  }

  Future<bool> importSharedConnection() async {
    final shared = await _connectionRepo.tryImportSharedConnection();
    if (shared == null) return false;
    connection = shared;
    await _connectionRepo.save(shared);
    hasSavedConnection = shared.isComplete;
    notifyListeners();
    return true;
  }

  Future<bool> testConnection([DbConnectionConfig? config]) async {
    testing = true;
    notifyListeners();
    try {
      final cfg = config ?? connection;
      final ok = await _billboardRepo.testConnection(cfg);
      if (ok) {
        await _billboardRepo.connect(cfg);
        await _refreshNamePickers();
      }
      return ok;
    } finally {
      testing = false;
      notifyListeners();
    }
  }

  Future<void> _refreshNamePickers() async {
    try {
      knownCompNames = await _billboardRepo.listConfiguredComputerNames();
      registerNames = await _billboardRepo.listRegisterNames();
    } catch (_) {
      knownCompNames = const [];
      registerNames = const [];
    }
    notifyListeners();
  }

  void _setProgress(String? msg) {
    autoConnectStatus = msg;
    notifyListeners();
  }

  /// Lists databases for [config] (or LAN host). Updates [availableDatabases].
  Future<({String host, List<String> databases, String? error})> searchDatabases({
    DbConnectionConfig? config,
    String? passwordOverride,
  }) async {
    searchingDatabases = true;
    errorMessage = null;
    autoConnectStatus = 'Searching for databases…';
    notifyListeners();

    try {
      var cfg = config ?? connection;
      if (passwordOverride != null) {
        cfg = cfg.copyWith(password: passwordOverride);
      }

      final passwords = <String>[
        if (cfg.password.isNotEmpty) cfg.password,
        ?passwordOverride,
        kDefaultMysqlPassword,
        '',
      ];
      final uniquePass = <String>[];
      for (final p in passwords) {
        if (!uniquePass.contains(p)) uniquePass.add(p);
      }

      final user =
          cfg.user.trim().isEmpty ? kDefaultMysqlUser : cfg.user.trim();
      final port = cfg.port <= 0 ? kDefaultMysqlPort : cfg.port;

      var hosts = <String>[];
      final hint = cfg.host.trim();
      if (hint.isNotEmpty) {
        hosts.add(hint);
      } else {
        autoConnectStatus = 'Searching for MySQL on the network…';
        notifyListeners();
        hosts = await LanMysqlDiscovery.findMysqlHosts(onProgress: _setProgress);
      }

      if (hosts.isEmpty) {
        errorMessage = 'No MySQL found to list databases.';
        return (host: '', databases: const <String>[], error: errorMessage);
      }

      for (final host in hosts) {
        for (final password in uniquePass) {
          autoConnectStatus = 'Listing databases on $host…';
          notifyListeners();
          final dbs = await LanMysqlDiscovery.listDatabases(
            host: host,
            port: port,
            user: user,
            password: password,
          );
          if (dbs.isEmpty) continue;

          availableDatabases = List.unmodifiable(dbs);
          lastDiscoveredHosts = List.unmodifiable([host]);
          connection = connection.copyWith(
            host: host,
            port: port,
            user: user,
            password: password,
          );
          autoConnectStatus = null;
          notifyListeners();
          return (host: host, databases: dbs, error: null);
        }
      }

      errorMessage =
          'MySQL found, but databases could not be listed. Check the password.';
      return (
        host: hosts.first,
        databases: const <String>[],
        error: errorMessage,
      );
    } catch (e) {
      errorMessage = e.toString();
      return (host: '', databases: const <String>[], error: errorMessage);
    } finally {
      searchingDatabases = false;
      notifyListeners();
    }
  }

  /// Tries saved/QR/form config, then LAN discovery with default password
  /// [kDefaultMysqlPassword]. If MySQL hosts answer but auth fails, returns
  /// [AutoConnectOutcome.needsPassword] so the UI can ask for another pass.
  Future<AutoConnectResult> autoConnect({
    DbConnectionConfig? config,
    String? compName,
    bool silent = false,
    bool createArrangementIfMissing = true,
    bool scanLan = true,
    String? passwordOverride,
    List<String>? hostsHint,
  }) async {
    if (!silent) {
      autoConnecting = true;
      errorMessage = null;
      autoConnectStatus = null;
      notifyListeners();
    }

    try {
      final name = () {
        if (Platform.isAndroid && detectedComputerName.trim().isNotEmpty) {
          return detectedComputerName.trim();
        }
        final fromArg = (compName ?? computerName).trim();
        return fromArg.isEmpty ? detectedComputerName : fromArg;
      }();

      var cfg = config ?? connection;
      if (passwordOverride != null) {
        cfg = cfg.copyWith(password: passwordOverride);
      }
      if (!cfg.isComplete) {
        final shared = await _connectionRepo.tryImportSharedConnection();
        if (shared != null) {
          cfg = passwordOverride != null
              ? shared.copyWith(password: passwordOverride)
              : shared;
        }
      }

      final explicitHost = cfg.host.trim();

      if (cfg.isComplete) {
        _setProgress('Connecting to ${cfg.host}…');
        final ok = await _billboardRepo.testConnection(cfg);
        if (ok) {
          await saveConnection(cfg);
          await saveComputerName(name);
          await openBoard(
            createArrangementIfMissing: createArrangementIfMissing,
          );
          return const AutoConnectResult(outcome: AutoConnectOutcome.success);
        }
      }

      // Prefer an explicit host (form / QR / hint) — never LAN-scan in that case.
      late final List<String> hosts;
      if (hostsHint?.isNotEmpty == true) {
        hosts = List<String>.from(hostsHint!);
        if (explicitHost.isNotEmpty && !hosts.contains(explicitHost)) {
          hosts.insert(0, explicitHost);
        }
        _setProgress('Connecting to ${hosts.first}…');
      } else if (explicitHost.isNotEmpty) {
        hosts = [explicitHost];
        _setProgress('Connecting to $explicitHost…');
      } else if (scanLan) {
        _setProgress('Searching for MySQL on the network…');
        hosts = await LanMysqlDiscovery.findMysqlHosts(
          onProgress: silent ? null : _setProgress,
        );
      } else {
        errorMessage = 'Could not connect to MySQL.';
        return AutoConnectResult(
          outcome: AutoConnectOutcome.failed,
          message: errorMessage,
        );
      }

      lastDiscoveredHosts = List.unmodifiable(hosts);

      if (hosts.isEmpty) {
        errorMessage =
            'No MySQL found on the network. Scan the POS QR or enter the server.';
        if (!silent) {
          phase = BillboardPhase.needsConnection;
          notifyListeners();
        }
        return AutoConnectResult(
          outcome: AutoConnectOutcome.failed,
          message: errorMessage,
        );
      }

      final user = (config?.user.trim().isNotEmpty == true)
          ? config!.user.trim()
          : (connection.user.trim().isNotEmpty
              ? connection.user.trim()
              : kDefaultMysqlUser);
      final preferredDb = (config?.database.trim().isNotEmpty == true)
          ? config!.database.trim()
          : (connection.database.trim().isNotEmpty
              ? connection.database.trim()
              : null);

      final passwords = <String>[
        ?passwordOverride,
        kDefaultMysqlPassword,
        if ((config ?? connection).password.isNotEmpty)
          (config ?? connection).password,
        '',
      ];

      _setProgress(
        hosts.length == 1
            ? 'Trying $user on ${hosts.first}…'
            : 'Found ${hosts.length} · trying $user…',
      );
      final attempt = await LanMysqlDiscovery.tryConnectHosts(
        hosts: hosts,
        passwords: passwords,
        user: user,
        preferredDatabase: preferredDb,
        onProgress: silent ? null : _setProgress,
      );

      if (attempt?.ready != null) {
        await saveConnection(attempt!.ready!);
        await saveComputerName(name);
        await openBoard(createArrangementIfMissing: createArrangementIfMissing);
        return AutoConnectResult(
          outcome: AutoConnectOutcome.success,
          hosts: hosts,
        );
      }

      final hit = attempt?.hit;
      if (hit != null) {
        availableDatabases = List.unmodifiable(hit.databases);
        lastDiscoveredHosts = List.unmodifiable([
          hit.host,
          ...hosts.where((h) => h != hit.host),
        ]);
        // Persist the host we actually authenticated against so the form
        // never snaps back to a previous saved IP when picking a database.
        connection = connection.copyWith(
          host: hit.host,
          port: hit.port,
          user: hit.user,
          password: hit.password,
        );
      }

      if (hit != null && hit.databases.length > 1) {
        errorMessage =
            'Found ${hit.databases.length} databases on ${hit.host}. Pick one.';
        if (!silent) {
          phase = BillboardPhase.needsConnection;
          notifyListeners();
        }
        return AutoConnectResult(
          outcome: AutoConnectOutcome.needsDatabase,
          hosts: hosts,
          databases: hit.databases,
          pendingConfig: hit.asConfig(''),
          message: errorMessage,
        );
      }

      // Auth failed on the host(s) we tried → ask user for password.
      errorMessage = hosts.length == 1
          ? 'Could not sign in to ${hosts.first}. Check the password.'
          : 'MySQL found on the network (${hosts.length}). Default password "$kDefaultMysqlPassword" did not work.';
      if (!silent) {
        phase = BillboardPhase.needsConnection;
        notifyListeners();
      }
      return AutoConnectResult(
        outcome: AutoConnectOutcome.needsPassword,
        hosts: hosts,
        message: errorMessage,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('autoConnect failed: $e\n$st');
      errorMessage = e.toString();
      if (!silent) {
        phase = BillboardPhase.needsConnection;
        notifyListeners();
      }
      return AutoConnectResult(
        outcome: AutoConnectOutcome.failed,
        message: errorMessage,
      );
    } finally {
      autoConnecting = false;
      autoConnectStatus = null;
      notifyListeners();
    }
  }

  Future<void> openBoard({bool createArrangementIfMissing = true}) async {
    _refreshTimer?.cancel();
    phase = BillboardPhase.loading;
    errorMessage = null;
    notifyListeners();

    try {
      await _connectionRepo.save(connection);
      await _connectionRepo.saveComputerName(computerName);
      await _billboardRepo.connect(connection);
      await _refreshNamePickers();

      if (createArrangementIfMissing) {
        final template = templateCompName;
        await _billboardRepo.ensureArrangementForComputer(
          compName: computerName,
          templateCompName: template,
        );
        // One-shot: avoid re-wiping local layout on every reconnect.
        if (template != null && template.trim().isNotEmpty) {
          templateCompName = null;
        }
      }

      board = await _loadBoard(
        compName: computerName,
        sortAlphabetical: sortAlphabetical,
      );
      phase = BillboardPhase.ready;
      isFirstLaunch = false;
      _scheduleRefresh();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Billboard open failed: $e\n$st');
      }
      errorMessage = e.toString();
      phase = BillboardPhase.error;
    }
    notifyListeners();
  }

  Future<void> reloadSilent() async {
    if (phase != BillboardPhase.ready) return;
    if (layoutEditing || layoutDirty) return;
    try {
      final next = await _loadBoard(
        compName: computerName,
        sortAlphabetical: sortAlphabetical,
      );
      board = next;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('Silent reload failed: $e');
    }
  }

  void beginLayoutEdit() {
    if (phase != BillboardPhase.ready || board == null) return;
    layoutEditing = true;
    _refreshTimer?.cancel();
    notifyListeners();
  }

  void markLayoutDirty() {
    if (!layoutEditing || layoutDirty) return;
    layoutDirty = true;
    // Defer notify so we don't rebuild mid pan-start (cancels the drag).
    scheduleMicrotask(() {
      if (layoutEditing && layoutDirty) notifyListeners();
    });
  }

  Future<void> cancelLayoutEdit() async {
    layoutEditing = false;
    layoutDirty = false;
    savingLayout = false;
    notifyListeners();
    await reloadSilent();
    if (phase == BillboardPhase.ready) _scheduleRefresh();
  }

  /// Absolute geometry write — call once on drag/resize end (not per frame).
  void commitArrangementGeometry({
    required int arrangementId,
    int? xDistance,
    int? yDistance,
    int? maxWidth,
    int maxX = 100000,
    int maxY = 100000,
  }) {
    final b = board;
    if (b == null || !layoutEditing) return;
    final xCap = maxX < 0 ? 0 : maxX;
    final yCap = maxY < 0 ? 0 : maxY;

    var changed = false;

    final sections = b.sections.map((s) {
      if (s.arrangement.id != arrangementId) return s;
      final a = s.arrangement;
      final nx = (xDistance ?? a.xDistance).clamp(0, xCap);
      final ny = (yDistance ?? a.yDistance).clamp(0, yCap);
      final nw =
          maxWidth == null ? a.maxWidth : maxWidth.clamp(120, 20000);
      if (nx == a.xDistance && ny == a.yDistance && nw == a.maxWidth) {
        return s;
      }
      changed = true;
      return s.copyWith(
        arrangement: a.copyWith(
          xDistance: nx,
          yDistance: ny,
          maxWidth: nw,
        ),
      );
    }).toList(growable: false);

    final pictures = b.pictures.map((p) {
      if (p.arrangement.id != arrangementId) return p;
      final a = p.arrangement;
      final nx = (xDistance ?? a.xDistance).clamp(0, xCap);
      final ny = (yDistance ?? a.yDistance).clamp(0, yCap);
      if (nx == a.xDistance && ny == a.yDistance) return p;
      changed = true;
      return p.copyWith(
        arrangement: a.copyWith(xDistance: nx, yDistance: ny),
      );
    }).toList(growable: false);

    if (!changed) return;
    board = b.copyWith(sections: sections, pictures: pictures);
    layoutDirty = true;
    notifyListeners();
  }

  void resizeArrangement({
    required int arrangementId,
    required int maxWidth,
  }) {
    commitArrangementGeometry(
      arrangementId: arrangementId,
      maxWidth: maxWidth,
    );
  }

  void nudgeFonts({
    required int arrangementId,
    int classDelta = 0,
    int itemDelta = 0,
  }) {
    final b = board;
    if (b == null || !layoutEditing) return;
    if (classDelta == 0 && itemDelta == 0) return;

    board = b.copyWith(
      sections: [
        for (final s in b.sections)
          if (s.arrangement.id == arrangementId)
            s.copyWith(
              arrangement: s.arrangement.copyWith(
                classFontSize:
                    (s.arrangement.classFontSize + classDelta).clamp(10, 96),
                itemFontSize:
                    (s.arrangement.itemFontSize + itemDelta).clamp(8, 72),
              ),
            )
          else
            s,
      ],
    );
    layoutDirty = true;
    notifyListeners();
  }

  /// Writes current section/picture positions to `bb_arrangement` for this device.
  Future<bool> saveLayoutEdits() async {
    final b = board;
    if (b == null || !layoutDirty) {
      layoutEditing = false;
      notifyListeners();
      if (phase == BillboardPhase.ready) _scheduleRefresh();
      return true;
    }

    savingLayout = true;
    errorMessage = null;
    notifyListeners();

    try {
      final name = computerName.trim();
      for (final s in b.sections) {
        final a = s.arrangement;
        await _billboardRepo.updateArrangementLayout(
          id: a.id,
          compName: name,
          xDistance: a.xDistance,
          yDistance: a.yDistance,
          maxWidth: a.maxWidth,
          classFontSize: a.classFontSize,
          itemFontSize: a.itemFontSize,
        );
      }
      for (final p in b.pictures) {
        final a = p.arrangement;
        await _billboardRepo.updateArrangementLayout(
          id: a.id,
          compName: name,
          xDistance: a.xDistance,
          yDistance: a.yDistance,
          maxWidth: a.maxWidth,
        );
      }
      layoutDirty = false;
      layoutEditing = false;
      savingLayout = false;
      notifyListeners();
      _scheduleRefresh();
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Save layout failed: $e\n$st');
      errorMessage = e.toString();
      savingLayout = false;
      notifyListeners();
      return false;
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (layoutEditing) return;
    _refreshTimer = Timer.periodic(
      Duration(seconds: refreshSeconds),
      (_) => reloadSilent(),
    );
  }

  Future<void> disconnectToSettings() async {
    _refreshTimer?.cancel();
    layoutEditing = false;
    layoutDirty = false;
    savingLayout = false;
    await _billboardRepo.disconnect();
    phase = BillboardPhase.needsConnection;
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(_billboardRepo.disconnect());
    super.dispose();
  }
}
