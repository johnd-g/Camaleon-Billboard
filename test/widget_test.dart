import 'package:flutter_test/flutter_test.dart';

import 'package:camaleon_billboard/core/db/db_connection_qr.dart';
import 'package:camaleon_billboard/domain/entities/arrangement_block.dart';

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
}
