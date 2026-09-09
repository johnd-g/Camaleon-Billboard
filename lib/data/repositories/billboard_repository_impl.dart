import 'package:camaleon_billboard/core/db/mysql_client.dart';
import 'package:camaleon_billboard/core/utils/qb_color.dart';
import 'package:camaleon_billboard/core/utils/type_data.dart';
import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/domain/entities/db_connection_config.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';
import 'package:camaleon_billboard/domain/repositories/billboard_repository.dart';

class BillboardRepositoryImpl implements BillboardRepository {
  BillboardRepositoryImpl(this._client);

  final MysqlClient _client;

  static const _table = 'bb_arrangement';

  @override
  Future<void> connect(DbConnectionConfig config) => _client.connect(config);

  @override
  Future<void> disconnect() => _client.disconnect();

  @override
  Future<bool> testConnection(DbConnectionConfig config) => _client.test(config);

  @override
  Future<List<ArrangementBlock>> loadMenuArrangements(String compName) {
    return _loadArrangements(compName: compName, usePicture: false);
  }

  @override
  Future<List<ArrangementBlock>> loadPictureArrangements(String compName) {
    return _loadArrangements(compName: compName, usePicture: true);
  }

  Future<List<ArrangementBlock>> _loadArrangements({
    required String compName,
    required bool usePicture,
  }) async {
    final rows = await _client.query(
      'SELECT * FROM $_table '
      'WHERE usepic = ? AND comp_name = ? '
      'ORDER BY screen_name, ID',
      [usePicture ? 1 : 0, compName],
    );

    final list = <ArrangementBlock>[];
    for (final row in rows) {
      final block = _mapArrangement(Map<String, dynamic>.from(row.fields));
      if (block.classId == 0 && !block.hasPicture && !block.usePicture) {
        continue;
      }
      if (usePicture && !block.hasPicture) continue;
      if (!usePicture && block.classId == 0) continue;
      list.add(block);
    }
    return list;
  }

  ArrangementBlock _mapArrangement(Map<String, dynamic> row) {
    return ArrangementBlock(
      id: Utils.asInt(row['ID']),
      compName: Utils.str(row['comp_name']),
      screenName: Utils.str(row['screen_name']),
      classId: Utils.asInt(row['class_id'] ?? row['Class_ID']),
      xDistance: Utils.asInt(row['xdis']),
      yDistance: Utils.asInt(row['ydis']),
      maxWidth: Utils.asInt(row['max_width'], 600),
      classFontSize: Utils.asInt(row['classfontsize'], 24),
      itemFontSize: Utils.asInt(row['itemsfontsize'], 20),
      classFontName: Utils.str(row['classfname']),
      itemFontName: Utils.str(row['itemfname']),
      classUpperCase: Utils.asFlag(row['classucase']),
      itemUpperCase: Utils.asFlag(row['itemucase']),
      classBold: Utils.asFlag(row['classbold']),
      itemBold: Utils.asFlag(row['itembold']),
      classForeColor: Utils.asInt(row['classfcolor'], 15),
      classBackColor: Utils.asInt(row['classbcolor'], 2),
      itemForeColor: Utils.asInt(row['itemfcolor'], 0),
      itemBackColor: Utils.asInt(row['itemsbcolor'], 15),
      mainBackColor: Utils.asInt(row['mainbcolor'], 15),
      modifierFontSize: Utils.asInt(row['modfsize'], 10),
      modifierFontName: Utils.str(row['modfname']),
      modifierColor: Utils.asInt(row['modfcolor'], 0),
      detailDescription: Utils.str(row['detaildesc']),
      pictureRoute: Utils.str(row['bbpic_route']),
      pictureBytes: Utils.asBytes(row['bb_pic']),
      rangeItems: Utils.str(row['range_items']),
      usePicture: Utils.asFlag(row['usepic']),
    );
  }

  @override
  Future<MenuSection> fillClassView(
    ArrangementBlock block, {
    required bool sortAlphabetical,
  }) async {
    final orderBy = sortAlphabetical
        ? 'it_titem.ITEM_Description ASC'
        : 'it_titem.Prioridad DESC';

    final (offset, count) = block.rangeLimit;
    final limitSql =
        (offset != null && count != null) ? ' LIMIT $offset, $count' : '';

    final sql = '''
SELECT
  it_titemclass.Class_Name,
  it_titem.ITEM_ID,
  it_titem.ITEM_Description,
  it_titem.ITEM_Screen_Name,
  it_titem.ITEM_Sale_Price,
  it_titem.desc_atmenu,
  it_titem.Prioridad
FROM it_titemclass
INNER JOIN it_titem
  ON it_titem.ITEM_Class_ID = it_titemclass.Class_ID
WHERE it_titem.ITEM_Sale_Price <> 0
  AND it_titem.ITEM_Show = 1
  AND it_titemclass.Class_ID = ?
GROUP BY it_titem.ITEM_ID
ORDER BY $orderBy$limitSql
''';

    final rows = await _client.query(sql, [block.classId]);
    String className = '';
    final items = <MenuItemEntity>[];

    for (final row in rows) {
      className = Utils.str(row['Class_Name']);
      if (block.classUpperCase) {
        className = className.toUpperCase();
      }

      final screen = Utils.str(row['ITEM_Screen_Name']);
      final description = Utils.str(row['ITEM_Description']);
      var name = screen.isNotEmpty ? screen : description;
      if (block.itemUpperCase) name = name.toUpperCase();

      items.add(
        MenuItemEntity(
          itemId: Utils.str(row['ITEM_ID']),
          name: name,
          price: Utils.blobToDouble(row['ITEM_Sale_Price']) ?? 0,
          description: Utils.str(row['desc_atmenu']),
          className: className,
        ),
      );
    }

    return MenuSection(
      arrangement: block,
      className: className.isEmpty ? block.screenName : className,
      items: items,
    );
  }

  @override
  Future<BillboardBoard> loadBoard({
    required String compName,
    required bool sortAlphabetical,
  }) async {
    final menus = await loadMenuArrangements(compName);
    final pics = await loadPictureArrangements(compName);

    final sections = <MenuSection>[];
    for (final block in menus) {
      try {
        final section = await fillClassView(
          block,
          sortAlphabetical: sortAlphabetical,
        );
        if (section.items.isNotEmpty || section.className.isNotEmpty) {
          sections.add(section);
        }
      } catch (_) {
        // Skip broken class blocks so one bad row does not blank the board.
      }
    }

    final pictures = [
      for (final b in pics) PictureBlock(arrangement: b),
    ];

    final mainBg = sections.isNotEmpty
        ? sections.first.arrangement.mainBackColor
        : (pics.isNotEmpty ? pics.first.mainBackColor : 0);

    return BillboardBoard(
      compName: compName,
      sections: sections,
      pictures: pictures,
      mainBackColor: mainBg,
    );
  }

  @override
  Future<List<String>> listConfiguredComputerNames() async {
    final rows = await _client.query(
      'SELECT DISTINCT comp_name FROM $_table '
      'WHERE comp_name IS NOT NULL AND TRIM(comp_name) <> \'\' '
      'ORDER BY comp_name',
    );
    return [
      for (final row in rows)
        Utils.str(row['comp_name']),
    ].where((e) => e.isNotEmpty).toList();
  }

  /// POS register display names (`it_tregister.Regi_Name`) — useful picker on
  /// Android/iOS where there is no Windows computer name.
  @override
  Future<List<String>> listRegisterNames() async {
    try {
      final rows = await _client.query(
        'SELECT DISTINCT Regi_Name FROM it_tregister '
        'WHERE Regi_Name IS NOT NULL AND TRIM(Regi_Name) <> \'\' '
        'ORDER BY Regi_Name',
      );
      return [
        for (final row in rows) Utils.str(row['Regi_Name']),
      ].where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> hasArrangementFor(String compName) async {
    final rows = await _client.query(
      'SELECT ID FROM $_table WHERE comp_name = ? LIMIT 1',
      [compName],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> ensureArrangementForComputer({
    required String compName,
    String? templateCompName,
  }) async {
    final name = compName.trim();
    if (name.isEmpty) return;

    final template = (templateCompName ?? '').trim();
    if (template.isNotEmpty && template != name) {
      // Explicit "Copiar layout desde": replace this device's rows with the
      // full template (otherwise a prior starter Screen 1 blocks the copy).
      await _client.query('DELETE FROM $_table WHERE comp_name = ?', [name]);
      final copied = await _copyArrangements(from: template, to: name);
      if (copied > 0) return;
    }

    if (await hasArrangementFor(name)) return;

    // Same starter defaults as POS Billboard "Add" (BillboardScreenConfig).
    // Prefer first menu class so the board is not blank.
    var classId = 0;
    try {
      final classes = await _client.query(
        'SELECT Class_ID FROM it_titemclass ORDER BY Class_Name LIMIT 1',
      );
      if (classes.isNotEmpty) {
        classId = Utils.asInt(classes.first['Class_ID']);
      }
    } catch (_) {}

    await _client.query(
      '''
INSERT INTO $_table (
  comp_name, screen_name, class_id, xdis, ydis, max_width,
  classfontsize, itemsfontsize, classfname, itemfname,
  classucase, itemucase, classbold, itembold,
  classfcolor, classbcolor, itemfcolor, itemsbcolor, mainbcolor,
  modfsize, modfname, modfcolor, detaildesc, bbpic_route, range_items, usepic
) VALUES (
  ?, ?, ?, 40, 40, 600,
  24, 20, '', '',
  0, 0, 0, 0,
  '15', '2', '15', '0', '0',
  10, '', '7', '', '', '', 0
)
''',
      [name, 'Screen 1', classId],
    );
  }

  Future<int> _copyArrangements({
    required String from,
    required String to,
  }) async {
    final rows = await _client.query(
      'SELECT * FROM $_table WHERE comp_name = ?',
      [from],
    );
    var count = 0;
    for (final row in rows) {
      final f = Map<String, dynamic>.from(row.fields);
      await _client.query(
        '''
INSERT INTO $_table (
  comp_name, screen_name, class_id, xdis, ydis, max_width,
  classfontsize, itemsfontsize, classfname, itemfname,
  classucase, itemucase, classbold, itembold,
  classfcolor, classbcolor, itemfcolor, itemsbcolor, mainbcolor,
  modfsize, modfname, modfcolor,
  pricefname, pricefsize, pricefcolor,
  detaildesc, bbpic_route, bb_pic, range_items, usepic
) VALUES (
  ?, ?, ?, ?, ?, ?,
  ?, ?, ?, ?,
  ?, ?, ?, ?,
  ?, ?, ?, ?, ?,
  ?, ?, ?,
  ?, ?, ?,
  ?, ?, ?, ?, ?
)
''',
        [
          to,
          Utils.str(f['screen_name']).isEmpty
              ? 'Screen 1'
              : Utils.str(f['screen_name']),
          Utils.asInt(f['class_id'] ?? f['Class_ID']),
          Utils.asInt(f['xdis']),
          Utils.asInt(f['ydis']),
          Utils.asInt(f['max_width'], 600),
          Utils.asInt(f['classfontsize'], 24),
          Utils.asInt(f['itemsfontsize'], 20),
          Utils.str(f['classfname']),
          Utils.str(f['itemfname']),
          Utils.asFlag(f['classucase']) ? 1 : 0,
          Utils.asFlag(f['itemucase']) ? 1 : 0,
          Utils.asFlag(f['classbold']) ? 1 : 0,
          Utils.asFlag(f['itembold']) ? 1 : 0,
          Utils.str(f['classfcolor']).isEmpty
              ? '15'
              : Utils.str(f['classfcolor']),
          Utils.str(f['classbcolor']).isEmpty
              ? '2'
              : Utils.str(f['classbcolor']),
          Utils.str(f['itemfcolor']).isEmpty
              ? '0'
              : Utils.str(f['itemfcolor']),
          Utils.str(f['itemsbcolor']).isEmpty
              ? '15'
              : Utils.str(f['itemsbcolor']),
          Utils.str(f['mainbcolor']).isEmpty
              ? '0'
              : Utils.str(f['mainbcolor']),
          Utils.asInt(f['modfsize'], 10),
          Utils.str(f['modfname']),
          Utils.str(f['modfcolor']).isEmpty
              ? '0'
              : Utils.str(f['modfcolor']),
          Utils.str(f['pricefname']),
          Utils.asInt(f['pricefsize'], 20),
          Utils.str(f['pricefcolor']).isEmpty
              ? '0'
              : Utils.str(f['pricefcolor']),
          Utils.str(f['detaildesc']),
          Utils.str(f['bbpic_route']),
          Utils.asBytes(f['bb_pic']),
          Utils.str(f['range_items']),
          Utils.asFlag(f['usepic']) ? 1 : 0,
        ],
      );
      count++;
    }
    return count;
  }

  @override
  Future<void> updateArrangementLayout({
    required int id,
    required String compName,
    required ArrangementBlock arrangement,
  }) async {
    final name = compName.trim();
    if (name.isEmpty || id <= 0) return;
    final a = arrangement;

    await _client.query(
      '''
UPDATE $_table SET
  xdis = ?,
  ydis = ?,
  max_width = ?,
  classfontsize = ?,
  itemsfontsize = ?,
  classfname = ?,
  itemfname = ?,
  classucase = ?,
  itemucase = ?,
  classbold = ?,
  itembold = ?,
  classfcolor = ?,
  classbcolor = ?,
  itemfcolor = ?,
  itemsbcolor = ?,
  mainbcolor = ?,
  modfsize = ?,
  modfname = ?,
  modfcolor = ?,
  detaildesc = ?
WHERE ID = ? AND comp_name = ?
''',
      [
        a.xDistance.clamp(0, 100000),
        a.yDistance.clamp(0, 100000),
        a.maxWidth.clamp(80, 20000),
        a.classFontSize.clamp(10, 96),
        a.itemFontSize.clamp(8, 72),
        a.classFontName,
        a.itemFontName,
        a.classUpperCase ? 1 : 0,
        a.itemUpperCase ? 1 : 0,
        a.classBold ? 1 : 0,
        a.itemBold ? 1 : 0,
        '${QbColors.clampOpaque(a.classForeColor)}',
        '${QbColors.clampFill(a.classBackColor)}',
        '${QbColors.clampOpaque(a.itemForeColor)}',
        '${QbColors.clampFill(a.itemBackColor)}',
        '${QbColors.clampOpaque(a.mainBackColor)}',
        a.modifierFontSize.clamp(8, 48),
        a.modifierFontName,
        '${QbColors.clampOpaque(a.modifierColor)}',
        a.detailDescription,
        id,
        name,
      ],
    );
  }
}
