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
