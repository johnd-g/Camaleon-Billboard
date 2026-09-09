import 'dart:typed_data';

/// One row of `bb_arrangement` — mirrors POS [BillboardScreenConfig].
class ArrangementBlock {
  const ArrangementBlock({
    required this.id,
    required this.compName,
    this.screenName = '',
    this.classId = 0,
    this.xDistance = 0,
    this.yDistance = 0,
    this.maxWidth = 600,
    this.classFontSize = 24,
    this.itemFontSize = 20,
    this.classFontName = '',
    this.itemFontName = '',
    this.classUpperCase = false,
    this.itemUpperCase = false,
    this.classBold = false,
    this.itemBold = false,
    this.classForeColor = 15,
    this.classBackColor = 2,
    this.itemForeColor = 0,
    this.itemBackColor = 15,
    this.mainBackColor = 15,
    this.modifierFontSize = 10,
    this.modifierFontName = '',
    this.modifierColor = 0,
    this.detailDescription = '',
    this.pictureRoute = '',
    this.pictureBytes,
    this.rangeItems = '',
    this.usePicture = false,
    this.boardBackground = false,
  });

  final int id;
  final String compName;
  final String screenName;
  final int classId;
  final int xDistance;
  final int yDistance;
  final int maxWidth;
  final int classFontSize;
  final int itemFontSize;
  final String classFontName;
  final String itemFontName;
  final bool classUpperCase;
  final bool itemUpperCase;
  final bool classBold;
  final bool itemBold;
  final int classForeColor;
  final int classBackColor;
  final int itemForeColor;
  final int itemBackColor;
  final int mainBackColor;
  final int modifierFontSize;
  final String modifierFontName;
  final int modifierColor;
  final String detailDescription;
  final String pictureRoute;
  /// Raw image from `bb_arrangement.bb_pic` (LONGBLOB). Preferred over [pictureRoute].
  final Uint8List? pictureBytes;
  final String rangeItems;
  final bool usePicture;

  /// `bb_arrangement.bb_background` — full-bleed board image (only one should be set).
  final bool boardBackground;

  bool get hasPicture =>
      (pictureBytes != null && pictureBytes!.isNotEmpty) ||
      pictureRoute.isNotEmpty;

  bool get isBoardBackground => boardBackground;

  /// Display height for foreground photos (no DB height column — follows width).
  double get pictureDisplayHeight =>
      maxWidth.toDouble().clamp(40, 20000) * 0.75;

  /// Parses Classic `range_items` as `offset-count` for MySQL LIMIT.
  (int? offset, int? count) get rangeLimit {
    final dash = rangeItems.indexOf('-');
    if (dash <= 0) return (null, null);
    final offset = int.tryParse(rangeItems.substring(0, dash).trim());
    final count = int.tryParse(rangeItems.substring(dash + 1).trim());
    if (offset == null || count == null) return (null, null);
    return (offset, count);
  }

  ArrangementBlock copyWith({
    int? id,
    String? compName,
    String? screenName,
    int? classId,
    int? xDistance,
    int? yDistance,
    int? maxWidth,
    int? classFontSize,
    int? itemFontSize,
    String? classFontName,
    String? itemFontName,
    bool? classUpperCase,
    bool? itemUpperCase,
    bool? classBold,
    bool? itemBold,
    int? classForeColor,
    int? classBackColor,
    int? itemForeColor,
    int? itemBackColor,
    int? mainBackColor,
    int? modifierFontSize,
    String? modifierFontName,
    int? modifierColor,
    String? detailDescription,
    String? pictureRoute,
    Uint8List? pictureBytes,
    String? rangeItems,
    bool? usePicture,
    bool? boardBackground,
  }) {
    return ArrangementBlock(
      id: id ?? this.id,
      compName: compName ?? this.compName,
      screenName: screenName ?? this.screenName,
      classId: classId ?? this.classId,
      xDistance: xDistance ?? this.xDistance,
      yDistance: yDistance ?? this.yDistance,
      maxWidth: maxWidth ?? this.maxWidth,
      classFontSize: classFontSize ?? this.classFontSize,
      itemFontSize: itemFontSize ?? this.itemFontSize,
      classFontName: classFontName ?? this.classFontName,
      itemFontName: itemFontName ?? this.itemFontName,
      classUpperCase: classUpperCase ?? this.classUpperCase,
      itemUpperCase: itemUpperCase ?? this.itemUpperCase,
      classBold: classBold ?? this.classBold,
      itemBold: itemBold ?? this.itemBold,
      classForeColor: classForeColor ?? this.classForeColor,
      classBackColor: classBackColor ?? this.classBackColor,
      itemForeColor: itemForeColor ?? this.itemForeColor,
      itemBackColor: itemBackColor ?? this.itemBackColor,
      mainBackColor: mainBackColor ?? this.mainBackColor,
      modifierFontSize: modifierFontSize ?? this.modifierFontSize,
      modifierFontName: modifierFontName ?? this.modifierFontName,
      modifierColor: modifierColor ?? this.modifierColor,
      detailDescription: detailDescription ?? this.detailDescription,
      pictureRoute: pictureRoute ?? this.pictureRoute,
      pictureBytes: pictureBytes ?? this.pictureBytes,
      rangeItems: rangeItems ?? this.rangeItems,
      usePicture: usePicture ?? this.usePicture,
      boardBackground: boardBackground ?? this.boardBackground,
    );
  }
}
