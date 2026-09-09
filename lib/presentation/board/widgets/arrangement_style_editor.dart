import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:camaleon_billboard/core/theme/camaleon_theme.dart';
import 'package:camaleon_billboard/core/utils/board_fonts.dart';
import 'package:camaleon_billboard/core/utils/qb_color.dart';
import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';

typedef StylePatch = void Function({
  int? classFontDelta,
  int? itemFontDelta,
  int? modifierFontSize,
  int? classForeColor,
  int? classBackColor,
  int? itemForeColor,
  int? itemBackColor,
  int? mainBackColor,
  int? modifierColor,
  bool? classBold,
  bool? itemBold,
  bool? classUpperCase,
  bool? itemUpperCase,
  bool? boardBackground,
  int? maxWidth,
  String? classFontName,
  String? itemFontName,
  String? modifierFontName,
  ArrangementContentType? contentType,
  int? offerId,
  ArrangementMediaType? mediaType,
  String? mediaFile,
  ArrangementMediaFit? mediaFit,
  double? mediaOpacity,
  int? displayOrder,
  int? displaySeconds,
  int? borderWidth,
  String? borderColor,
  bool? videoLoop,
  bool? videoMuted,
});

/// Full `bb_arrangement` style controls for the selected block / board.
class ArrangementStyleEditor extends StatelessWidget {
  const ArrangementStyleEditor({
    super.key,
    required this.boardMainBackColor,
    required this.onBoardBackgroundColor,
    required this.onPatch,
    this.section,
    this.picture,
    this.compact = false,
    this.multipleBoardBackgrounds = false,
    this.backgroundPreviewBytes,
    this.backgroundMediaType = ArrangementMediaType.none,
    this.backgroundMediaFile = '',
    this.uploadingBackground = false,
    this.onPickBackgroundImage,
    this.onPickBackgroundVideo,
    this.onClearBackgroundImage,
    this.onBrowseMediaFile,
  });

  final int boardMainBackColor;
  final ValueChanged<int> onBoardBackgroundColor;
  final StylePatch onPatch;
  final MenuSection? section;
  final PictureBlock? picture;
  final bool compact;
  final bool multipleBoardBackgrounds;
  final Uint8List? backgroundPreviewBytes;
  final ArrangementMediaType backgroundMediaType;
  final String backgroundMediaFile;
  final bool uploadingBackground;
  final VoidCallback? onPickBackgroundImage;
  final VoidCallback? onPickBackgroundVideo;
  final VoidCallback? onClearBackgroundImage;
  final VoidCallback? onBrowseMediaFile;

  @override
  Widget build(BuildContext context) {
    final a = section?.arrangement ?? picture?.arrangement;
    final hasBgImage =
        backgroundPreviewBytes != null && backgroundPreviewBytes!.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Label('Board background'),
              const SizedBox(height: 8),
              _ColorSwatches(
                value: boardMainBackColor,
                onChanged: onBoardBackgroundColor,
              ),
              const SizedBox(height: 12),
              const _Label('Background media'),
              const SizedBox(height: 8),
              if (hasBgImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.memory(
                      backgroundPreviewBytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                )
              else if (backgroundMediaType == ArrangementMediaType.video &&
                  backgroundMediaFile.isNotEmpty)
                Container(
                  height: 72,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.videocam_rounded,
                          color: Colors.white70, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          backgroundMediaFile,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    'No media · solid color only',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: uploadingBackground
                          ? null
                          : onPickBackgroundImage,
                      icon: uploadingBackground
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              hasBgImage
                                  ? Icons.photo_library_outlined
                                  : Icons.add_photo_alternate_outlined,
                              size: 18,
                            ),
                      label: Text(hasBgImage ? 'Change image' : 'Image'),
                      style: FilledButton.styleFrom(
                        backgroundColor: CamaleonColors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: uploadingBackground
                          ? null
                          : onPickBackgroundVideo,
                      icon: const Icon(Icons.videocam_outlined, size: 18),
                      label: Text(
                        backgroundMediaType == ArrangementMediaType.video
                            ? 'Change video'
                            : 'Video',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white12,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if ((hasBgImage ||
                          backgroundMediaType ==
                              ArrangementMediaType.video) &&
                      onClearBackgroundImage != null) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Remove background media',
                      onPressed:
                          uploadingBackground ? null : onClearBackgroundImage,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white12,
                        foregroundColor: Colors.white70,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Image → bb_pic blob. Video → media_file path (loops behind the menu).',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              if (multipleBoardBackgrounds) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0x33F59E0B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x99F59E0B)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFFBBF24), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'More than one photo is marked as board background. '
                          'Only one is allowed — turn the extras off.',
                          style: TextStyle(
                            color: Color(0xFFFFE7A3),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (a == null) ...[
          const SizedBox(height: 10),
          _Card(
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  color: CamaleonColors.greenSoft.withValues(alpha: 0.9),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tap a menu section or photo to edit size, colors, and type.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 10),
          _blockHeader(
            section?.className ??
                (picture!.arrangement.screenName.isEmpty
                    ? 'Photo #${picture!.arrangement.id}'
                    : picture!.arrangement.screenName),
            isPhoto: picture != null,
          ),
          if (picture != null) ...[
            const SizedBox(height: 8),
            _BackgroundToggle(
              value: a.isBoardBackground,
              onChanged: (v) => onPatch(boardBackground: v),
            ),
            if (!a.isBoardBackground) ...[
              const SizedBox(height: 8),
              _StepperRow(
                icon: Icons.swap_horiz_rounded,
                label: 'Width',
                valueLabel: '${a.maxWidth}',
                unit: 'px',
                onMinus: () => onPatch(maxWidth: a.maxWidth - 20),
                onPlus: () => onPatch(maxWidth: a.maxWidth + 20),
                onMinusBig: () => onPatch(maxWidth: a.maxWidth - 100),
                onPlusBig: () => onPatch(maxWidth: a.maxWidth + 100),
              ),
            ],
            const SizedBox(height: 8),
            _MediaControls(
              arrangement: a,
              onPatch: onPatch,
              onBrowseMediaFile: onBrowseMediaFile,
              browsing: uploadingBackground,
            ),
          ],
          if (section != null) ...[
            const SizedBox(height: 8),
            _ContentTypeCard(
              arrangement: a,
              onPatch: onPatch,
            ),
            const SizedBox(height: 8),
            _BorderControls(
              arrangement: a,
              onPatch: onPatch,
            ),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                children: [
                  _StepperRow(
                    icon: Icons.title_rounded,
                    label: 'Header',
                    valueLabel: '${a.classFontSize}',
                    unit: 'px',
                    onMinus: () => onPatch(classFontDelta: -1),
                    onPlus: () => onPatch(classFontDelta: 1),
                    onMinusBig: () => onPatch(classFontDelta: -4),
                    onPlusBig: () => onPatch(classFontDelta: 4),
                    embedded: true,
                  ),
                  const _Divider(),
                  _StepperRow(
                    icon: Icons.format_list_bulleted_rounded,
                    label: 'Items',
                    valueLabel: '${a.itemFontSize}',
                    unit: 'px',
                    onMinus: () => onPatch(itemFontDelta: -1),
                    onPlus: () => onPatch(itemFontDelta: 1),
                    onMinusBig: () => onPatch(itemFontDelta: -4),
                    onPlusBig: () => onPatch(itemFontDelta: 4),
                    embedded: true,
                  ),
                  const _Divider(),
                  _StepperRow(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Width',
                    valueLabel: '${a.maxWidth}',
                    unit: 'px',
                    onMinus: () => onPatch(maxWidth: a.maxWidth - 20),
                    onPlus: () => onPatch(maxWidth: a.maxWidth + 20),
                    onMinusBig: () => onPatch(maxWidth: a.maxWidth - 100),
                    onPlusBig: () => onPatch(maxWidth: a.maxWidth + 100),
                    embedded: true,
                  ),
                  const _Divider(),
                  _StepperRow(
                    icon: Icons.notes_rounded,
                    label: 'Description',
                    valueLabel: '${a.modifierFontSize}',
                    unit: 'px',
                    onMinus: () =>
                        onPatch(modifierFontSize: a.modifierFontSize - 1),
                    onPlus: () =>
                        onPatch(modifierFontSize: a.modifierFontSize + 1),
                    onMinusBig: () =>
                        onPatch(modifierFontSize: a.modifierFontSize - 4),
                    onPlusBig: () =>
                        onPatch(modifierFontSize: a.modifierFontSize + 4),
                    embedded: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label('Header'),
                  const SizedBox(height: 8),
                  _TwinColors(
                    leftLabel: 'Text',
                    leftValue: a.classForeColor,
                    onLeft: (v) => onPatch(classForeColor: v),
                    rightLabel: 'Fill',
                    rightValue: a.classBackColor,
                    onRight: (v) => onPatch(classBackColor: v),
                    rightAllowTransparent: true,
                  ),
                  const SizedBox(height: 14),
                  const _Label('Items'),
                  const SizedBox(height: 8),
                  _TwinColors(
                    leftLabel: 'Text',
                    leftValue: a.itemForeColor,
                    onLeft: (v) => onPatch(itemForeColor: v),
                    rightLabel: 'Fill',
                    rightValue: a.itemBackColor,
                    onRight: (v) => onPatch(itemBackColor: v),
                    rightAllowTransparent: true,
                  ),
                  const SizedBox(height: 14),
                  const _Label('Description text'),
                  const SizedBox(height: 8),
                  _ColorSwatches(
                    value: a.modifierColor,
                    onChanged: (v) => onPatch(modifierColor: v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label('Fonts'),
                  const SizedBox(height: 8),
                  _FontPicker(
                    label: 'Header',
                    value: a.classFontName,
                    onChanged: (v) => onPatch(classFontName: v),
                  ),
                  const SizedBox(height: 8),
                  _FontPicker(
                    label: 'Items',
                    value: a.itemFontName,
                    onChanged: (v) => onPatch(itemFontName: v),
                  ),
                  const SizedBox(height: 8),
                  _FontPicker(
                    label: 'Description',
                    value: a.modifierFontName,
                    onChanged: (v) => onPatch(modifierFontName: v),
                  ),
                  const SizedBox(height: 12),
                  const _Label('Type'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _StyleToggle(
                          label: 'Header bold',
                          value: a.classBold,
                          onChanged: (v) => onPatch(classBold: v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StyleToggle(
                          label: 'Items bold',
                          value: a.itemBold,
                          onChanged: (v) => onPatch(itemBold: v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _StyleToggle(
                          label: 'HEADER caps',
                          value: a.classUpperCase,
                          onChanged: (v) => onPatch(classUpperCase: v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StyleToggle(
                          label: 'ITEMS caps',
                          value: a.itemUpperCase,
                          onChanged: (v) => onPatch(itemUpperCase: v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 12),
              Text(
                'Position  ·  X ${a.xDistance}   Y ${a.yDistance}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 11,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }

  Widget _blockHeader(String name, {required bool isPhoto}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: CamaleonColors.green,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isPhoto ? 'Photo' : 'Section',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _BackgroundToggle extends StatelessWidget {
  const _BackgroundToggle({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value
          ? CamaleonColors.green.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value ? CamaleonColors.green : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.wallpaper_rounded,
                color: value ? CamaleonColors.greenSoft : Colors.white54,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fill whole board',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Stretch this photo behind the menu',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                activeThumbColor: Colors.white,
                activeTrackColor: CamaleonColors.green,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContentTypeCard extends StatelessWidget {
  const _ContentTypeCard({
    required this.arrangement,
    required this.onPatch,
  });

  final ArrangementBlock arrangement;
  final StylePatch onPatch;

  @override
  Widget build(BuildContext context) {
    final a = arrangement;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Label('Content type'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final t in ArrangementContentType.values) ...[
                if (t != ArrangementContentType.values.first)
                  const SizedBox(width: 8),
                Expanded(
                  child: _StyleToggle(
                    label: t.dbValue,
                    value: a.contentType == t,
                    onChanged: (_) => onPatch(contentType: t),
                  ),
                ),
              ],
            ],
          ),
          if (a.contentType == ArrangementContentType.offer) ...[
            const SizedBox(height: 10),
            _StepperRow(
              icon: Icons.local_offer_outlined,
              label: 'Offer ID',
              valueLabel: '${a.offerId}',
              unit: '',
              onMinus: () => onPatch(offerId: a.offerId - 1),
              onPlus: () => onPatch(offerId: a.offerId + 1),
              onMinusBig: () => onPatch(offerId: a.offerId - 10),
              onPlusBig: () => onPatch(offerId: a.offerId + 10),
              embedded: true,
            ),
            const SizedBox(height: 4),
            Text(
              'dates_special / day_specials id from POS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _StepperRow(
            icon: Icons.reorder_rounded,
            label: 'Order',
            valueLabel: '${a.displayOrder}',
            unit: '',
            onMinus: () => onPatch(displayOrder: a.displayOrder - 1),
            onPlus: () => onPatch(displayOrder: a.displayOrder + 1),
            onMinusBig: () => onPatch(displayOrder: a.displayOrder - 5),
            onPlusBig: () => onPatch(displayOrder: a.displayOrder + 5),
            embedded: true,
          ),
          const _Divider(),
          _StepperRow(
            icon: Icons.timer_outlined,
            label: 'Seconds',
            valueLabel: '${a.displaySeconds}',
            unit: 's',
            onMinus: () => onPatch(displaySeconds: a.displaySeconds - 1),
            onPlus: () => onPatch(displaySeconds: a.displaySeconds + 1),
            onMinusBig: () => onPatch(displaySeconds: a.displaySeconds - 5),
            onPlusBig: () => onPatch(displaySeconds: a.displaySeconds + 5),
            embedded: true,
          ),
        ],
      ),
    );
  }
}

class _MediaControls extends StatelessWidget {
  const _MediaControls({
    required this.arrangement,
    required this.onPatch,
    this.onBrowseMediaFile,
    this.browsing = false,
  });

  final ArrangementBlock arrangement;
  final StylePatch onPatch;
  final VoidCallback? onBrowseMediaFile;
  final bool browsing;

  @override
  Widget build(BuildContext context) {
    final a = arrangement;
    final opacityPct = (a.clampedMediaOpacity * 100).round();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Label('Media'),
          const SizedBox(height: 8),
          Text(
            'Type',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final t in ArrangementMediaType.values) ...[
                if (t != ArrangementMediaType.values.first)
                  const SizedBox(width: 6),
                Expanded(
                  child: _StyleToggle(
                    label: t.dbValue,
                    value: a.mediaType == t,
                    onChanged: (_) => onPatch(mediaType: t),
                  ),
                ),
              ],
            ],
          ),
          if (a.mediaType != ArrangementMediaType.none) ...[
            const SizedBox(height: 10),
            _MediaFileField(
              value: a.mediaFile,
              browsing: browsing,
              onChanged: (v) => onPatch(mediaFile: v),
              onBrowse: onBrowseMediaFile,
              isVideo: a.mediaType == ArrangementMediaType.video,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Fit',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final f in ArrangementMediaFit.values) ...[
                if (f != ArrangementMediaFit.values.first)
                  const SizedBox(width: 6),
                Expanded(
                  child: _StyleToggle(
                    label: f.dbValue,
                    value: a.mediaFit == f,
                    onChanged: (_) => onPatch(mediaFit: f),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _StepperRow(
            icon: Icons.opacity_rounded,
            label: 'Opacity',
            valueLabel: '$opacityPct',
            unit: '%',
            onMinus: () => onPatch(mediaOpacity: a.mediaOpacity - 0.05),
            onPlus: () => onPatch(mediaOpacity: a.mediaOpacity + 0.05),
            onMinusBig: () => onPatch(mediaOpacity: a.mediaOpacity - 0.15),
            onPlusBig: () => onPatch(mediaOpacity: a.mediaOpacity + 0.15),
            embedded: true,
          ),
          const _Divider(),
          _StepperRow(
            icon: Icons.reorder_rounded,
            label: 'Order',
            valueLabel: '${a.displayOrder}',
            unit: '',
            onMinus: () => onPatch(displayOrder: a.displayOrder - 1),
            onPlus: () => onPatch(displayOrder: a.displayOrder + 1),
            onMinusBig: () => onPatch(displayOrder: a.displayOrder - 5),
            onPlusBig: () => onPatch(displayOrder: a.displayOrder + 5),
            embedded: true,
          ),
          const _Divider(),
          _StepperRow(
            icon: Icons.timer_outlined,
            label: 'Seconds',
            valueLabel: '${a.displaySeconds}',
            unit: 's',
            onMinus: () => onPatch(displaySeconds: a.displaySeconds - 1),
            onPlus: () => onPatch(displaySeconds: a.displaySeconds + 1),
            onMinusBig: () => onPatch(displaySeconds: a.displaySeconds - 5),
            onPlusBig: () => onPatch(displaySeconds: a.displaySeconds + 5),
            embedded: true,
          ),
          if (a.mediaType == ArrangementMediaType.video) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StyleToggle(
                    label: 'Loop',
                    value: a.videoLoop,
                    onChanged: (v) => onPatch(videoLoop: v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StyleToggle(
                    label: 'Muted',
                    value: a.videoMuted,
                    onChanged: (v) => onPatch(videoMuted: v),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _BorderControls(arrangement: a, onPatch: onPatch, embedded: true),
        ],
      ),
    );
  }
}

class _MediaFileField extends StatefulWidget {
  const _MediaFileField({
    required this.value,
    required this.onChanged,
    this.onBrowse,
    this.browsing = false,
    this.isVideo = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onBrowse;
  final bool browsing;
  final bool isVideo;

  @override
  State<_MediaFileField> createState() => _MediaFileFieldState();
}

class _MediaFileFieldState extends State<_MediaFileField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _MediaFileField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.isVideo ? 'Video file' : 'Image file',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                cursorColor: CamaleonColors.greenSoft,
                decoration: InputDecoration(
                  hintText: widget.isVideo
                      ? 'path/video.mp4'
                      : 'path/image.jpg',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: CamaleonColors.green),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: widget.onChanged,
                onSubmitted: widget.onChanged,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: FilledButton.tonalIcon(
                onPressed: widget.browsing ? null : widget.onBrowse,
                icon: widget.browsing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Browse'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          widget.isVideo
              ? 'Browse opens the system file picker. Path is saved in media_file.'
              : 'Browse saves the image in bb_pic and the name in media_file.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _BorderControls extends StatelessWidget {
  const _BorderControls({
    required this.arrangement,
    required this.onPatch,
    this.embedded = false,
  });

  final ArrangementBlock arrangement;
  final StylePatch onPatch;
  final bool embedded;

  int get _width {
    final a = arrangement;
    return [
      a.borderTopWidth,
      a.borderRightWidth,
      a.borderBottomWidth,
      a.borderLeftWidth,
    ].fold<int>(0, (m, v) => v > m ? v : m);
  }

  int get _colorIndex {
    final raw = arrangement.borderTopColor.trim().isNotEmpty
        ? arrangement.borderTopColor
        : arrangement.borderLeftColor;
    return int.tryParse(raw.trim()) ?? 15;
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!embedded) ...[
          const _Label('Border'),
          const SizedBox(height: 8),
        ] else ...[
          Text(
            'Border',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        _StepperRow(
          icon: Icons.border_outer_rounded,
          label: 'Width',
          valueLabel: '$_width',
          unit: 'px',
          onMinus: () => onPatch(borderWidth: _width - 1),
          onPlus: () => onPatch(borderWidth: _width + 1),
          onMinusBig: () => onPatch(borderWidth: _width - 4),
          onPlusBig: () => onPatch(borderWidth: _width + 4),
          embedded: true,
        ),
        const SizedBox(height: 8),
        _ColorSwatches(
          value: _colorIndex.clamp(0, 15),
          onChanged: (v) => onPatch(borderColor: '$v'),
          dense: true,
        ),
      ],
    );
    if (embedded) return body;
    return _Card(child: body);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withValues(alpha: 0.06),
      ),
    );
  }
}

class _TwinColors extends StatelessWidget {
  const _TwinColors({
    required this.leftLabel,
    required this.leftValue,
    required this.onLeft,
    required this.rightLabel,
    required this.rightValue,
    required this.onRight,
    this.rightAllowTransparent = false,
  });

  final String leftLabel;
  final int leftValue;
  final ValueChanged<int> onLeft;
  final String rightLabel;
  final int rightValue;
  final ValueChanged<int> onRight;
  final bool rightAllowTransparent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                leftLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _ColorSwatches(value: leftValue, onChanged: onLeft, dense: true),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rightLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _ColorSwatches(
                value: rightValue,
                onChanged: onRight,
                dense: true,
                allowTransparent: rightAllowTransparent,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({
    required this.value,
    required this.onChanged,
    this.dense = false,
    this.allowTransparent = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool dense;
  final bool allowTransparent;

  @override
  Widget build(BuildContext context) {
    final size = dense ? 20.0 : 24.0;
    final indices = <int>[
      if (allowTransparent) QbColors.transparentIndex,
      for (var i = 0; i < QbColors.palette.length; i++) i,
    ];
    return Wrap(
      spacing: dense ? 5 : 6,
      runSpacing: dense ? 5 : 6,
      children: [
        for (final i in indices)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: value == i ? CamaleonColors.greenSoft : Colors.white24,
                  width: value == i ? 2.5 : 1,
                ),
                boxShadow: value == i
                    ? [
                        BoxShadow(
                          color: CamaleonColors.green.withValues(alpha: 0.45),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
              child: ClipOval(
                child: QbColors.isTransparent(i)
                    ? const CustomPaint(
                        painter: _CheckerPainter(),
                        child: Center(
                          child: Icon(
                            Icons.block,
                            size: 11,
                            color: Colors.white54,
                          ),
                        ),
                      )
                    : ColoredBox(color: QbColors.of(i)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Checkerboard swatch for transparent fills.
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const a = Color(0xFF3A4555);
    const b = Color(0xFF1E2633);
    const n = 3;
    final w = size.width / n;
    final h = size.height / n;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final paint = Paint()..color = ((x + y).isEven ? a : b);
        canvas.drawRect(Rect.fromLTWH(x * w, y * h, w + 0.5, h + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
    required this.onMinusBig,
    required this.onPlusBig,
    this.embedded = false,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final String unit;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onMinusBig;
  final VoidCallback onPlusBig;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Icon(icon, size: 18, color: CamaleonColors.greenSoft),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        _HoldBtn(icon: Icons.remove_rounded, onTap: onMinus, onHold: onMinusBig),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            width: 58,
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _HoldBtn(icon: Icons.add_rounded, onTap: onPlus, onHold: onPlusBig),
      ],
    );

    if (embedded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: row,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: row,
    );
  }
}

/// Tap = small step; hold = big jumps.
class _HoldBtn extends StatefulWidget {
  const _HoldBtn({
    required this.icon,
    required this.onTap,
    required this.onHold,
  });

  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onHold;

  @override
  State<_HoldBtn> createState() => _HoldBtnState();
}

class _HoldBtnState extends State<_HoldBtn> {
  int _holdGen = 0;
  bool _didHold = false;

  Future<void> _beginHold() async {
    final gen = ++_holdGen;
    _didHold = false;
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (!mounted || gen != _holdGen) return;
    _didHold = true;
    while (mounted && gen == _holdGen) {
      HapticFeedback.selectionClick();
      widget.onHold();
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
  }

  void _endHold() => _holdGen++;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white12,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTapDown: (_) => _beginHold(),
        onTapCancel: _endHold,
        onTap: () {
          final held = _didHold;
          _endHold();
          if (held) return;
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(widget.icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _FontPicker extends StatelessWidget {
  const _FontPicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = BoardFonts.normalizeId(value);
    final known = BoardFonts.options.any((o) => o.id == current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: BoardFonts.options.length + (known ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final option = i < BoardFonts.options.length
                  ? BoardFonts.options[i]
                  : BoardFontOption(
                      id: current,
                      label: BoardFonts.labelFor(current),
                      sample: 'Aa',
                    );
              final selected = option.id.toLowerCase() == current.toLowerCase();
              final preview = BoardFonts.apply(
                option.id,
                TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              );
              return Material(
                color: selected
                    ? CamaleonColors.green.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(option.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? CamaleonColors.green : Colors.white24,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(option.sample, style: preview),
                        const SizedBox(width: 6),
                        Text(
                          option.label,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StyleToggle extends StatelessWidget {
  const _StyleToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value
          ? CamaleonColors.green.withValues(alpha: 0.28)
          : Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        child: Container(
          height: 42,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: value ? CamaleonColors.green : Colors.white24,
              width: value ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (value) ...[
                const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: value ? Colors.white : Colors.white70,
                    fontWeight: value ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
