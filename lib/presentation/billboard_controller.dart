import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:camaleon_billboard/core/db/db_connection_qr.dart';
import 'package:camaleon_billboard/core/db/lan_mysql_discovery.dart';
import 'package:camaleon_billboard/core/db/mysql_client.dart';
import 'package:camaleon_billboard/core/errors/app_failure.dart';
import 'package:camaleon_billboard/core/utils/device_identity.dart';
import 'package:camaleon_billboard/core/utils/qb_color.dart';
import 'package:camaleon_billboard/data/repositories/billboard_repository_impl.dart';
import 'package:camaleon_billboard/data/repositories/connection_config_repository_impl.dart';
import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/domain/entities/db_connection_config.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';
import 'package:camaleon_billboard/domain/repositories/billboard_repository.dart';
import 'package:camaleon_billboard/domain/repositories/connection_config_repository.dart';
import 'package:camaleon_billboard/domain/usecases/load_billboard_usecase.dart';

enum BillboardPhase { bootstrapping, needsConnection, loading, ready, error }

enum AutoConnectOutcome { success, needsPassword, needsDatabase, failed }

enum _PendingBoardBg { none, image, video, clear }

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
  int refreshSeconds = 5;
  bool customerDisplay = false;
  bool _customerDisplaySaved = false;
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

  /// Negative local IDs for blocks created in this session (INSERT on Save).
  int _nextTempId = -1;

  /// Rows removed in UI during edit — deleted from DB only on Save.
  final List<int> _sessionDeletedIds = [];

  /// Picture ids whose media changed in memory — persisted on Save.
  final Set<int> _pendingMediaIds = {};

  _PendingBoardBg _pendingBoardBg = _PendingBoardBg.none;
  List<int>? _pendingBoardBgImageBytes;
  String? _pendingBoardBgVideoFile;
  String? _pendingBoardBgVideoRoute;

  Timer? _refreshTimer;
  bool _reloadInFlight = false;
  int _pollTick = 0;

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
    customerDisplay = await _connectionRepo.loadCustomerDisplay();
    _customerDisplaySaved = customerDisplay;

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

  void setCustomerDisplay(bool enabled) {
    if (!layoutEditing) return;
    if (customerDisplay == enabled) return;
    customerDisplay = enabled;
    markLayoutDirty();
    notifyListeners();
  }

  void _clearSessionPending() {
    _sessionDeletedIds.clear();
    _pendingMediaIds.clear();
    _pendingBoardBg = _PendingBoardBg.none;
    _pendingBoardBgImageBytes = null;
    _pendingBoardBgVideoFile = null;
    _pendingBoardBgVideoRoute = null;
    _nextTempId = -1;
  }

  int _allocTempId() {
    final id = _nextTempId;
    _nextTempId -= 1;
    return id;
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
      errorMessage = AppFailure.message(e);
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
      errorMessage = AppFailure.message(e);
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
      errorMessage = AppFailure.message(e);
      phase = BillboardPhase.error;
    }
    notifyListeners();
  }

  Future<void> reloadSilent({bool full = false}) async {
    if (phase != BillboardPhase.ready) return;
    if (layoutEditing || layoutDirty || savingLayout) return;
    if (_reloadInFlight) return;
    _reloadInFlight = true;
    try {
      final current = board;
      final BillboardBoard next;
      if (full || current == null) {
        next = await _loadBoard(
          compName: computerName,
          sortAlphabetical: sortAlphabetical,
        );
      } else {
        // Light poll: prices / names / specials only — no bb_pic blobs.
        next = await _billboardRepo.refreshMenuItems(
          current,
          sortAlphabetical: sortAlphabetical,
        );
      }
      if (layoutEditing || layoutDirty || savingLayout) return;
      board = next;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('Silent reload failed: $e');
    } finally {
      _reloadInFlight = false;
    }
  }

  void beginLayoutEdit() {
    if (phase != BillboardPhase.ready || board == null) return;
    layoutEditing = true;
    creatingBlock = false;
    uploadingBoardBackground = false;
    _clearSessionPending();
    _customerDisplaySaved = customerDisplay;
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
    customerDisplay = _customerDisplaySaved;
    // Temp blocks never hit the DB — Discard just reloads the last saved board.
    _clearSessionPending();
    notifyListeners();
    await reloadSilent(full: true);
    if (phase == BillboardPhase.ready) _scheduleRefresh();
  }

  /// Absolute geometry write — call once on drag/resize end (not per frame).
  void commitArrangementGeometry({
    required int arrangementId,
    int? xDistance,
    int? yDistance,
    int? maxWidth,
    int minWidth = 120,
    int maxX = 100000,
    int maxY = 100000,
  }) {
    final b = board;
    if (b == null || !layoutEditing) return;
    final xCap = maxX < 0 ? 0 : maxX;
    final yCap = maxY < 0 ? 0 : maxY;
    final wMin = minWidth.clamp(40, 20000);

    var changed = false;

    final sections = b.sections.map((s) {
      if (s.arrangement.id != arrangementId) return s;
      final a = s.arrangement;
      final nx = (xDistance ?? a.xDistance).clamp(0, xCap);
      final ny = (yDistance ?? a.yDistance).clamp(0, yCap);
      final nw =
          maxWidth == null ? a.maxWidth : maxWidth.clamp(wMin, 20000);
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
      final nw =
          maxWidth == null ? a.maxWidth : maxWidth.clamp(wMin, 20000);
      if (nx == a.xDistance && ny == a.yDistance && nw == a.maxWidth) {
        return p;
      }
      changed = true;
      return p.copyWith(
        arrangement: a.copyWith(
          xDistance: nx,
          yDistance: ny,
          maxWidth: nw,
        ),
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
    int minWidth = 80,
  }) {
    commitArrangementGeometry(
      arrangementId: arrangementId,
      maxWidth: maxWidth,
      minWidth: minWidth,
    );
  }

  void nudgeFonts({
    required int arrangementId,
    int classDelta = 0,
    int itemDelta = 0,
  }) {
    updateArrangementStyle(
      arrangementId: arrangementId,
      classFontDelta: classDelta,
      itemFontDelta: itemDelta,
    );
  }

  /// Patch style fields on one section/picture arrangement.
  void updateArrangementStyle({
    required int arrangementId,
    int? classFontDelta,
    int? itemFontDelta,
    int? classFontSize,
    int? itemFontSize,
    int? modifierFontSize,
    int? classForeColor,
    int? classBackColor,
    int? itemForeColor,
    int? itemBackColor,
    int? mainBackColor,
    int? modifierColor,
    bool? classBold,
    bool? itemBold,
    bool? classUpperCase,
    bool? itemUpperCase,
    String? classFontName,
    String? itemFontName,
    String? modifierFontName,
    String? detailDescription,
    bool? boardBackground,
    ArrangementContentType? contentType,
    int? offerId,
    ArrangementMediaType? mediaType,
    String? mediaFile,
    ArrangementMediaFit? mediaFit,
    double? mediaOpacity,
    int? displayOrder,
    int? displaySeconds,
    int? rangeOffset,
    int? rangeCount,
    int? borderWidth,
    String? borderColor,
    bool? videoLoop,
    bool? videoMuted,
  }) {
    final b = board;
    if (b == null || !layoutEditing) return;

    var rangeChanged = false;

    ArrangementBlock patch(ArrangementBlock a) {
      var next = a;
      if (classFontDelta != null) {
        next = next.copyWith(
          classFontSize: (next.classFontSize + classFontDelta).clamp(10, 96),
        );
      }
      if (itemFontDelta != null) {
        next = next.copyWith(
          itemFontSize: (next.itemFontSize + itemFontDelta).clamp(8, 72),
        );
      }
      if (classFontSize != null) {
        next = next.copyWith(classFontSize: classFontSize.clamp(10, 96));
      }
      if (itemFontSize != null) {
        next = next.copyWith(itemFontSize: itemFontSize.clamp(8, 72));
      }
      if (modifierFontSize != null) {
        next =
            next.copyWith(modifierFontSize: modifierFontSize.clamp(8, 48));
      }
      if (classForeColor != null) {
        next = next.copyWith(classForeColor: QbColors.clampOpaque(classForeColor));
      }
      if (classBackColor != null) {
        next = next.copyWith(classBackColor: QbColors.clampFill(classBackColor));
      }
      if (itemForeColor != null) {
        next = next.copyWith(itemForeColor: QbColors.clampOpaque(itemForeColor));
      }
      if (itemBackColor != null) {
        next = next.copyWith(itemBackColor: QbColors.clampFill(itemBackColor));
      }
      if (mainBackColor != null) {
        next = next.copyWith(mainBackColor: QbColors.clampOpaque(mainBackColor));
      }
      if (modifierColor != null) {
        next = next.copyWith(modifierColor: QbColors.clampOpaque(modifierColor));
      }
      if (classBold != null) next = next.copyWith(classBold: classBold);
      if (itemBold != null) next = next.copyWith(itemBold: itemBold);
      if (classUpperCase != null) {
        next = next.copyWith(classUpperCase: classUpperCase);
      }
      if (itemUpperCase != null) {
        next = next.copyWith(itemUpperCase: itemUpperCase);
      }
      if (classFontName != null) {
        next = next.copyWith(classFontName: classFontName);
      }
      if (itemFontName != null) {
        next = next.copyWith(itemFontName: itemFontName);
      }
      if (modifierFontName != null) {
        next = next.copyWith(modifierFontName: modifierFontName);
      }
      if (boardBackground != null) {
        next = next.copyWith(boardBackground: boardBackground);
      } else if (detailDescription != null) {
        next = next.copyWith(detailDescription: detailDescription);
      }
      if (contentType != null) {
        next = next.copyWith(contentType: contentType);
      }
      if (offerId != null) {
        next = next.copyWith(offerId: offerId.clamp(0, 2147483647));
      }
      if (mediaType != null) {
        if (mediaType == ArrangementMediaType.video) {
          // Drop the image blob so the block actually becomes a video.
          next = next.copyWith(
            mediaType: mediaType,
            clearPictureBytes: true,
          );
        } else if (mediaType == ArrangementMediaType.image) {
          next = next.copyWith(mediaType: mediaType);
        } else {
          next = next.copyWith(
            mediaType: mediaType,
            mediaFile: '',
            pictureRoute: '',
            clearPictureBytes: true,
          );
        }
        if (arrangementId != 0) _pendingMediaIds.add(arrangementId);
      }
      if (mediaFile != null) {
        next = next.copyWith(
          mediaFile: mediaFile,
          // Live preview uses pictureRoute; keep it in sync for IMAGE paths.
          pictureRoute: mediaFile.isNotEmpty ? mediaFile : next.pictureRoute,
        );
        if (arrangementId != 0) _pendingMediaIds.add(arrangementId);
      }
      if (mediaFit != null) next = next.copyWith(mediaFit: mediaFit);
      if (mediaOpacity != null) {
        next = next.copyWith(
          mediaOpacity: mediaOpacity.clamp(0.0, 1.0),
        );
      }
      if (displayOrder != null) {
        next = next.copyWith(displayOrder: displayOrder.clamp(0, 100000));
      }
      if (displaySeconds != null) {
        next = next.copyWith(displaySeconds: displaySeconds.clamp(0, 3600));
      }
      if (rangeOffset != null || rangeCount != null) {
        var o = rangeOffset ?? next.rangeOffset;
        var c = rangeCount ?? next.rangeCount;
        // First Skip while "all" → start a sensible window (Classic style).
        if (rangeOffset != null && c <= 0) c = 12;
        final encoded = ArrangementBlock.encodeRangeItems(
          offset: o,
          count: c,
        );
        if (encoded != next.rangeItems) {
          next = next.copyWith(rangeItems: encoded);
          rangeChanged = true;
        }
      }
      if (borderWidth != null) {
        final w = borderWidth.clamp(0, 200);
        next = next.copyWith(
          borderTopWidth: w,
          borderRightWidth: w,
          borderBottomWidth: w,
          borderLeftWidth: w,
        );
      }
      if (borderColor != null) {
        next = next.copyWith(
          borderTopColor: borderColor,
          borderRightColor: borderColor,
          borderBottomColor: borderColor,
          borderLeftColor: borderColor,
        );
      }
      if (videoLoop != null) next = next.copyWith(videoLoop: videoLoop);
      if (videoMuted != null) next = next.copyWith(videoMuted: videoMuted);
      return next;
    }

    // Only one photo may be board background — turning one on clears the rest.
    final clearOtherBackgrounds = boardBackground == true;

    board = b.copyWith(
      sections: [
        for (final s in b.sections)
          if (s.arrangement.id == arrangementId)
            s.copyWith(arrangement: patch(s.arrangement))
          else if (mainBackColor != null)
            s.copyWith(
              arrangement: s.arrangement.copyWith(
                mainBackColor: mainBackColor.clamp(0, 15),
              ),
            )
          else
            s,
      ],
      pictures: [
        for (final p in b.pictures)
          if (p.arrangement.id == arrangementId)
            p.copyWith(arrangement: patch(p.arrangement))
          else if (clearOtherBackgrounds && p.arrangement.boardBackground)
            p.copyWith(
              arrangement: p.arrangement.copyWith(boardBackground: false),
            )
          else if (mainBackColor != null)
            p.copyWith(
              arrangement: p.arrangement.copyWith(
                mainBackColor: mainBackColor.clamp(0, 15),
              ),
            )
          else
            p,
      ],
      mainBackColor: mainBackColor?.clamp(0, 15) ?? b.mainBackColor,
    );
    layoutDirty = true;
    notifyListeners();
    if (rangeChanged) {
      unawaited(_refreshSectionItems(arrangementId));
    }
  }

  Future<void> _refreshSectionItems(int arrangementId) async {
    final b = board;
    if (b == null || !layoutEditing) return;
    MenuSection? target;
    for (final s in b.sections) {
      if (s.arrangement.id == arrangementId) {
        target = s;
        break;
      }
    }
    if (target == null) return;

    try {
      final loaded = await _billboardRepo.fillClassView(
        target.arrangement,
        sortAlphabetical: sortAlphabetical,
      );
      final current = board;
      if (current == null || !layoutEditing) return;
      board = current.copyWith(
        sections: [
          for (final s in current.sections)
            if (s.arrangement.id == arrangementId)
              s.copyWith(
                className: loaded.className,
                items: loaded.items,
              )
            else
              s,
        ],
      );
      notifyListeners();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Refresh section items after range change failed: $e\n$st');
      }
    }
  }

  void setBoardBackgroundColor(int qbIndex) {
    final b = board;
    if (b == null || !layoutEditing) return;
    final color = qbIndex.clamp(0, 15);
    board = b.copyWith(
      mainBackColor: color,
      sections: [
        for (final s in b.sections)
          s.copyWith(
            arrangement: s.arrangement.copyWith(mainBackColor: color),
          ),
      ],
      pictures: [
        for (final p in b.pictures)
          p.copyWith(
            arrangement: p.arrangement.copyWith(mainBackColor: color),
          ),
      ],
    );
    layoutDirty = true;
    notifyListeners();
  }

  bool uploadingBoardBackground = false;

  /// Stages a board background image in memory — persisted on Save.
  Future<bool> setBoardBackgroundImage(List<int> bytes) async {
    final b = board;
    if (b == null || bytes.isEmpty || !layoutEditing) return false;

    uploadingBoardBackground = true;
    errorMessage = null;
    notifyListeners();

    try {
      _pendingBoardBg = _PendingBoardBg.image;
      _pendingBoardBgImageBytes = List<int>.from(bytes);
      _pendingBoardBgVideoFile = null;
      _pendingBoardBgVideoRoute = null;

      final others = [
        for (final p in b.pictures)
          if (!p.arrangement.isBoardBackground) p,
      ];
      final existing = b.boardBackgroundPictures.isEmpty
          ? null
          : b.boardBackgroundPictures.first;
      final id = existing?.arrangement.id ?? -1;
      board = b.copyWith(
        pictures: [
          ...others,
          PictureBlock(
            arrangement: ArrangementBlock(
              id: id,
              compName: b.compName,
              screenName: 'Board background',
              maxWidth: 1920,
              mainBackColor: b.mainBackColor,
              usePicture: true,
              boardBackground: true,
              mediaType: ArrangementMediaType.image,
              mediaFit: ArrangementMediaFit.cover,
              pictureBytes: Uint8List.fromList(bytes),
            ),
          ),
        ],
      );
      layoutDirty = true;
      uploadingBoardBackground = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Board background stage failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      uploadingBoardBackground = false;
      notifyListeners();
      return false;
    }
  }

  /// Stages a board background video in memory — persisted on Save.
  Future<bool> setBoardBackgroundVideo({
    required String mediaFile,
    String pictureRoute = '',
    bool videoLoop = true,
    bool videoMuted = true,
  }) async {
    final b = board;
    if (b == null || mediaFile.trim().isEmpty || !layoutEditing) return false;

    uploadingBoardBackground = true;
    errorMessage = null;
    notifyListeners();

    try {
      final file = mediaFile.trim();
      final route = pictureRoute.trim().isNotEmpty ? pictureRoute.trim() : file;
      _pendingBoardBg = _PendingBoardBg.video;
      _pendingBoardBgVideoFile = file;
      _pendingBoardBgVideoRoute = route;
      _pendingBoardBgImageBytes = null;

      final others = [
        for (final p in b.pictures)
          if (!p.arrangement.isBoardBackground) p,
      ];
      final existing = b.boardBackgroundPictures.isEmpty
          ? null
          : b.boardBackgroundPictures.first;
      final id = existing?.arrangement.id ?? -1;
      board = b.copyWith(
        pictures: [
          ...others,
          PictureBlock(
            arrangement: ArrangementBlock(
              id: id,
              compName: b.compName,
              screenName: 'Board background',
              maxWidth: 1920,
              mainBackColor: b.mainBackColor,
              usePicture: true,
              boardBackground: true,
              mediaType: ArrangementMediaType.video,
              mediaFile: file,
              pictureRoute: route,
              mediaFit: ArrangementMediaFit.cover,
              videoLoop: videoLoop,
              videoMuted: videoMuted,
            ),
          ),
        ],
      );
      layoutDirty = true;
      uploadingBoardBackground = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Board background video stage failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      uploadingBoardBackground = false;
      notifyListeners();
      return false;
    }
  }

  /// Stages removal of board background — persisted on Save.
  Future<bool> clearBoardBackgroundImage() async {
    final b = board;
    if (b == null || !layoutEditing) return false;

    uploadingBoardBackground = true;
    errorMessage = null;
    notifyListeners();

    try {
      _pendingBoardBg = _PendingBoardBg.clear;
      _pendingBoardBgImageBytes = null;
      _pendingBoardBgVideoFile = null;
      _pendingBoardBgVideoRoute = null;
      board = b.copyWith(
        pictures: [
          for (final p in b.pictures)
            if (!p.arrangement.isBoardBackground) p,
        ],
      );
      layoutDirty = true;
      uploadingBoardBackground = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Clear board background stage failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      uploadingBoardBackground = false;
      notifyListeners();
      return false;
    }
  }

  bool creatingBlock = false;

  Future<List<MenuClassOption>> listMenuClasses() async {
    try {
      return await _billboardRepo.listMenuClasses();
    } catch (e, st) {
      if (kDebugMode) debugPrint('List menu classes failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      notifyListeners();
      return const [];
    }
  }

  /// Creates a new menu section in memory (INSERT on Save). Returns temp ID.
  Future<int?> addMenuBlock({
    required int classId,
    required String className,
  }) async {
    final b = board;
    final name = computerName.trim();
    if (b == null || name.isEmpty || !layoutEditing) return null;
    if (classId <= 0) return null;

    creatingBlock = true;
    errorMessage = null;
    notifyListeners();

    try {
      final index = b.sections.length + b.pictures.length;
      final id = _allocTempId();
      final title = className.trim().isEmpty ? 'Screen' : className.trim();
      final block = ArrangementBlock(
        id: id,
        compName: name,
        screenName: title,
        classId: classId,
        xDistance: 40 + (index % 4) * 36,
        yDistance: 40 + index * 36,
        maxWidth: 600,
        mainBackColor: b.mainBackColor,
        classForeColor: 15,
        classBackColor: 2,
        itemForeColor: 15,
        itemBackColor: 0,
        displayOrder: index + 1,
        displaySeconds: 0,
        usePicture: false,
      );
      final section = await _billboardRepo.fillClassView(
        block,
        sortAlphabetical: sortAlphabetical,
      );

      board = b.copyWith(sections: [...b.sections, section]);
      _sessionDeletedIds.remove(id);
      layoutDirty = true;
      creatingBlock = false;
      notifyListeners();
      return id;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Add menu block failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      creatingBlock = false;
      notifyListeners();
      return null;
    }
  }

  /// Creates a new empty photo/media block in memory (INSERT on Save).
  Future<int?> addPhotoBlock({String screenName = 'Photo'}) async {
    final b = board;
    final name = computerName.trim();
    if (b == null || name.isEmpty || !layoutEditing) return null;

    creatingBlock = true;
    errorMessage = null;
    notifyListeners();

    try {
      final visiblePics =
          b.pictures.where((p) => !p.arrangement.isBoardBackground).length;
      final index = b.sections.length + visiblePics;
      final id = _allocTempId();
      final title = screenName.trim().isEmpty ? 'Photo' : screenName.trim();
      final block = ArrangementBlock(
        id: id,
        compName: name,
        screenName: title,
        classId: 0,
        xDistance: 80 + (index % 4) * 40,
        yDistance: 80 + index * 40,
        maxWidth: 400,
        mainBackColor: b.mainBackColor,
        displayOrder: index + 1,
        displaySeconds: 0,
        usePicture: true,
        itemBackColor: 15,
        itemForeColor: 0,
      );

      board = b.copyWith(
        pictures: [
          ...b.pictures,
          PictureBlock(arrangement: block),
        ],
      );
      _sessionDeletedIds.remove(id);
      layoutDirty = true;
      creatingBlock = false;
      notifyListeners();
      return id;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Add photo block failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      creatingBlock = false;
      notifyListeners();
      return null;
    }
  }

  /// Removes the block from the board in memory — DB delete happens on Save.
  Future<bool> deleteArrangement(int arrangementId) async {
    final b = board;
    if (b == null || arrangementId == 0) {
      errorMessage = 'Nothing selected to delete';
      notifyListeners();
      return false;
    }
    if (!layoutEditing) {
      errorMessage = 'Enter Edit mode before deleting';
      notifyListeners();
      return false;
    }

    creatingBlock = true;
    errorMessage = null;
    notifyListeners();

    try {
      // Temp (never-inserted) blocks: drop from memory only.
      if (arrangementId < 0) {
        _pendingMediaIds.remove(arrangementId);
      } else if (!_sessionDeletedIds.contains(arrangementId)) {
        _sessionDeletedIds.add(arrangementId);
      }

      board = b.copyWith(
        sections: [
          for (final s in b.sections)
            if (s.arrangement.id != arrangementId) s,
        ],
        pictures: [
          for (final p in b.pictures)
            if (p.arrangement.id != arrangementId) p,
        ],
      );
      _pendingMediaIds.remove(arrangementId);
      layoutDirty = true;
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Delete arrangement failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      return false;
    } finally {
      creatingBlock = false;
      notifyListeners();
    }
  }

  /// Stages media on a photo block in memory — persisted on Save.
  ///
  /// IMAGE → `bb_pic` blob + `media_file` name (both).
  /// VIDEO → `media_file` / `bbpic_route` path only (no huge blob).
  Future<bool> applyPickedMedia({
    required int arrangementId,
    required ArrangementMediaType mediaType,
    required String mediaFile,
    String pictureRoute = '',
    List<int>? pictureBytes,
  }) async {
    final b = board;
    if (b == null || !layoutEditing) return false;
    if (mediaType == ArrangementMediaType.none) return false;

    uploadingBoardBackground = true;
    errorMessage = null;
    notifyListeners();

    try {
      board = b.copyWith(
        pictures: [
          for (final p in b.pictures)
            if (p.arrangement.id == arrangementId)
              p.copyWith(
                arrangement: p.arrangement.copyWith(
                  mediaType: mediaType,
                  mediaFile: mediaFile,
                  pictureRoute:
                      pictureRoute.isNotEmpty ? pictureRoute : mediaFile,
                  pictureBytes: mediaType == ArrangementMediaType.image &&
                          pictureBytes != null &&
                          pictureBytes.isNotEmpty
                      ? Uint8List.fromList(pictureBytes)
                      : null,
                  clearPictureBytes: mediaType != ArrangementMediaType.image,
                ),
              )
            else
              p,
        ],
      );
      if (arrangementId != 0) _pendingMediaIds.add(arrangementId);
      layoutDirty = true;
      uploadingBoardBackground = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Apply media failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      uploadingBoardBackground = false;
      notifyListeners();
      return false;
    }
  }

  /// Stages clearing media on a photo block — persisted on Save.
  Future<bool> clearBlockMedia(int arrangementId) async {
    final b = board;
    if (b == null || !layoutEditing || arrangementId == 0) {
      return false;
    }

    uploadingBoardBackground = true;
    errorMessage = null;
    notifyListeners();

    try {
      board = b.copyWith(
        pictures: [
          for (final p in b.pictures)
            if (p.arrangement.id == arrangementId)
              p.copyWith(
                arrangement: p.arrangement.copyWith(
                  mediaType: ArrangementMediaType.none,
                  mediaFile: '',
                  pictureRoute: '',
                  clearPictureBytes: true,
                ),
              )
            else
              p,
        ],
      );
      _pendingMediaIds.add(arrangementId);
      layoutDirty = true;
      uploadingBoardBackground = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Clear block media failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      uploadingBoardBackground = false;
      notifyListeners();
      return false;
    }
  }

  /// Persists pending edit-session changes (layout, media, deletes, prefs).
  ///
  /// Retries the MySQL transaction a few times on failure (safe: each attempt
  /// rolls back fully before the next try). Draft state stays in memory.
  Future<bool> saveLayoutEdits() async {
    final b = board;
    if (b == null) {
      layoutEditing = false;
      notifyListeners();
      return true;
    }
    if (!layoutDirty) {
      layoutEditing = false;
      notifyListeners();
      if (phase == BillboardPhase.ready) _scheduleRefresh();
      return true;
    }

    savingLayout = true;
    errorMessage = null;
    notifyListeners();

    const maxAttempts = 3;
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final name = computerName.trim();
        await _persistLayoutTransaction(b, name);

        // Prefs are local — outside MySQL txn
        await _connectionRepo.saveCustomerDisplay(customerDisplay);
        _customerDisplaySaved = customerDisplay;

        _clearSessionPending();
        layoutDirty = false;
        layoutEditing = false;
        savingLayout = false;
        notifyListeners();

        await reloadSilent(full: true);
        _scheduleRefresh();
        return true;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (kDebugMode) {
          debugPrint('Save layout attempt $attempt/$maxAttempts failed: $e\n$st');
        }
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }

    if (kDebugMode) {
      debugPrint('Save layout failed after $maxAttempts attempts: $lastError\n$lastStack');
    }
    errorMessage = AppFailure.message(lastError ?? 'Save failed');
    savingLayout = false;
    notifyListeners();
    return false;
  }

  Future<void> _persistLayoutTransaction(BillboardBoard b, String name) async {
    await _billboardRepo.runInTransaction(() async {
      // 1) Pending deletes (real rows only)
      for (final id in List<int>.of(_sessionDeletedIds)) {
        if (id > 0) await _billboardRepo.deleteArrangementById(id);
      }

      // 2) Board background
      switch (_pendingBoardBg) {
        case _PendingBoardBg.image:
          final bytes = _pendingBoardBgImageBytes;
          if (bytes != null && bytes.isNotEmpty) {
            await _billboardRepo.upsertBoardBackgroundImage(
              compName: name,
              bytes: bytes,
              mainBackColor: b.mainBackColor,
            );
          }
        case _PendingBoardBg.video:
          final file = _pendingBoardBgVideoFile?.trim() ?? '';
          if (file.isNotEmpty) {
            await _billboardRepo.upsertBoardBackgroundVideo(
              compName: name,
              mediaFile: file,
              pictureRoute: _pendingBoardBgVideoRoute ?? file,
              mainBackColor: b.mainBackColor,
            );
          }
        case _PendingBoardBg.clear:
          await _billboardRepo.clearBoardBackgroundImage(name);
        case _PendingBoardBg.none:
          break;
      }

      // 3) INSERT new blocks (temp negative IDs) then UPDATE style/layout
      final idMap = <int, int>{};

      for (final s in b.sections) {
        final a = s.arrangement;
        if (a.id >= 0) continue;
        final newId = await _billboardRepo.insertMenuArrangement(
          compName: name,
          classId: a.classId,
          screenName: a.screenName,
          xDistance: a.xDistance,
          yDistance: a.yDistance,
          maxWidth: a.maxWidth,
          mainBackColor: b.mainBackColor,
          displayOrder: a.displayOrder,
        );
        idMap[a.id] = newId;
        await _billboardRepo.updateArrangementLayout(
          id: newId,
          compName: name,
          arrangement: a.copyWith(id: newId, mainBackColor: b.mainBackColor),
        );
      }

      for (final p in b.pictures) {
        final a = p.arrangement;
        if (a.id >= 0 || a.isBoardBackground) continue;
        final newId = await _billboardRepo.insertPhotoArrangement(
          compName: name,
          screenName: a.screenName,
          xDistance: a.xDistance,
          yDistance: a.yDistance,
          maxWidth: a.maxWidth,
          mainBackColor: b.mainBackColor,
          displayOrder: a.displayOrder,
        );
        idMap[a.id] = newId;
        await _billboardRepo.updateArrangementLayout(
          id: newId,
          compName: name,
          arrangement: a.copyWith(id: newId, mainBackColor: b.mainBackColor),
        );
      }

      // 4) Layout + style for existing blocks
      for (final s in b.sections) {
        final id = s.arrangement.id;
        if (id <= 0) continue;
        if (_sessionDeletedIds.contains(id)) continue;
        await _billboardRepo.updateArrangementLayout(
          id: id,
          compName: name,
          arrangement: s.arrangement.copyWith(mainBackColor: b.mainBackColor),
        );
      }
      for (final p in b.pictures) {
        final id = p.arrangement.id;
        if (id <= 0) continue;
        if (_sessionDeletedIds.contains(id)) continue;
        if (p.arrangement.isBoardBackground) continue;
        await _billboardRepo.updateArrangementLayout(
          id: id,
          compName: name,
          arrangement: p.arrangement.copyWith(mainBackColor: b.mainBackColor),
        );
      }

      // 5) Media blobs / paths (map temp → real IDs)
      for (final oldId in List<int>.of(_pendingMediaIds)) {
        final id = idMap[oldId] ?? oldId;
        if (id <= 0 || _sessionDeletedIds.contains(oldId)) continue;
        PictureBlock? pic;
        for (final p in b.pictures) {
          if (p.arrangement.id == oldId) {
            pic = p;
            break;
          }
        }
        if (pic == null) continue;
        final a = pic.arrangement;
        await _billboardRepo.updateArrangementMedia(
          id: id,
          compName: name,
          mediaType: a.mediaType,
          mediaFile: a.mediaFile,
          pictureRoute: a.pictureRoute,
          pictureBytes: a.mediaType == ArrangementMediaType.image
              ? (a.pictureBytes ?? const <int>[])
              : (a.mediaType == ArrangementMediaType.none ||
                      a.mediaType == ArrangementMediaType.video
                  ? const <int>[]
                  : null),
        );
      }
    });
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (layoutEditing) return;
    _pollTick = 0;
    // Menu prices/specials every 5s; full board (layout + pics) less often.
    final interval = refreshSeconds.clamp(5, 3600);
    _refreshTimer = Timer.periodic(
      Duration(seconds: interval),
      (_) {
        if (layoutEditing || layoutDirty || savingLayout) return;
        _pollTick++;
        // Every ~60s worth of ticks, do a full reload; otherwise items only.
        final ticksForFull = (60 / interval).ceil().clamp(1, 120);
        reloadSilent(full: _pollTick % ticksForFull == 0);
      },
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
