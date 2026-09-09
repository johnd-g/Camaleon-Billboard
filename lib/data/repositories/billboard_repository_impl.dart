import 'package:mysql1/mysql1.dart';

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
    final args = [usePicture ? 1 : 0, compName];
    Results rows;
    try {
      rows = await _client.query(
        'SELECT * FROM $_table '
        'WHERE usepic = ? AND comp_name = ? '
        'ORDER BY display_order ASC, screen_name ASC, ID ASC',
        args,
      );
    } catch (e) {
      // Older DBs without display_order — never ALTER; just fall back.
      final msg = e.toString().toLowerCase();
      if (!msg.contains('unknown column')) rethrow;
      rows = await _client.query(
        'SELECT * FROM $_table '
        'WHERE usepic = ? AND comp_name = ? '
        'ORDER BY screen_name ASC, ID ASC',
        args,
      );
    }

    final list = <ArrangementBlock>[];
    for (final row in rows) {
      final block = _mapArrangement(Map<String, dynamic>.from(row.fields));
      if (block.classId == 0 &&
          !block.hasPicture &&
          !block.usePicture &&
          block.contentType != ArrangementContentType.offer) {
        continue;
      }
      if (usePicture && !block.hasPicture) continue;
      if (!usePicture &&
          block.classId == 0 &&
          block.contentType != ArrangementContentType.offer) {
        continue;
      }
      list.add(block);
    }
    return list;
  }

  ArrangementBlock _mapArrangement(Map<String, dynamic> row) {
    final mediaFile = Utils.str(row['media_file']);
    final mediaType = ArrangementMediaType.parse(Utils.str(row['media_type']));
    var pictureRoute = Utils.str(row['bbpic_route']);
    if (pictureRoute.isEmpty &&
        mediaType == ArrangementMediaType.image &&
        mediaFile.isNotEmpty) {
      pictureRoute = mediaFile;
    }

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
      pictureRoute: pictureRoute,
      pictureBytes: Utils.asBytes(row['bb_pic']),
      rangeItems: Utils.str(row['range_items']),
      usePicture: Utils.asFlag(row['usepic']),
      boardBackground: Utils.asFlag(row['bb_background']),
      contentType: ArrangementContentType.parse(Utils.str(row['content_type'])),
      offerId: Utils.asInt(row['offer_id']),
      mediaType: mediaType,
      mediaFile: mediaFile,
      mediaFit: ArrangementMediaFit.parse(Utils.str(row['media_fit'])),
      mediaOpacity: Utils.asDouble(row['media_opacity'], 1),
      videoLoop: Utils.asInt(row['video_loop'], 1) != 0,
      videoMuted: Utils.asInt(row['video_muted'], 1) != 0,
      displayOrder: Utils.asInt(row['display_order']),
      displaySeconds: Utils.asInt(row['display_seconds'], 8),
      borderTopWidth: Utils.asInt(row['border_top_width']),
      borderTopColor: Utils.str(row['border_top_color']),
      borderRightWidth: Utils.asInt(row['border_right_width']),
      borderRightColor: Utils.str(row['border_right_color']),
      borderBottomWidth: Utils.asInt(row['border_bottom_width']),
      borderBottomColor: Utils.str(row['border_bottom_color']),
      borderLeftWidth: Utils.asInt(row['border_left_width']),
      borderLeftColor: Utils.str(row['border_left_color']),
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

    // Active happy-hour / date specials (same tables POS 2.0 uses).
    final specialIds = await _activeSpecialIds();
    final priceExpr = specialIds.isEmpty
        ? 'it_titem.ITEM_Sale_Price'
        : '''COALESCE(
  (
    SELECT ds.item_price
    FROM day_specials ds
    WHERE ds.PR_ID IN ($specialIds)
      AND ds.item_id = it_titem.ITEM_ID
      AND IFNULL(ds.item_dis, 0) <> 1
      AND IFNULL(ds.class_dis, 0) <> 1
    ORDER BY ds.PR_ID ASC
    LIMIT 1
  ),
  it_titem.ITEM_Sale_Price
)''';

    final sql = '''
SELECT
  it_titemclass.Class_Name,
  it_titem.ITEM_ID,
  it_titem.ITEM_Description,
  it_titem.ITEM_Screen_Name,
  $priceExpr AS ITEM_Sale_Price,
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

  /// Comma-separated active `dates_special.Id` values, or empty if none / tables missing.
  Future<String> _activeSpecialIds() async {
    try {
      final rows = await _client.query('''
SELECT ds.Id
FROM dates_special ds
WHERE IFNULL(ds.inactive, 0) = 0
  AND NOW() BETWEEN ds.DateIn AND ds.DateOut
  AND (
    (DAYOFWEEK(NOW()) = 1 AND IFNULL(ds.SUON, 0) = 1) OR
    (DAYOFWEEK(NOW()) = 2 AND IFNULL(ds.MOON, 0) = 1) OR
    (DAYOFWEEK(NOW()) = 3 AND IFNULL(ds.TUON, 0) = 1) OR
    (DAYOFWEEK(NOW()) = 4 AND IFNULL(ds.WEON, 0) = 1) OR
    (DAYOFWEEK(NOW()) = 5 AND IFNULL(ds.THON, 0) = 1) OR
    (DAYOFWEEK(NOW()) = 6 AND IFNULL(ds.FRON, 0) = 1) OR
    (DAYOFWEEK(NOW()) = 7 AND IFNULL(ds.SAON, 0) = 1)
  )
  AND (
    TIME(ds.DateOut) < TIME(ds.DateIn)
    OR TIME(NOW()) BETWEEN TIME(ds.DateIn) AND TIME(ds.DateOut)
  )
ORDER BY ds.DateOut ASC
''');
      final ids = <String>[];
      for (final row in rows) {
        final id = Utils.asInt(row['Id']);
        if (id > 0) ids.add('$id');
      }
      return ids.join(',');
    } catch (_) {
      return '';
    }
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
  Future<BillboardBoard> refreshMenuItems(
    BillboardBoard current, {
    required bool sortAlphabetical,
  }) async {
    final sections = <MenuSection>[];
    for (final section in current.sections) {
      try {
        final next = await fillClassView(
          section.arrangement,
          sortAlphabetical: sortAlphabetical,
        );
        sections.add(next);
      } catch (_) {
        sections.add(section);
      }
    }
    return current.copyWith(sections: sections);
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
  detaildesc, bbpic_route, bb_pic, range_items, usepic, bb_background,
  content_type, offer_id, media_type, media_file, media_fit, media_opacity,
  video_loop, video_muted, display_order, display_seconds,
  border_top_width, border_top_color,
  border_right_width, border_right_color,
  border_bottom_width, border_bottom_color,
  border_left_width, border_left_color
) VALUES (
  ?, ?, ?, ?, ?, ?,
  ?, ?, ?, ?,
  ?, ?, ?, ?,
  ?, ?, ?, ?, ?,
  ?, ?, ?,
  ?, ?, ?,
  ?, ?, ?, ?, ?, ?,
  ?, ?, ?, ?, ?, ?,
  ?, ?, ?, ?,
  ?, ?,
  ?, ?,
  ?, ?,
  ?, ?
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
          Utils.asFlag(f['bb_background']) ? 1 : 0,
          ArrangementContentType.parse(Utils.str(f['content_type'])).dbValue,
          Utils.asInt(f['offer_id']),
          ArrangementMediaType.parse(Utils.str(f['media_type'])).dbValue,
          Utils.str(f['media_file']),
          ArrangementMediaFit.parse(Utils.str(f['media_fit'])).dbValue,
          Utils.asDouble(f['media_opacity'], 1).clamp(0, 1),
          Utils.asInt(f['video_loop'], 1) != 0 ? 1 : 0,
          Utils.asInt(f['video_muted'], 1) != 0 ? 1 : 0,
          Utils.asInt(f['display_order']),
          Utils.asInt(f['display_seconds'], 8),
          Utils.asInt(f['border_top_width']),
          Utils.str(f['border_top_color']),
          Utils.asInt(f['border_right_width']),
          Utils.str(f['border_right_color']),
          Utils.asInt(f['border_bottom_width']),
          Utils.str(f['border_bottom_color']),
          Utils.asInt(f['border_left_width']),
          Utils.str(f['border_left_color']),
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
  detaildesc = ?,
  bb_background = ?,
  content_type = ?,
  offer_id = ?,
  media_type = ?,
  media_file = ?,
  media_fit = ?,
  media_opacity = ?,
  video_loop = ?,
  video_muted = ?,
  display_order = ?,
  display_seconds = ?,
  border_top_width = ?,
  border_top_color = ?,
  border_right_width = ?,
  border_right_color = ?,
  border_bottom_width = ?,
  border_bottom_color = ?,
  border_left_width = ?,
  border_left_color = ?
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
        a.boardBackground ? 1 : 0,
        a.contentType.dbValue,
        a.offerId.clamp(0, 2147483647),
        a.mediaType.dbValue,
        a.mediaFile,
        a.mediaFit.dbValue,
        a.clampedMediaOpacity,
        a.videoLoop ? 1 : 0,
        a.videoMuted ? 1 : 0,
        a.displayOrder.clamp(0, 100000),
        a.displaySeconds.clamp(1, 3600),
        a.borderTopWidth.clamp(0, 200),
        a.borderTopColor,
        a.borderRightWidth.clamp(0, 200),
        a.borderRightColor,
        a.borderBottomWidth.clamp(0, 200),
        a.borderBottomColor,
        a.borderLeftWidth.clamp(0, 200),
        a.borderLeftColor,
        id,
        name,
      ],
    );
  }

  static const _boardBackgroundScreenName = 'Board background';

  @override
  Future<void> upsertBoardBackgroundImage({
    required String compName,
    required List<int> bytes,
    int mainBackColor = 0,
  }) async {
    final name = compName.trim();
    if (name.isEmpty || bytes.isEmpty) return;

    // Only one board background per device.
    await _client.query(
      'UPDATE $_table SET bb_background = 0 WHERE comp_name = ?',
      [name],
    );

    final existing = await _client.query(
      'SELECT ID FROM $_table '
      'WHERE comp_name = ? AND usepic = 1 AND screen_name = ? '
      'LIMIT 1',
      [name, _boardBackgroundScreenName],
    );

    if (existing.isNotEmpty) {
      final id = Utils.asInt(existing.first['ID']);
      await _client.query(
        'UPDATE $_table SET '
        'bb_pic = ?, bbpic_route = ?, bb_background = 1, mainbcolor = ?, '
        "media_type = 'IMAGE', media_file = '', media_fit = 'COVER', "
        'media_opacity = 1.000 '
        'WHERE ID = ? AND comp_name = ?',
        [bytes, '', '$mainBackColor', id, name],
      );
      return;
    }

    await _client.query(
      '''
INSERT INTO $_table (
  comp_name, screen_name, class_id, xdis, ydis, max_width,
  classfontsize, itemsfontsize, classfname, itemfname,
  classucase, itemucase, classbold, itembold,
  classfcolor, classbcolor, itemfcolor, itemsbcolor, mainbcolor,
  modfsize, modfname, modfcolor,
  detaildesc, bbpic_route, bb_pic, range_items, usepic, bb_background,
  content_type, media_type, media_fit, media_opacity
) VALUES (
  ?, ?, 0, 0, 0, 1920,
  24, 20, '', '',
  0, 0, 0, 0,
  '15', '2', '0', '15', ?,
  10, '', '0',
  '', '', ?, '', 1, 1,
  'MENU', 'IMAGE', 'COVER', 1.000
)
''',
      [name, _boardBackgroundScreenName, '$mainBackColor', bytes],
    );
  }

  @override
  Future<void> upsertBoardBackgroundVideo({
    required String compName,
    required String mediaFile,
    String pictureRoute = '',
    int mainBackColor = 0,
    bool videoLoop = true,
    bool videoMuted = true,
  }) async {
    final name = compName.trim();
    final file = mediaFile.trim();
    if (name.isEmpty || file.isEmpty) return;
    final route = pictureRoute.trim().isNotEmpty ? pictureRoute.trim() : file;

    await _client.query(
      'UPDATE $_table SET bb_background = 0 WHERE comp_name = ?',
      [name],
    );

    final existing = await _client.query(
      'SELECT ID FROM $_table '
      'WHERE comp_name = ? AND usepic = 1 AND screen_name = ? '
      'LIMIT 1',
      [name, _boardBackgroundScreenName],
    );

    if (existing.isNotEmpty) {
      final id = Utils.asInt(existing.first['ID']);
      await _client.query(
        'UPDATE $_table SET '
        'bb_pic = NULL, bbpic_route = ?, bb_background = 1, mainbcolor = ?, '
        "media_type = 'VIDEO', media_file = ?, media_fit = 'COVER', "
        'media_opacity = 1.000, video_loop = ?, video_muted = ? '
        'WHERE ID = ? AND comp_name = ?',
        [
          route,
          '$mainBackColor',
          file,
          videoLoop ? 1 : 0,
          videoMuted ? 1 : 0,
          id,
          name,
        ],
      );
      return;
    }

    await _client.query(
      '''
INSERT INTO $_table (
  comp_name, screen_name, class_id, xdis, ydis, max_width,
  classfontsize, itemsfontsize, classfname, itemfname,
  classucase, itemucase, classbold, itembold,
  classfcolor, classbcolor, itemfcolor, itemsbcolor, mainbcolor,
  modfsize, modfname, modfcolor,
  detaildesc, bbpic_route, range_items, usepic, bb_background,
  content_type, media_type, media_file, media_fit, media_opacity,
  video_loop, video_muted
) VALUES (
  ?, ?, 0, 0, 0, 1920,
  24, 20, '', '',
  0, 0, 0, 0,
  '15', '2', '0', '15', ?,
  10, '', '0',
  '', ?, '', 1, 1,
  'MENU', 'VIDEO', ?, 'COVER', 1.000,
  ?, ?
)
''',
      [
        name,
        _boardBackgroundScreenName,
        '$mainBackColor',
        route,
        file,
        videoLoop ? 1 : 0,
        videoMuted ? 1 : 0,
      ],
    );
  }

  @override
  Future<void> clearBoardBackgroundImage(String compName) async {
    final name = compName.trim();
    if (name.isEmpty) return;

    await _client.query(
      'UPDATE $_table SET bb_background = 0 WHERE comp_name = ?',
      [name],
    );
    await _client.query(
      'DELETE FROM $_table '
      'WHERE comp_name = ? AND usepic = 1 AND screen_name = ?',
      [name, _boardBackgroundScreenName],
    );
  }

  @override
  Future<void> updateArrangementMedia({
    required int id,
    required String compName,
    required ArrangementMediaType mediaType,
    required String mediaFile,
    String pictureRoute = '',
    List<int>? pictureBytes,
  }) async {
    final name = compName.trim();
    if (name.isEmpty || id <= 0) return;

    if (pictureBytes != null) {
      if (pictureBytes.isEmpty) {
        await _client.query(
          'UPDATE $_table SET '
          'media_type = ?, media_file = ?, bbpic_route = ?, bb_pic = NULL '
          'WHERE ID = ? AND comp_name = ?',
          [mediaType.dbValue, mediaFile, pictureRoute, id, name],
        );
      } else {
        await _client.query(
          'UPDATE $_table SET '
          'media_type = ?, media_file = ?, bbpic_route = ?, bb_pic = ? '
          'WHERE ID = ? AND comp_name = ?',
          [
            mediaType.dbValue,
            mediaFile,
            pictureRoute,
            pictureBytes,
            id,
            name,
          ],
        );
      }
      return;
    }

    await _client.query(
      'UPDATE $_table SET '
      'media_type = ?, media_file = ?, bbpic_route = ? '
      'WHERE ID = ? AND comp_name = ?',
      [mediaType.dbValue, mediaFile, pictureRoute, id, name],
    );
  }
}
