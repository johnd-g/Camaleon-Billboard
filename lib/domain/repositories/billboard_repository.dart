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
}
