import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/domain/entities/db_connection_config.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';

abstract class BillboardRepository {
  Future<void> connect(DbConnectionConfig config);
  Future<void> disconnect();
  Future<bool> testConnection(DbConnectionConfig config);

  /// Classic `loadorderscuentas` — menu blocks (`usepic=0`).
  Future<List<ArrangementBlock>> loadMenuArrangements(String compName);

  /// Classic `loadpicturesand` — picture blocks (`usepic=1`).
  Future<List<ArrangementBlock>> loadPictureArrangements(String compName);

  /// Classic `fillclassview` — items for one class / range.
  Future<MenuSection> fillClassView(
    ArrangementBlock block, {
    required bool sortAlphabetical,
  });

  /// Full board load (menus + pictures with blobs).
  Future<BillboardBoard> loadBoard({
    required String compName,
    required bool sortAlphabetical,
  });

  /// Refresh item names/prices/descriptions only — keeps picture blobs in memory.
  Future<BillboardBoard> refreshMenuItems(
    BillboardBoard current, {
    required bool sortAlphabetical,
  });

  /// Distinct `comp_name` values already configured in POS Billboard setup.
  Future<List<String>> listConfiguredComputerNames();

  /// POS `it_tregister.Regi_Name` values (pickable device labels).
  Future<List<String>> listRegisterNames();

  /// True when this device already has at least one `bb_arrangement` row.
  Future<bool> hasArrangementFor(String compName);

  /// Ensures [compName] has `bb_arrangement` rows.
  ///
  /// - No [templateCompName]: inserts a starter screen only if none exist.
  /// - With [templateCompName]: replaces this device's rows with a full copy
  ///   of the template's layout (all matching `bb_arrangement` rows).
  Future<void> ensureArrangementForComputer({
    required String compName,
    String? templateCompName,
  });

  /// Persists layout + style fields for one arrangement row.
  Future<void> updateArrangementLayout({
    required int id,
    required String compName,
    required ArrangementBlock arrangement,
  });

  /// Stores [bytes] as the sole board-background photo (`bb_pic` + `bb_background=1`).
  ///
  /// Creates or updates a dedicated `usepic=1` row named "Board background".
  Future<void> upsertBoardBackgroundImage({
    required String compName,
    required List<int> bytes,
    int mainBackColor = 0,
  });

  /// Stores a video path as the sole board background (`media_type=VIDEO`).
  Future<void> upsertBoardBackgroundVideo({
    required String compName,
    required String mediaFile,
    String pictureRoute = '',
    int mainBackColor = 0,
    bool videoLoop = true,
    bool videoMuted = true,
  });

  /// Clears `bb_background` and removes the dedicated background row if present.
  Future<void> clearBoardBackgroundImage(String compName);

  /// Updates media fields for one picture row.
  ///
  /// When [pictureBytes] is non-null, writes `bb_pic`. Pass an empty list to
  /// clear the blob. Omit (null) to leave `bb_pic` unchanged.
  Future<void> updateArrangementMedia({
    required int id,
    required String compName,
    required ArrangementMediaType mediaType,
    required String mediaFile,
    String pictureRoute = '',
    List<int>? pictureBytes,
  });

  /// POS `it_titemclass` rows for picking a new menu section.
  Future<List<MenuClassOption>> listMenuClasses();

  /// Inserts a new menu block (`usepic=0`) and returns its `ID`.
  Future<int> insertMenuArrangement({
    required String compName,
    required int classId,
    required String screenName,
    int xDistance = 40,
    int yDistance = 40,
    int maxWidth = 600,
    int mainBackColor = 0,
    int displayOrder = 0,
  });

  /// Inserts a new photo/media block (`usepic=1`) and returns its `ID`.
  Future<int> insertPhotoArrangement({
    required String compName,
    String screenName = 'Photo',
    int xDistance = 40,
    int yDistance = 40,
    int maxWidth = 400,
    int mainBackColor = 0,
    int displayOrder = 0,
  });

  /// Deletes one `bb_arrangement` row for this device.
  /// Returns affected row count.
  Future<int> deleteArrangement({
    required int id,
    required String compName,
  });

  /// Force-delete by primary key only (ignores comp_name).
  Future<int> deleteArrangementById(int id);

  /// Loads one arrangement row by primary key (any `usepic`).
  Future<ArrangementBlock?> loadArrangementById({
    required int id,
    required String compName,
  });

  /// Runs [action] in a MySQL transaction (COMMIT / ROLLBACK).
  Future<T> runInTransaction<T>(Future<T> Function() action);

  /// Open tickets from POS (`it_tcuenta` + `it_torder`) for Customer display.
  Future<List<CustomerOrderTicket>> loadOpenCustomerOrders({int limit = 10});
}
