import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:camaleon_billboard/core/db/qr_image_scanner.dart';
import 'package:camaleon_billboard/core/theme/camaleon_theme.dart';
import 'package:camaleon_billboard/domain/entities/db_connection_config.dart';
import 'package:camaleon_billboard/presentation/billboard_controller.dart';
import 'package:camaleon_billboard/presentation/theme_controller.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _password;
  late final TextEditingController _db;
  late final TextEditingController _comp;
  late final TextEditingController _refresh;
  final ImagePicker _picker = ImagePicker();
  bool _alpha = false;
  bool _scanningQr = false;
  bool _showManual = false;
  String? _status;
  String? _templateComp;

  bool get _cameraSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  bool get _desktopSharedFile {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  @override
  void initState() {
    super.initState();
    final c = context.read<BillboardController>();
    _host = TextEditingController(text: c.connection.host);
    _port = TextEditingController(text: '${c.connection.port}');
    _user = TextEditingController(text: c.connection.user);
    _password = TextEditingController(text: c.connection.password);
    _db = TextEditingController(text: c.connection.database);
    _comp = TextEditingController(text: _deviceLabel(c));
    _refresh = TextEditingController(text: '${c.refreshSeconds}');
    _alpha = c.sortAlphabetical;
    _templateComp = c.templateCompName;
  }

  /// On Android, Device is always the device name.
  String _deviceLabel(BillboardController c) {
    if (!kIsWeb &&
        Platform.isAndroid &&
        c.detectedComputerName.trim().isNotEmpty) {
      return c.detectedComputerName.trim();
    }
    final saved = c.computerName.trim();
    if (saved.isNotEmpty) return saved;
    return c.detectedComputerName.trim();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    _db.dispose();
    _comp.dispose();
    _refresh.dispose();
    super.dispose();
  }

  DbConnectionConfig _readConfig() {
    return DbConnectionConfig(
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 3306,
      user: _user.text.trim(),
      password: _password.text,
      database: _db.text.trim(),
    );
  }

  void _syncFromController(BillboardController c) {
    _host.text = c.connection.host;
    _port.text = '${c.connection.port}';
    _user.text = c.connection.user;
    _password.text = c.connection.password;
    _db.text = c.connection.database;
    if (!kIsWeb && Platform.isAndroid) {
      _comp.text = _deviceLabel(c);
    } else if (_comp.text.trim().isEmpty) {
      _comp.text = c.computerName;
    }
  }

  String _summaryLine() {
    final cfg = _readConfig();
    if (!cfg.isComplete) return 'No MySQL yet';
    return '${cfg.host}:${cfg.port} · ${cfg.database}';
  }

  Future<void> _searchDatabases() async {
    final c = context.read<BillboardController>();
    setState(() => _status = 'Searching for databases…');
    final result = await c.searchDatabases(config: _readConfig());
    if (!mounted) return;

    if (result.error != null || result.databases.isEmpty) {
      setState(() {
        _status = result.error ??
            c.errorMessage ??
            'No databases found.';
      });
      return;
    }

    _syncFromController(c);
    if (_db.text.trim().isEmpty ||
        !result.databases.contains(_db.text.trim())) {
      _db.text = result.databases.first;
    }
    setState(() {
      _status =
          '${result.databases.length} databases on ${result.host}. Pick one and connect.';
    });
  }

  Future<void> _autoConnect() async {
    final c = context.read<BillboardController>();
    final form = _readConfig();
    final host = form.host.trim();
    final deviceName = _deviceLabel(c);
    if (deviceName.isNotEmpty) {
      _comp.text = deviceName;
    }
    setState(() {
      _status = host.isNotEmpty
          ? 'Connecting to $host…'
          : 'Searching for MySQL on the network…';
    });
    await c.savePreferences(
      alphabetical: _alpha,
      refresh: int.tryParse(_refresh.text.trim()) ?? 5,
    );
    c.templateCompName = _templateComp;

    var result = await c.autoConnect(
      config: form,
      compName: deviceName.isNotEmpty ? deviceName : _comp.text,
      createArrangementIfMissing: true,
      // With a server filled in, only that host — never scan the LAN.
      scanLan: host.isEmpty,
    );
    if (!mounted) return;

    result = await _resolveAutoConnectFollowUps(c, result);
    if (!mounted) return;

    // Never overwrite the form with a stale saved connection after a
    // partial result (needs DB / password). Only sync on full success.
    if (result.ok) {
      _syncFromController(c);
    }

    if (!result.ok) {
      setState(() {
        _showManual = true;
        _status = c.autoConnectStatus ??
            result.message ??
            c.errorMessage ??
            'Auto-connect failed.';
      });
    }
  }

  Future<AutoConnectResult> _resolveAutoConnectFollowUps(
    BillboardController c,
    AutoConnectResult result,
  ) async {
    var current = result;

    if (current.outcome == AutoConnectOutcome.needsPassword) {
      final pass = await _askMysqlPassword(current.hosts);
      if (!mounted || pass == null) {
        return AutoConnectResult(
          outcome: AutoConnectOutcome.failed,
          hosts: current.hosts,
          message: current.message ??
              'MySQL found; enter the password to continue.',
        );
      }
      _password.text = pass;
      final retryHost = _readConfig().host.trim();
      setState(() => _status = 'Retrying with the password…');
      current = await c.autoConnect(
        config: _readConfig(),
        compName: _comp.text,
        createArrangementIfMissing: true,
        scanLan: retryHost.isEmpty,
        passwordOverride: pass,
        hostsHint: current.hosts.isNotEmpty
            ? current.hosts
            : (retryHost.isNotEmpty
                ? [retryHost]
                : c.lastDiscoveredHosts),
      );
      if (!mounted) return current;
      if (current.ok) {
        _syncFromController(c);
      }
    }

    if (current.outcome == AutoConnectOutcome.needsDatabase) {
      final dbs = current.databases;
      final pending = current.pendingConfig;
      if (pending == null || dbs.isEmpty) {
        return AutoConnectResult(
          outcome: AutoConnectOutcome.failed,
          message: 'No databases available to choose.',
        );
      }
      // Keep the host the user typed if present; only fill blanks from pending.
      setState(() {
        _showManual = true;
        if (_host.text.trim().isEmpty) {
          _host.text = pending.host;
        }
        if (_port.text.trim().isEmpty) {
          _port.text = '${pending.port}';
        }
        if (_user.text.trim().isEmpty) {
          _user.text = pending.user;
        }
        if (_password.text.isEmpty) {
          _password.text = pending.password;
        }
        if (_db.text.trim().isEmpty || !dbs.contains(_db.text.trim())) {
          _db.text = dbs.first;
        }
        _status = 'Pick a database and tap Connect.';
      });
      return AutoConnectResult(
        outcome: AutoConnectOutcome.failed,
        hosts: current.hosts,
        databases: dbs,
        pendingConfig: pending,
        message: 'Pick a database and tap Connect.',
      );
    }

    return current;
  }

  Future<String?> _askMysqlPassword(List<String> hosts) async {
    final controller = TextEditingController();
    final hostLine = hosts.isEmpty
        ? 'a MySQL server'
        : (hosts.length == 1
            ? hosts.first
            : '${hosts.length} servers (${hosts.take(3).join(', ')}${hosts.length > 3 ? '…' : ''})');
    final pass = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('MySQL password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Found $hostLine.\n'
                'Default password "antonio" did not work.',
                style: const TextStyle(fontSize: 14, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return pass;
  }

  Future<void> _applyQrBytes(Uint8List bytes) async {
    final payload = QrImageScanner.decodePayload(bytes);
    if (payload == null) {
      setState(() => _status = 'No QR code found in the image.');
      return;
    }
    final c = context.read<BillboardController>();
    final ok = c.applyQrPayload(payload);
    if (!ok) {
      setState(() => _status = 'This QR is not a Camaleon connection code.');
      return;
    }
    _syncFromController(c);
    setState(() => _status = 'QR ready · ${_summaryLine()}');
    await _autoConnect();
  }

  Future<void> _scanQrFromGallery() async {
    if (_scanningQr) return;
    setState(() {
      _scanningQr = true;
      _status = null;
    });
    try {
      XFile? file;
      try {
        file = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 95,
        );
      } on Object {
        final files = await FilePicker.pickFiles(type: FileType.image);
        if (files.isEmpty) return;
        await _applyQrBytes(await files.first.readAsBytes());
        return;
      }
      if (file == null) return;
      await _applyQrBytes(await file.readAsBytes());
    } on Object catch (e) {
      setState(() => _status = 'Could not load image: $e');
    } finally {
      if (mounted) setState(() => _scanningQr = false);
    }
  }

  Future<void> _scanQrFromCamera() async {
    if (_scanningQr) return;
    setState(() {
      _scanningQr = true;
      _status = null;
    });
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 95,
      );
      if (file == null) return;
      await _applyQrBytes(await file.readAsBytes());
    } on Object catch (e) {
      setState(() => _status = 'Could not open camera: $e');
    } finally {
      if (mounted) setState(() => _scanningQr = false);
    }
  }

  Future<void> _importShared() async {
    final c = context.read<BillboardController>();
    final ok = await c.importSharedConnection();
    if (!mounted) return;
    if (!ok) {
      setState(() => _status = 'No shared Camaleon connection file.');
      return;
    }
    _syncFromController(c);
    setState(() => _status = 'File ready · ${_summaryLine()}');
    await _autoConnect();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BillboardController>();
    final themeCtrl = context.watch<ThemeController>();
    final scheme = Theme.of(context).colorScheme;
    final isDark = themeCtrl.isDark(context);
    final busy = c.autoConnecting || c.searchingDatabases || _scanningQr;
    final h = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final compact = h < 780 || keyboard > 0;
    final ready = _readConfig().isComplete || c.connection.isComplete;
    final muted = isDark ? CamaleonColors.nightMuted : CamaleonColors.slate;
    final ink = isDark ? CamaleonColors.nightText : CamaleonColors.ink;
    final surface = isDark ? CamaleonColors.nightSurface : Colors.white;
    final border = isDark ? CamaleonColors.nightLine : CamaleonColors.line;
    final bgTop = isDark ? CamaleonColors.night : CamaleonColors.mist;
    final bgBottom = isDark ? const Color(0xFF070B12) : Colors.white;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgTop, bgBottom],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: isDark ? 'Light mode' : 'Dark mode',
                  onPressed: () => themeCtrl.toggle(context),
                  icon: Icon(
                    isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    color: muted,
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(22, compact ? 8 : 16, 22, 12),
                    child: CustomScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _showManual
                              ? _manualView(
                                  c: c,
                                  busy: busy,
                                  ink: ink,
                                  muted: muted,
                                  scheme: scheme,
                                )
                              : _homeView(
                                  c: c,
                                  busy: busy,
                                  compact: compact,
                                  keyboardOpen: keyboard > 0,
                                  ready: ready,
                                  ink: ink,
                                  muted: muted,
                                  scheme: scheme,
                                  isDark: isDark,
                                  border: border,
                                  surface: surface,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeView({
    required BillboardController c,
    required bool busy,
    required bool compact,
    required bool keyboardOpen,
    required bool ready,
    required Color ink,
    required Color muted,
    required ColorScheme scheme,
    required bool isDark,
    required Color border,
    required Color surface,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!keyboardOpen) ...[
          SizedBox(height: compact ? 8 : 12),
          Center(
            child: Image.asset(
              CamaleonAssets.logo,
              height: compact ? 44 : 56,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Billboard',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CamaleonColors.green,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 2.4,
            ),
          ),
          SizedBox(height: compact ? 6 : 10),
          Text(
            ready
                ? 'One tap to connect and open the menu'
                : 'First time: scan the POS QR code',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 14),
          ),
          SizedBox(height: compact ? 16 : 24),
        ] else
          const SizedBox(height: 8),
        if (ready) ...[
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: busy ? null : _autoConnect,
              icon: c.autoConnecting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.bolt_rounded),
              label: Text(
                c.autoConnecting ? 'Connecting…' : 'Connect',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (!keyboardOpen) ...[
            const SizedBox(height: 8),
            Text(
              'Tests the connection, creates the layout if missing, and opens the billboard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12, height: 1.3),
            ),
            SizedBox(height: compact ? 14 : 20),
            Row(
              children: [
                Expanded(child: Divider(color: border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or change connection',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
                Expanded(child: Divider(color: border)),
              ],
            ),
            SizedBox(height: compact ? 12 : 14),
            _qrRow(busy),
          ],
        ] else ...[
          if (!keyboardOpen) ...[
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : (_cameraSupported
                        ? _scanQrFromCamera
                        : _scanQrFromGallery),
                icon: _scanningQr
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : Icon(
                        _cameraSupported
                            ? Icons.qr_code_scanner_rounded
                            : Icons.image_outlined,
                      ),
                label: Text(
                  _scanningQr
                      ? 'Scanning…'
                      : (_cameraSupported
                          ? 'Scan POS QR'
                          : 'Load QR image'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The QR fills in the connection and connects instantly.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12, height: 1.3),
            ),
            SizedBox(height: compact ? 14 : 20),
            Row(
              children: [
                if (_cameraSupported)
                  Expanded(
                    child: _secondaryBtn(
                      busy: busy,
                      icon: Icons.image_outlined,
                      label: 'Use image',
                      onPressed: _scanQrFromGallery,
                    ),
                  ),
                if (_cameraSupported && _desktopSharedFile)
                  const SizedBox(width: 8),
                if (_desktopSharedFile)
                  Expanded(
                    child: _secondaryBtn(
                      busy: busy,
                      icon: Icons.folder_open_outlined,
                      label: 'File',
                      onPressed: _importShared,
                    ),
                  ),
                if (!_cameraSupported && !_desktopSharedFile)
                  Expanded(
                    child: _secondaryBtn(
                      busy: busy,
                      icon: Icons.image_outlined,
                      label: 'Load image',
                      onPressed: _scanQrFromGallery,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : _autoConnect,
              icon: c.autoConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt_rounded, size: 18),
              label: Text(
                c.autoConnecting ? 'Searching…' : 'Auto-connect',
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
          ],
        ],
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ready
                  ? CamaleonColors.green.withValues(alpha: 0.35)
                  : border,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: CamaleonColors.ink.withValues(alpha: 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!keyboardOpen) ...[
                Row(
                  children: [
                    Icon(
                      ready
                          ? Icons.check_circle_rounded
                          : Icons.qr_code_2_rounded,
                      size: 18,
                      color: ready ? CamaleonColors.green : muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ready
                            ? _summaryLine()
                            : 'No connection · scan the POS QR',
                        style: TextStyle(
                          color: ready ? CamaleonColors.green : muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _comp,
                readOnly: true,
                enableInteractiveSelection: false,
                style: TextStyle(color: muted, fontSize: 14),
                decoration: _dec('Device', Icons.computer, muted),
              ),
            ],
          ),
        ),
        if (_status != null ||
            c.autoConnectStatus != null ||
            c.errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            c.autoConnectStatus ?? _status ?? c.errorMessage!,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _isPositive(
                c.autoConnectStatus ?? _status ?? c.errorMessage!,
              )
                  ? CamaleonColors.green
                  : CamaleonColors.orange,
              fontSize: 13,
            ),
          ),
        ],
        const Spacer(),
        if (!keyboardOpen)
          TextButton(
            onPressed:
                busy ? null : () => setState(() => _showManual = true),
            child: Text('Manual settings', style: TextStyle(color: muted)),
          ),
      ],
    );
  }

  Widget _manualView({
    required BillboardController c,
    required bool busy,
    required Color ink,
    required Color muted,
    required ColorScheme scheme,
  }) {
    final androidName = _deviceLabel(c);
    if ((!kIsWeb && Platform.isAndroid) || _comp.text.trim().isEmpty) {
      if (androidName.isNotEmpty) {
        _comp.text = androidName;
      }
    }
    final status = _manualStatus(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed:
                  busy ? null : () => setState(() => _showManual = false),
              icon: Icon(Icons.arrow_back_rounded, color: muted),
            ),
            Expanded(
              child: Text(
                'MySQL connection',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _comp,
          readOnly: true,
          enableInteractiveSelection: false,
          style: TextStyle(color: muted, fontSize: 14),
          decoration: _dec('Device', Icons.computer, muted),
        ),
        const SizedBox(height: 8),
        _field(_host, 'Server', Icons.dns_outlined, muted, ink),
        Row(
          children: [
            Expanded(
              child: _field(
                _port,
                'Port',
                Icons.numbers,
                muted,
                ink,
                keyboard: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                _user,
                'User',
                Icons.person_outline,
                muted,
                ink,
              ),
            ),
          ],
        ),
        _field(
          _password,
          'Password',
          Icons.lock_outline,
          muted,
          ink,
          obscure: true,
        ),
        _databaseField(c, busy, ink, muted),
        if (c.knownCompNames.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InputDecorator(
              decoration: _dec(
                'Copy layout from',
                Icons.copy_all_outlined,
                muted,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  isDense: true,
                  value: _templateComp != null &&
                          c.knownCompNames.contains(_templateComp)
                      ? _templateComp
                      : null,
                  style: TextStyle(color: ink, fontSize: 14),
                  hint: Text('New Screen 1', style: TextStyle(color: muted)),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('New Screen 1'),
                    ),
                    for (final name in c.knownCompNames)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (v) => setState(() => _templateComp = v),
                ),
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _field(
                _refresh,
                'Refresh (s)',
                Icons.timer_outlined,
                muted,
                ink,
                keyboard: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: CamaleonColors.green,
                title: Text(
                  'A–Z sort',
                  style: TextStyle(color: ink, fontSize: 13),
                ),
                value: _alpha,
                onChanged: busy ? null : (v) => setState(() => _alpha = v),
              ),
            ),
          ],
        ),
        if (status != null) ...[
          Text(
            status,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _isPositive(status)
                  ? CamaleonColors.green
                  : CamaleonColors.orange,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _searchDatabases,
            icon: c.searchingDatabases
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.search_rounded),
            label: Text(
              c.searchingDatabases ? 'Searching…' : 'Search',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: busy ? null : _autoConnect,
            icon: c.autoConnecting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: scheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.link_rounded),
            label: Text(
              c.autoConnecting ? 'Connecting…' : 'Connect',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  String? _manualStatus(BillboardController c) {
    // Only surface errors / in-progress — not success echoes.
    if (c.searchingDatabases || c.autoConnecting) {
      return c.autoConnectStatus ?? _status;
    }
    final raw = _status ?? c.errorMessage;
    if (raw == null) return null;
    if (raw.contains('Missing MySQL') ||
        raw.contains('Faltan datos de MySQL')) {
      return 'Fill in server, user, and database.';
    }
    final lower = raw.toLowerCase();
    // Keep post-search guidance visible; hide other database-list echoes.
    if (lower.contains('pick one') || lower.contains('elige una')) return raw;
    if (lower.contains('databases on ') ||
        lower.contains('bases en ') ||
        lower.contains('base elegida')) {
      return null;
    }
    return raw;
  }

  Widget _qrRow(bool busy) {
    return Row(
      children: [
        if (_cameraSupported)
          Expanded(
            child: _secondaryBtn(
              busy: busy,
              icon: Icons.qr_code_scanner_rounded,
              label: 'Scan QR',
              onPressed: _scanQrFromCamera,
            ),
          ),
        if (_cameraSupported) const SizedBox(width: 8),
        Expanded(
          child: _secondaryBtn(
            busy: busy,
            icon: Icons.image_outlined,
            label: 'Image',
            onPressed: _scanQrFromGallery,
          ),
        ),
        if (_desktopSharedFile) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _secondaryBtn(
              busy: busy,
              icon: Icons.folder_open_outlined,
              label: 'File',
              onPressed: _importShared,
            ),
          ),
        ],
      ],
    );
  }

  Widget _secondaryBtn({
    required bool busy,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      icon: Icon(icon, size: 18, color: CamaleonColors.green),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  bool _isPositive(String msg) {
    final m = msg.toLowerCase();
    return m.contains('ok') ||
        m.contains('ready') ||
        m.contains('listo') ||
        m.contains('imported') ||
        m.contains('importado') ||
        m.contains('searching') ||
        m.contains('buscando') ||
        m.contains('scanning') ||
        m.contains('escaneando') ||
        m.contains('trying') ||
        m.contains('probando') ||
        m.contains('connecting') ||
        m.contains('conectando') ||
        m.contains('found') ||
        m.contains('encontrados') ||
        m.contains('databases on') ||
        m.contains('bases en') ||
        m.contains('pick one') ||
        m.contains('elige una');
  }

  Widget _databaseField(
    BillboardController c,
    bool busy,
    Color ink,
    Color muted,
  ) {
    final dbs = c.availableDatabases;
    if (dbs.isEmpty) {
      return _field(_db, 'Database', Icons.storage_outlined, muted, ink);
    }

    final current = _db.text.trim();
    final value = dbs.contains(current) ? current : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: _dec('Database', Icons.storage_outlined, muted),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            isDense: true,
            value: value,
            hint: Text(
              'Choose from ${dbs.length}',
              style: TextStyle(color: muted, fontSize: 14),
            ),
            style: TextStyle(color: ink, fontSize: 14),
            items: [
              for (final name in dbs)
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _db.text = v);
                  },
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon,
    Color muted,
    Color ink, {
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        style: TextStyle(color: ink, fontSize: 14),
        decoration: _dec(label, icon, muted),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon, Color muted) {
    return InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: TextStyle(color: muted, fontSize: 13),
      prefixIcon: Icon(icon, color: muted, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}
