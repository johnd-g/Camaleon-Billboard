import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:camaleon_billboard/core/utils/board_fonts.dart';
import 'package:camaleon_billboard/core/utils/qb_color.dart';
import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';
import 'package:camaleon_billboard/presentation/board/arrangement_block_ui.dart';
import 'package:camaleon_billboard/presentation/board/widgets/billboard_video_panel.dart';

class MenuSectionPanel extends StatelessWidget {
  const MenuSectionPanel({super.key, required this.section});

  final MenuSection section;

  static final NumberFormat _currency =
      NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final a = section.arrangement;
    // Skip/Count live on the arrangement — always slice at paint time so the
    // editor preview updates even when the cached item list is still full.
    final visible = a.applyRange(section.items);
    final border = a.decorationBorder;
    Widget body = ColoredBox(
      color: QbColors.of(a.itemBackColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Full-bleed header — no side padding (avoids a “border” from item fill).
          _ClassHeader(
            arrangement: a,
            title: section.className,
            isOffer: a.contentType == ArrangementContentType.offer,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (visible.isEmpty &&
                    a.contentType == ArrangementContentType.offer)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      a.offerId <= 0
                          ? 'Set Offer ID from POS specials'
                          : 'No items in this special',
                      textAlign: TextAlign.center,
                      style: BoardFonts.apply(
                        a.itemFontName,
                        TextStyle(
                          color: QbColors.of(a.itemForeColor)
                              .withValues(alpha: 0.7),
                          fontSize: a.itemFontSize.toDouble().clamp(10, 48),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                for (final item in visible) ...[
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
        ],
      ),
    );
    if (border != null) {
      body = DecoratedBox(
        decoration: BoxDecoration(border: border),
        child: body,
      );
    }
    return body;
  }
}

class _ClassHeader extends StatelessWidget {
  const _ClassHeader({
    required this.arrangement,
    required this.title,
    this.isOffer = false,
  });

  final ArrangementBlock arrangement;
  final String title;
  final bool isOffer;

  @override
  Widget build(BuildContext context) {
    final a = arrangement;
    final style = BoardFonts.apply(
      a.classFontName,
      TextStyle(
        color: QbColors.of(a.classForeColor),
        fontSize: a.classFontSize.toDouble(),
        fontWeight: a.classBold ? FontWeight.w800 : FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
    return ColoredBox(
      color: QbColors.of(a.classBackColor),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            if (isOffer)
              Text(
                'SPECIAL',
                textAlign: TextAlign.center,
                style: style.copyWith(
                  fontSize: (a.classFontSize * 0.45).clamp(9, 18),
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: style,
            ),
          ],
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
    final style = BoardFonts.apply(
      a.itemFontName,
      TextStyle(
        color: QbColors.of(a.itemForeColor),
        fontSize: a.itemFontSize.toDouble(),
        fontWeight: a.itemBold ? FontWeight.w700 : FontWeight.w500,
        height: 1.15,
      ),
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
    final style = BoardFonts.apply(
      a.modifierFontName,
      TextStyle(
        color: QbColors.of(a.modifierColor),
        fontSize: a.modifierFontSize.toDouble().clamp(8, 48),
        fontStyle: FontStyle.italic,
        height: 1.2,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 48),
      child: Text(text, style: style),
    );
  }
}

class BillboardPicturePanel extends StatelessWidget {
  const BillboardPicturePanel({
    super.key,
    required this.block,
    this.fit,
  });

  final PictureBlock block;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    final a = block.arrangement;
    final resolvedFit = fit ?? a.mediaBoxFit;
    final opacity = a.clampedMediaOpacity;
    final border = a.decorationBorder;

    Widget child;
    if (a.mediaType == ArrangementMediaType.video) {
      final path = a.resolvedVideoPath;
      if (path.isEmpty) {
        child = const ColoredBox(
          color: Color(0x33000000),
          child: Center(
            child: Icon(Icons.videocam_outlined, color: Colors.white54, size: 40),
          ),
        );
      } else {
        child = BillboardVideoPanel(
          key: ValueKey('vid-${a.id}-$path-${a.videoLoop}-${a.videoMuted}'),
          path: path,
          fit: resolvedFit,
          loop: a.videoLoop,
          muted: a.videoMuted,
        );
      }
    } else {
      child = _image(resolvedFit);
    }

    if (opacity < 0.999) {
      child = Opacity(opacity: opacity, child: child);
    }
    if (border != null) {
      child = DecoratedBox(
        decoration: BoxDecoration(border: border),
        child: child,
      );
    }
    return child;
  }

  Widget _image(BoxFit fit) {
    final bytes = block.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: _err,
      );
    }

    final path = block.route.isNotEmpty
        ? block.route
        : block.arrangement.mediaFile;
    if (path.isEmpty) {
      return const ColoredBox(
        color: Color(0x33000000),
        child: Center(
          child: Icon(Icons.image_outlined, color: Colors.white54, size: 40),
        ),
      );
    }

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: _err,
      );
    }

    final file = File(path);
    if (!file.existsSync()) {
      return _MissingPic(path: path);
    }
    return Image.file(
      file,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: _err,
    );
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
