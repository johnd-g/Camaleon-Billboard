import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:camaleon_billboard/core/theme/camaleon_theme.dart';
import 'package:camaleon_billboard/domain/entities/menu_section.dart';
import 'package:camaleon_billboard/presentation/billboard_controller.dart';
import 'package:camaleon_billboard/presentation/live_order/live_order_controller.dart';
import 'package:camaleon_billboard/presentation/live_order/live_order_page.dart';

final _orderMoney = NumberFormat.currency(symbol: '\$');

String _fmtMoney(double v) => _orderMoney.format(v);

String _fmtQty(double qty) {
  if (qty == qty.roundToDouble()) return '${qty.round()}';
  return qty.toStringAsFixed(2);
}

/// Placeholder tickets shown only when Live order is not configured.
const kSampleCustomerOrders = <CustomerOrderTicket>[
  CustomerOrderTicket(
    cuentaId: 1042,
    label: 'Orden #1042',
    total: 7.25,
    lines: [
      CustomerOrderLine(qty: 2, name: 'Taco Pastor', unitPrice: 1.5),
      CustomerOrderLine(qty: 1, name: 'Taco Asada', unitPrice: 1.75),
      CustomerOrderLine(qty: 1, name: 'Agua Fresca', unitPrice: 2.5),
    ],
  ),
  CustomerOrderTicket(
    cuentaId: 1043,
    label: 'Orden #1043',
    total: 11.24,
    lines: [
      CustomerOrderLine(qty: 1, name: 'Desayuno Chilaquiles', unitPrice: 8.99),
      CustomerOrderLine(qty: 1, name: 'Café', unitPrice: 2.25),
    ],
  ),
];

/// Compact preview for the Style sidebar.
class CustomerOrderSidebarPreview extends StatelessWidget {
  const CustomerOrderSidebarPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveOrderController>();
    if (live.config.isReady) {
      if (!live.showCustomerTicket) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Hidden while order is empty',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 520,
          child: Material(
            color: receiptSurface(
              context.select((BillboardController c) => c.poleDisplayDarkMode),
            ),
            child: const LiveOrderTicketView(
              compact: false,
              showHeaderTitle: true,
              customerDisplay: true,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < kSampleCustomerOrders.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _OrderTicketCard(
            ticket: kSampleCustomerOrders[i].label,
            lines: kSampleCustomerOrders[i].lines,
            total: kSampleCustomerOrders[i].total,
            compact: true,
          ),
        ],
      ],
    );
  }
}

/// Side column for Customer display — sits beside the menu board (no overlay).
class CustomerOrderBoardPanel extends StatelessWidget {
  const CustomerOrderBoardPanel({super.key, this.width = 320});

  final double width;

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveOrderController>();

    // Live order configured but ticket empty → hide panel (board fills width).
    if (live.config.isReady && !live.showCustomerTicket) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: width,
      child: Material(
        color: receiptSurface(
          context.select((BillboardController c) => c.poleDisplayDarkMode),
        ),
        child: live.config.isReady
            ? const LiveOrderTicketView(compact: false, customerDisplay: true)
            : _SampleOrdersColumn(),
      ),
    );
  }
}

class _SampleOrdersColumn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: CamaleonColors.green,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: const Text(
            'CUSTOMER DISPLAY',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            children: [
              for (var i = 0; i < kSampleCustomerOrders.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _OrderTicketCard(
                  ticket: kSampleCustomerOrders[i].label,
                  lines: kSampleCustomerOrders[i].lines,
                  total: kSampleCustomerOrders[i].total,
                  compact: false,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Set POS IP in Settings → Live order',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
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
