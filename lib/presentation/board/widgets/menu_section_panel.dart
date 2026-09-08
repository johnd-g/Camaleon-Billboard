import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:camaleon_billboard/core/utils/qb_color.dart';
import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';

class MenuSectionPanel extends StatelessWidget {
  const MenuSectionPanel({super.key, required this.section});

  final MenuSection section;

  static final NumberFormat _currency =
      NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final a = section.arrangement;
    final bg = a.itemBackColor == 0
        ? const Color.fromARGB(255, 1, 1, 1)
        : QbColors.of(a.itemBackColor);

    return ColoredBox(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ClassHeader(arrangement: a, title: section.className),
            const SizedBox(height: 4),
            for (final item in section.items) ...[
              _ItemRow(
                arrangement: a,
                name: item.name,
                price: _currency.format(item.price),
              ),
              if (item.description.trim().isNotEmpty)
                _DescRow(arrangement: a, text: item.description),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClassHeader extends StatelessWidget {
  const _ClassHeader({required this.arrangement, required this.title});

  final ArrangementBlock arrangement;
  final String title;

  @override
  Widget build(BuildContext context) {
    final a = arrangement;
    return ColoredBox(
      color: QbColors.of(a.classBackColor),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: QbColors.of(a.classForeColor),
            fontSize: a.classFontSize.toDouble(),
            fontWeight: a.classBold ? FontWeight.w800 : FontWeight.w700,
            fontFamily: a.classFontName.isEmpty ? null : a.classFontName,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.arrangement,
    required this.name,
    required this.price,
  });

  final ArrangementBlock arrangement;
  final String name;
  final String price;

  @override
  Widget build(BuildContext context) {
    final a = arrangement;
    final style = TextStyle(
      color: QbColors.of(a.itemForeColor),
      fontSize: a.itemFontSize.toDouble(),
      fontWeight: a.itemBold ? FontWeight.w700 : FontWeight.w500,
      fontFamily: a.itemFontName.isEmpty ? null : a.itemFontName,
      height: 1.15,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(name, style: style)),
          const SizedBox(width: 8),
          Text(price, style: style.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DescRow extends StatelessWidget {
  const _DescRow({required this.arrangement, required this.text});

  final ArrangementBlock arrangement;
  final String text;

  @override
  Widget build(BuildContext context) {
    final a = arrangement;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 48),
      child: Text(
        text,
        style: TextStyle(
          color: QbColors.of(a.modifierColor),
          fontSize: a.modifierFontSize.toDouble().clamp(8, 48),
          fontStyle: FontStyle.italic,
          fontFamily: a.modifierFontName.isEmpty ? null : a.modifierFontName,
          height: 1.2,
        ),
      ),
    );
  }
}

class BillboardPicturePanel extends StatelessWidget {
  const BillboardPicturePanel({super.key, required this.block});

  final PictureBlock block;

  @override
  Widget build(BuildContext context) {
    final path = block.route;
    if (path.isEmpty) return const SizedBox.shrink();

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(path, fit: BoxFit.contain, errorBuilder: _err);
    }

    final file = File(path);
    if (!file.existsSync()) {
      return _MissingPic(path: path);
    }
    return Image.file(file, fit: BoxFit.contain, errorBuilder: _err);
  }

  Widget _err(BuildContext context, Object error, StackTrace? stackTrace) =>
      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48);
}

class _MissingPic extends StatelessWidget {
  const _MissingPic({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black26,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        path,
        style: const TextStyle(color: Colors.white54, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }
}
