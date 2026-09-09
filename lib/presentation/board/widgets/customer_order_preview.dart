import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:camaleon_billboard/core/theme/camaleon_theme.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';

final _orderMoney = NumberFormat.currency(symbol: '\$');

String _fmtMoney(double v) => _orderMoney.format(v);

String _fmtQty(double qty) {
  if (qty == qty.roundToDouble()) return '${qty.round()}';
  return qty.toStringAsFixed(2);
}

/// Compact preview for the Style sidebar.
class CustomerOrderSidebarPreview extends StatelessWidget {
  const CustomerOrderSidebarPreview({
    super.key,
    this.orders = const [],
  });

  final List<CustomerOrderTicket> orders;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Text(
        'No open tickets right now',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 12,
        ),
      );
    }
    final shown = orders.take(3).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _OrderTicketCard(
            ticket: shown[i].label,
            lines: shown[i].lines,
            total: shown[i].total,
            compact: true,
          ),
        ],
      ],
    );
  }
}

/// Side column for Customer display — sits beside the menu board (no overlay).
class CustomerOrderBoardPanel extends StatelessWidget {
  const CustomerOrderBoardPanel({
    super.key,
    this.width = 320,
    this.orders = const [],
  });

  final double width;
  final List<CustomerOrderTicket> orders;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: const Color(0xFF0B1220),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: CamaleonColors.green,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: const Text(
                'YOUR ORDER',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Expanded(
              child: orders.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Waiting for open tickets…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      children: [
                        for (var i = 0; i < orders.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _OrderTicketCard(
                            ticket: orders[i].label,
                            lines: orders[i].lines,
                            total: orders[i].total,
                            compact: false,
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderTicketCard extends StatelessWidget {
  const _OrderTicketCard({
    required this.ticket,
    required this.lines,
    required this.total,
    required this.compact,
  });

  final String ticket;
  final List<CustomerOrderLine> lines;
  final double total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: compact ? 0.06 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ticket,
                  style: TextStyle(
                    color: CamaleonColors.greenSoft,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 13 : 15,
                  ),
                ),
              ),
              Text(
                _fmtMoney(total),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 13 : 15,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: compact ? 28 : 32,
                    child: Text(
                      '${_fmtQty(line.qty)}×',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 12 : 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 12 : 14,
                        height: 1.25,
                      ),
                    ),
                  ),
                  Text(
                    _fmtMoney(line.lineTotal),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: compact ? 12 : 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
