import 'dart:typed_data';

import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';

class MenuItemEntity {
  const MenuItemEntity({
    required this.itemId,
    required this.name,
    required this.price,
    this.description = '',
    this.className = '',
  });

  final String itemId;
  final String name;
  final double price;
  final String description;
  final String className;
}

/// A POS menu class (`it_titemclass`) available for a new menu block.
class MenuClassOption {
  const MenuClassOption({
    required this.classId,
    required this.name,
  });

  final int classId;
  final String name;
}

/// A POS daily special (`dates_special`) for OFFER blocks.
class SpecialOfferOption {
  const SpecialOfferOption({
    required this.id,
    required this.name,
    this.dateIn = '',
    this.dateOut = '',
    this.inactive = false,
  });

  final int id;
  final String name;
  final String dateIn;
  final String dateOut;
  final bool inactive;

  String get label {
    final n = name.trim().isEmpty ? 'Special #$id' : name.trim();
    return '$n  ·  #$id';
  }

  String get subtitle {
    final parts = <String>[];
    if (dateIn.trim().isNotEmpty || dateOut.trim().isNotEmpty) {
      parts.add('${dateIn.trim()} → ${dateOut.trim()}');
    }
    if (inactive) parts.add('inactive');
    return parts.join(' · ');
  }
}

/// Open POS ticket for Customer display (`it_tcuenta` + `it_torder`).
class CustomerOrderTicket {
  const CustomerOrderTicket({
    required this.cuentaId,
    required this.label,
    required this.lines,
    required this.total,
  });

  final int cuentaId;
  final String label;
  final List<CustomerOrderLine> lines;
  final double total;
}

class CustomerOrderLine {
  const CustomerOrderLine({
    required this.qty,
    required this.name,
    required this.unitPrice,
  });

  final double qty;
  final String name;
  final double unitPrice;

  double get lineTotal => qty * unitPrice;
}

class MenuSection {
  const MenuSection({
    required this.arrangement,
    required this.className,
    required this.items,
  });

  final ArrangementBlock arrangement;
  final String className;
  final List<MenuItemEntity> items;

  MenuSection copyWith({
    ArrangementBlock? arrangement,
    String? className,
    List<MenuItemEntity>? items,
  }) {
    return MenuSection(
      arrangement: arrangement ?? this.arrangement,
      className: className ?? this.className,
      items: items ?? this.items,
    );
  }
}

class PictureBlock {
  const PictureBlock({
    required this.arrangement,
  });

  final ArrangementBlock arrangement;

  String get route => arrangement.pictureRoute;
  Uint8List? get bytes => arrangement.pictureBytes;
  bool get hasImage => arrangement.hasPicture;
  int get x => arrangement.xDistance;
  int get y => arrangement.yDistance;

  PictureBlock copyWith({ArrangementBlock? arrangement}) {
    return PictureBlock(arrangement: arrangement ?? this.arrangement);
  }
}

class BillboardBoard {
  const BillboardBoard({
    required this.compName,
    required this.sections,
    required this.pictures,
    this.mainBackColor = 0,
  });

  final String compName;
  final List<MenuSection> sections;
  final List<PictureBlock> pictures;
  final int mainBackColor;

  List<PictureBlock> get boardBackgroundPictures => [
        for (final p in pictures)
          if (p.arrangement.isBoardBackground) p,
      ];

  /// More than one `bb_background=1` — invalid; UI should warn.
  bool get hasMultipleBoardBackgrounds =>
      boardBackgroundPictures.length > 1;

  BillboardBoard copyWith({
    String? compName,
    List<MenuSection>? sections,
    List<PictureBlock>? pictures,
    int? mainBackColor,
  }) {
    return BillboardBoard(
      compName: compName ?? this.compName,
      sections: sections ?? this.sections,
      pictures: pictures ?? this.pictures,
      mainBackColor: mainBackColor ?? this.mainBackColor,
    );
  }
}
