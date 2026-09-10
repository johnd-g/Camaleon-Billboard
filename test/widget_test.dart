import 'package:flutter_test/flutter_test.dart';

import 'package:camaleon_billboard/core/db/db_connection_qr.dart';
import 'package:camaleon_billboard/core/utils/board_rotation.dart';
import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';

void main() {
  test('DbConnectionQr parses classic payload', () {
    final qr = DbConnectionQr.parse(
      '__cmlnconn__:192.168.1.10:3306:root:s:ecret:camaleon',
    );
    expect(qr, isNotNull);
    expect(qr!.host, '192.168.1.10');
    expect(qr.port, 3306);
    expect(qr.user, 'root');
    expect(qr.password, 's:ecret');
    expect(qr.database, 'camaleon');
  });

  test('range_items parses LIMIT offset-count', () {
    const block = ArrangementBlock(
      id: 1,
      compName: 'PC1',
      rangeItems: '0-12',
    );
    final (offset, count) = block.rangeLimit;
    expect(offset, 0);
    expect(count, 12);
  });

  test('applyRange skips and takes items', () {
    const block = ArrangementBlock(
      id: 1,
      compName: 'PC1',
      rangeItems: '4-6',
    );
    final items = List<int>.generate(10, (i) => i + 1);
    expect(block.applyRange(items), [5, 6, 7, 8, 9, 10]);
  });

  test('BoardRotation playlist sorts by display_order', () {
    const board = BillboardBoard(
      compName: 'TV1',
      sections: [
        MenuSection(
          arrangement: ArrangementBlock(
            id: 2,
            compName: 'TV1',
            displayOrder: 20,
            displaySeconds: 8,
          ),
          className: 'B',
          items: [],
        ),
        MenuSection(
          arrangement: ArrangementBlock(
            id: 1,
            compName: 'TV1',
            displayOrder: 10,
            displaySeconds: 5,
            contentType: ArrangementContentType.offer,
            offerId: 3,
          ),
          className: 'A',
          items: [],
        ),
        MenuSection(
          arrangement: ArrangementBlock(
            id: 3,
            compName: 'TV1',
            displayOrder: 5,
            displaySeconds: 0,
          ),
          className: 'Static',
          items: [],
        ),
      ],
      pictures: [
        PictureBlock(
          arrangement: ArrangementBlock(
            id: 9,
            compName: 'TV1',
            displayOrder: 15,
            displaySeconds: 6,
            usePicture: true,
          ),
        ),
      ],
    );

    final playlist = BoardRotation.playlist(board);
    expect(playlist.map((a) => a.id).toList(), [1, 9, 2]);

    expect(
      BoardRotation.isVisible(
        playlist.first,
        editing: false,
        previewRotation: false,
        activeRotationId: 1,
        hasRotationPlaylist: true,
      ),
      isTrue,
    );
    expect(
      BoardRotation.isVisible(
        playlist.last,
        editing: false,
        previewRotation: false,
        activeRotationId: 1,
        hasRotationPlaylist: true,
      ),
      isFalse,
    );
    expect(
      BoardRotation.isVisible(
        board.sections[2].arrangement,
        editing: false,
        previewRotation: false,
        activeRotationId: 1,
        hasRotationPlaylist: true,
      ),
      isTrue,
    );
    expect(
      BoardRotation.isVisible(
        playlist.last,
        editing: true,
        previewRotation: false,
        activeRotationId: 1,
        hasRotationPlaylist: true,
      ),
      isTrue,
    );
    expect(
      BoardRotation.isVisible(
        playlist.last,
        editing: true,
        previewRotation: true,
        activeRotationId: 1,
        hasRotationPlaylist: true,
      ),
      isFalse,
    );
  });
}
