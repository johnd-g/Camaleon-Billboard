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
    int? borderWidth,
    String? borderColor,
    bool? videoLoop,
    bool? videoMuted,
  }) {
    final b = board;
    if (b == null || !layoutEditing) return;

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
          final name = computerName.trim();
          if (name.isNotEmpty) {
            unawaited(
              _billboardRepo.updateArrangementMedia(
                id: arrangementId,
                compName: name,
                mediaType: ArrangementMediaType.video,
                mediaFile: next.mediaFile,
                pictureRoute: next.pictureRoute,
                pictureBytes: const <int>[],
              ),
            );
          }
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
      }
      if (mediaFile != null) {
        next = next.copyWith(
          mediaFile: mediaFile,
          // Live preview uses pictureRoute; keep it in sync for IMAGE paths.
          pictureRoute: mediaFile.isNotEmpty ? mediaFile : next.pictureRoute,
        );
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
        next = next.copyWith(displaySeconds: displaySeconds.clamp(1, 3600));
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

  /// Picks [bytes] into DB as board background and refreshes picture blocks in memory.
  Future<bool> setBoardBackgroundImage(List<int> bytes) async {
    final b = board;
    final name = computerName.trim();
    if (b == null || name.isEmpty || bytes.isEmpty) return false;
    if (!layoutEditing) return false;

    uploadingBoardBackground = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _billboardRepo.upsertBoardBackgroundImage(
        compName: name,
        bytes: bytes,
        mainBackColor: b.mainBackColor,
      );
      final pics = await _billboardRepo.loadPictureArrangements(name);
      board = b.copyWith(
        pictures: [
          for (final a in pics)
            PictureBlock(
              arrangement: a.copyWith(mainBackColor: b.mainBackColor),
            ),
        ],
      );
      uploadingBoardBackground = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Board background upload failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      uploadingBoardBackground = false;
      notifyListeners();
      return false;
    }
  }

  /// Sets a looping/muted video path as the full-board background.
  Future<bool> setBoardBackgroundVideo({
    required String mediaFile,
    String pictureRoute = '',
    bool videoLoop = true,
    bool videoMuted = true,
  }) async {
    final b = board;
    final name = computerName.trim();
    if (b == null || name.isEmpty || mediaFile.trim().isEmpty) return false;
    if (!layoutEditing) return false;

    uploadingBoardBackground = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _billboardRepo.upsertBoardBackgroundVideo(
        compName: name,
        mediaFile: mediaFile,
        pictureRoute: pictureRoute,
        mainBackColor: b.mainBackColor,
        videoLoop: videoLoop,
        videoMuted: videoMuted,
      );
      final pics = await _billboardRepo.loadPictureArrangements(name);
      board = b.copyWith(
        pictures: [
          for (final a in pics)
            PictureBlock(
              arrangement: a.copyWith(mainBackColor: b.mainBackColor),
            ),
        ],
      );
      uploadingBoardBackground = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Board background video failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      uploadingBoardBackground = false;
      notifyListeners();
      return false;
    }
  }

  /// Removes the dedicated board-background image from DB (and unsets flags).
  Future<bool> clearBoardBackgroundImage() async {
    final b = board;
    final name = computerName.trim();
    if (b == null || name.isEmpty || !layoutEditing) return false;

    uploadingBoardBackground = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _billboardRepo.clearBoardBackgroundImage(name);
      final pics = await _billboardRepo.loadPictureArrangements(name);
      board = b.copyWith(
        pictures: [
          for (final a in pics)
            PictureBlock(
              arrangement: a.copyWith(mainBackColor: b.mainBackColor),
            ),
        ],
      );
      uploadingBoardBackground = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Clear board background failed: $e\n$st');
      errorMessage = AppFailure.message(e);
      uploadingBoardBackground = false;
      notifyListeners();
      return false;
    }
  }

  /// Applies a file picked from Explorer / Android picker to a photo block.
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
    final name = computerName.trim();
    if (b == null || name.isEmpty || !layoutEditing) return false;
    if (mediaType == ArrangementMediaType.none) return false;

    uploadingBoardBackground = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _billboardRepo.updateArrangementMedia(
        id: arrangementId,
        compName: name,
        mediaType: mediaType,
        mediaFile: mediaFile,
        pictureRoute: pictureRoute.isNotEmpty ? pictureRoute : mediaFile,
        // IMAGE: write blob. VIDEO: clear old bb_pic so image doesn't stick.
        pictureBytes: mediaType == ArrangementMediaType.image &&
                pictureBytes != null &&
                pictureBytes.isNotEmpty
            ? pictureBytes
            : (mediaType == ArrangementMediaType.video
                ? const <int>[]
                : null),
      );

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

  /// Writes current section/picture positions + styles to `bb_arrangement`.
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
        await _billboardRepo.updateArrangementLayout(
          id: s.arrangement.id,
          compName: name,
          arrangement: s.arrangement.copyWith(mainBackColor: b.mainBackColor),
        );
      }
      for (final p in b.pictures) {
        await _billboardRepo.updateArrangementLayout(
          id: p.arrangement.id,
          compName: name,
          arrangement: p.arrangement.copyWith(mainBackColor: b.mainBackColor),
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
      errorMessage = AppFailure.message(e);
      savingLayout = false;
      notifyListeners();
      return false;
    }
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
