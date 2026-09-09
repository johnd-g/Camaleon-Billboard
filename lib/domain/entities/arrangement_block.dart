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
    this.contentType = ArrangementContentType.menu,
    this.offerId = 0,
    this.mediaType = ArrangementMediaType.none,
    this.mediaFile = '',
    this.mediaFit = ArrangementMediaFit.cover,
    this.mediaOpacity = 1,
    this.videoLoop = true,
    this.videoMuted = true,
    this.displayOrder = 0,
    this.displaySeconds = 8,
    this.borderTopWidth = 0,
    this.borderTopColor = '',
    this.borderRightWidth = 0,
    this.borderRightColor = '',
    this.borderBottomWidth = 0,
    this.borderBottomColor = '',
    this.borderLeftWidth = 0,
    this.borderLeftColor = '',
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

  /// `content_type`: MENU or OFFER.
  final ArrangementContentType contentType;

  /// Daily special / offer id when [contentType] is offer.
  final int offerId;

  /// `media_type`: NONE, IMAGE, or VIDEO.
  final ArrangementMediaType mediaType;

  /// Relative image or video filename (`media_file`).
  final String mediaFile;

  /// `media_fit`: COVER, CONTAIN, or STRETCH.
  final ArrangementMediaFit mediaFit;

  /// `media_opacity` 0.000–1.000.
  final double mediaOpacity;

  final bool videoLoop;
  final bool videoMuted;
  final int displayOrder;
  final int displaySeconds;

  final int borderTopWidth;
  final String borderTopColor;
  final int borderRightWidth;
  final String borderRightColor;
  final int borderBottomWidth;
  final String borderBottomColor;
  final int borderLeftWidth;
  final String borderLeftColor;

  bool get hasPicture =>
      (pictureBytes != null && pictureBytes!.isNotEmpty) ||
      pictureRoute.isNotEmpty ||
      ((mediaType == ArrangementMediaType.image ||
              mediaType == ArrangementMediaType.video) &&
          mediaFile.isNotEmpty);

  bool get isBoardBackground => boardBackground;

  bool get hasAnyBorder =>
      borderTopWidth > 0 ||
      borderRightWidth > 0 ||
      borderBottomWidth > 0 ||
      borderLeftWidth > 0;

  double get clampedMediaOpacity => mediaOpacity.clamp(0.0, 1.0);

  /// Display height for foreground photos (no DB height column — follows width).
  double get pictureDisplayHeight =>
      maxWidth.toDouble().clamp(40, 20000) * 0.75;

  /// Parses Classic `range_items` as `offset-count` (Skip / Count).
  (int? offset, int? count) get rangeLimit {
    final raw = rangeItems.trim();
    if (raw.isEmpty) return (null, null);
    // Accept ASCII '-' or en/em dashes from Classic / copy-paste.
    final match = RegExp(r'^(\d+)\s*[-–—]\s*(\d+)$').firstMatch(raw);
    if (match == null) return (null, null);
    final offset = int.tryParse(match.group(1)!);
    final count = int.tryParse(match.group(2)!);
    if (offset == null || count == null || offset < 0 || count <= 0) {
      return (null, null);
    }
    return (offset, count);
  }

  /// Offset used by the range UI (0 when unset / show all).
  int get rangeOffset => rangeLimit.$1 ?? 0;

  /// Item count used by the range UI (0 = no LIMIT = all items).
  int get rangeCount => rangeLimit.$2 ?? 0;

  /// Encodes Classic `range_items`. Empty string = show all items.
  static String encodeRangeItems({required int offset, required int count}) {
    final o = offset.clamp(0, 100000);
    final c = count.clamp(0, 100000);
    if (c <= 0) return '';
    return '$o-$c';
  }

  /// Applies Skip/Count to an already-ordered item list.
  List<T> applyRange<T>(List<T> items) {
    final (offset, count) = rangeLimit;
    if (offset == null || count == null) return items;
    if (items.isEmpty) return items;
    final start = offset.clamp(0, items.length);
    final end = (start + count).clamp(0, items.length);
    if (start == 0 && end == items.length) return items;
    return items.sublist(start, end);
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
    bool clearPictureBytes = false,
    String? rangeItems,
    bool? usePicture,
    bool? boardBackground,
    ArrangementContentType? contentType,
    int? offerId,
    ArrangementMediaType? mediaType,
    String? mediaFile,
    ArrangementMediaFit? mediaFit,
    double? mediaOpacity,
    bool? videoLoop,
    bool? videoMuted,
    int? displayOrder,
    int? displaySeconds,
    int? borderTopWidth,
    String? borderTopColor,
    int? borderRightWidth,
    String? borderRightColor,
    int? borderBottomWidth,
    String? borderBottomColor,
    int? borderLeftWidth,
    String? borderLeftColor,
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
      pictureBytes:
          clearPictureBytes ? null : (pictureBytes ?? this.pictureBytes),
      rangeItems: rangeItems ?? this.rangeItems,
      usePicture: usePicture ?? this.usePicture,
      boardBackground: boardBackground ?? this.boardBackground,
      contentType: contentType ?? this.contentType,
      offerId: offerId ?? this.offerId,
      mediaType: mediaType ?? this.mediaType,
      mediaFile: mediaFile ?? this.mediaFile,
      mediaFit: mediaFit ?? this.mediaFit,
      mediaOpacity: mediaOpacity ?? this.mediaOpacity,
      videoLoop: videoLoop ?? this.videoLoop,
      videoMuted: videoMuted ?? this.videoMuted,
      displayOrder: displayOrder ?? this.displayOrder,
      displaySeconds: displaySeconds ?? this.displaySeconds,
      borderTopWidth: borderTopWidth ?? this.borderTopWidth,
      borderTopColor: borderTopColor ?? this.borderTopColor,
      borderRightWidth: borderRightWidth ?? this.borderRightWidth,
      borderRightColor: borderRightColor ?? this.borderRightColor,
      borderBottomWidth: borderBottomWidth ?? this.borderBottomWidth,
      borderBottomColor: borderBottomColor ?? this.borderBottomColor,
      borderLeftWidth: borderLeftWidth ?? this.borderLeftWidth,
      borderLeftColor: borderLeftColor ?? this.borderLeftColor,
    );
  }
}

enum ArrangementContentType {
  menu,
  offer;

  static ArrangementContentType parse(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'OFFER':
        return ArrangementContentType.offer;
      case 'MENU':
      default:
        return ArrangementContentType.menu;
    }
  }

  String get dbValue => switch (this) {
        ArrangementContentType.menu => 'MENU',
        ArrangementContentType.offer => 'OFFER',
      };
}

enum ArrangementMediaType {
  none,
  image,
  video;

  static ArrangementMediaType parse(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'IMAGE':
        return ArrangementMediaType.image;
      case 'VIDEO':
        return ArrangementMediaType.video;
      case 'NONE':
      default:
        return ArrangementMediaType.none;
    }
  }

  String get dbValue => switch (this) {
        ArrangementMediaType.none => 'NONE',
        ArrangementMediaType.image => 'IMAGE',
        ArrangementMediaType.video => 'VIDEO',
      };
}

enum ArrangementMediaFit {
  cover,
  contain,
  stretch;

  static ArrangementMediaFit parse(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'CONTAIN':
        return ArrangementMediaFit.contain;
      case 'STRETCH':
        return ArrangementMediaFit.stretch;
      case 'COVER':
      default:
        return ArrangementMediaFit.cover;
    }
  }

  String get dbValue => switch (this) {
        ArrangementMediaFit.cover => 'COVER',
        ArrangementMediaFit.contain => 'CONTAIN',
        ArrangementMediaFit.stretch => 'STRETCH',
      };
}
