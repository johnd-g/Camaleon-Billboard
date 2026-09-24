import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:camaleon_billboard/core/theme/camaleon_theme.dart';
import 'package:camaleon_billboard/domain/entities/live_order.dart';
import 'package:camaleon_billboard/presentation/live_order/live_order_controller.dart';

final _liveMoney = NumberFormat.currency(symbol: '\$');

String _fmtMoney(double v) => _liveMoney.format(v);

String _fmtQty(double qty) {
  if (qty == qty.roundToDouble()) return '${qty.round()}';
  return qty.toStringAsFixed(2);
}

/// Full-screen Live order (no MySQL required).
class LiveOrderPage extends StatelessWidget {
  const LiveOrderPage({super.key, this.showBack = true});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final busy = context.select((LiveOrderController c) => c.actionBusy);
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              child: Row(
                children: [
                  if (showBack)
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white70,
                      ),
                    )
                  else
                    const SizedBox(width: 8),
                  const Spacer(),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () =>
                              context.read<LiveOrderController>().publishTest(),
                    child: Text(
                      'Test',
                      style: TextStyle(
                        color: busy ? Colors.white24 : CamaleonColors.greenSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () =>
                              context.read<LiveOrderController>().clearOrder(),
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        color: busy ? Colors.white24 : Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: LiveOrderTicketView(compact: false)),
          ],
        ),
      ),
    );
  }
}

/// Ticket body used by the full-screen page and the customer-display side panel.
class LiveOrderTicketView extends StatelessWidget {
  const LiveOrderTicketView({
    super.key,
    this.compact = false,
    this.showHeaderTitle = true,
    this.customerDisplay = false,
  });

  final bool compact;
  final bool showHeaderTitle;

  /// Board side panel: fixed "Customer display" branding (no TEST ORDER banner).
  final bool customerDisplay;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveOrderController>();
    final snap = c.snapshot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          compact: compact,
          showTitle: showHeaderTitle,
          customerDisplay: customerDisplay,
          tableName: snap?.tableName ?? '',
          registerName: snap?.registerName ?? '',
          isTest: snap?.isTest == true,
          phase: c.phase,
        ),
        Expanded(
          child: _Body(
            controller: c,
            compact: compact,
            customerDisplay: customerDisplay,
          ),
        ),
        _Footer(
          compact: compact,
          customerDisplay: customerDisplay,
          totals: snap?.totals,
          showTotals: snap != null && snap.hasItems,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.compact,
    required this.showTitle,
    required this.customerDisplay,
    required this.tableName,
    required this.registerName,
    required this.isTest,
    required this.phase,
  });

  final bool compact;
  final bool showTitle;
  final bool customerDisplay;
  final String tableName;
  final String registerName;
  final bool isTest;
  final LiveOrderPhase phase;

  @override
  Widget build(BuildContext context) {
    // tableName only when POS sent a non-empty mesa / special ticket.
    final table = tableName.trim();
    final register = registerName.trim();

    final String title;
    final String? subtitle;
    if (customerDisplay) {
      title = 'CUSTOMER DISPLAY';
      if (table.isNotEmpty && register.isNotEmpty) {
        subtitle = '$table · $register';
      } else if (table.isNotEmpty) {
        subtitle = table;
      } else if (register.isNotEmpty) {
        subtitle = register;
      } else {
        subtitle = null;
      }
    } else if (table.isNotEmpty && register.isNotEmpty) {
      title = table;
      subtitle = register;
    } else if (register.isNotEmpty) {
      title = register;
      subtitle = null;
    } else if (table.isNotEmpty) {
      title = table;
      subtitle = null;
    } else {
      title = 'LIVE ORDER';
      subtitle = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          Container(
            color: CamaleonColors.green,
            padding: EdgeInsets.symmetric(
              horizontal: customerDisplay ? 20 : (compact ? 12 : 16),
              vertical: customerDisplay ? 18 : (compact ? 10 : 14),
            ),
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: customerDisplay
                        ? (compact ? 20 : 28)
                        : (compact ? 16 : 22),
                    letterSpacing: 0.6,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      fontSize: compact ? 13 : 16,
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (isTest && !customerDisplay)
          Container(
            color: CamaleonColors.orange,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'TEST ORDER',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.85),
                fontWeight: FontWeight.w800,
                fontSize: compact ? 11 : 13,
                letterSpacing: 1.2,
              ),
            ),
          ),
        if (phase == LiveOrderPhase.waiting ||
            phase == LiveOrderPhase.connecting)
          Container(
            color: Colors.white10,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              phase == LiveOrderPhase.connecting
                  ? 'Connecting…'
                  : 'Waiting for POS…',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ),
      ],
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({
    required this.controller,
    required this.compact,
    this.customerDisplay = false,
  });

  final LiveOrderController controller;
  final bool compact;
  final bool customerDisplay;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _scroll = ScrollController();
  String? _lastScrollKey;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToLatestIfNeeded(String key) {
    if (_lastScrollKey == key) return;
    final isFirst = _lastScrollKey == null;
    _lastScrollKey = key;
    if (isFirst) return; // don't animate on first paint
    void go() {
      if (!mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

    // Wait two frames so newly added rows are laid out first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    });
  }

  String _scrollKey(LiveOrderSnapshot snap) {
    // Fingerprint that changes when lines are added/removed/renamed.
    final buf = StringBuffer(snap.updatedAt);
    buf.write('|${snap.itemCount}');
    for (final seat in snap.seats) {
      buf.write('|${seat.seat}:${seat.items.length}');
      for (final p in seat.items) {
        buf.write('>${p.itemId}:${p.itemDescription}:${p.modifiers.length}');
        for (final m in p.modifiers) {
          buf.write('+${m.itemId}:${m.itemDescription}');
        }
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final snap = c.snapshot;
    final compact = widget.compact;
    final customerDisplay = widget.customerDisplay;
    final large = customerDisplay && !compact;

    if (c.phase == LiveOrderPhase.idle && !c.config.enabled) {
      _lastScrollKey = null;
      return _CenteredMessage(
        compact: compact,
        icon: Icons.receipt_long_outlined,
        text: 'Enable Live order in Settings',
      );
    }

    if (c.phase == LiveOrderPhase.error && snap == null) {
      _lastScrollKey = null;
      return _CenteredMessage(
        compact: compact,
        icon: Icons.wifi_off_rounded,
        text: c.statusMessage ?? 'Could not reach POS',
      );
    }

    if (c.phase == LiveOrderPhase.waiting && snap == null) {
      _lastScrollKey = null;
      return _CenteredMessage(
        compact: compact,
        icon: Icons.hourglass_top_rounded,
        text: 'Waiting for POS…',
      );
    }

    if (c.phase == LiveOrderPhase.connecting && snap == null) {
      _lastScrollKey = null;
      return const Center(
        child: CircularProgressIndicator(color: CamaleonColors.greenSoft),
      );
    }

    if (snap == null || !snap.hasItems || c.phase == LiveOrderPhase.empty) {
      _lastScrollKey = null;
      // Customer Display: never show "No items yet" — panel is hidden by board.
      if (customerDisplay) {
        return const SizedBox.shrink();
      }
      return _CenteredMessage(
        compact: compact,
        icon: Icons.shopping_bag_outlined,
        text: 'No items yet',
      );
    }

    _scrollToLatestIfNeeded(_scrollKey(snap));

    final seatsWithItems = snap.seats
        .where((s) => s.items.isNotEmpty)
        .toList(growable: false);

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        large ? 24 : (compact ? 12 : 20),
        large ? 18 : (compact ? 10 : 16),
        large ? 24 : (compact ? 12 : 20),
        large ? 18 : (compact ? 10 : 16),
      ),
      children: [
        for (final seat in seatsWithItems) ...[
          if (seatsWithItems.length > 1 || seat.seat.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                bottom: large ? 10 : (compact ? 6 : 8),
                top: 4,
              ),
              child: Text(
                seat.seat.isEmpty ? 'Seat' : 'Seat ${seat.seat}',
                style: TextStyle(
                  color: CamaleonColors.greenSoft,
                  fontWeight: FontWeight.w800,
                  fontSize: large ? 20 : (compact ? 13 : 15),
                ),
              ),
            ),
          for (final parent in seat.items) ...[
            _ItemRow(
              item: parent,
              compact: compact,
              customerDisplay: customerDisplay,
              isChild: false,
            ),
            for (final mod in parent.modifiers)
              _ItemRow(
                item: mod,
                compact: compact,
                customerDisplay: customerDisplay,
                isChild: true,
              ),
          ],
          SizedBox(height: large ? 14 : (compact ? 8 : 12)),
        ],
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.compact,
    required this.isChild,
    this.customerDisplay = false,
  });

  final LiveOrderItem item;
  final bool compact;
  final bool customerDisplay;
  final bool isChild;

  @override
  Widget build(BuildContext context) {
    final large = customerDisplay && !compact;
    final indent = isChild ? (large ? 32.0 : (compact ? 18.0 : 28.0)) : 0.0;
    final nameSize = large
        ? (isChild ? 18.0 : 24.0)
        : (compact ? (isChild ? 12.0 : 14.0) : (isChild ? 15.0 : 18.0));
    final qtySize = large ? 22.0 : (compact ? 13.0 : 16.0);
    final priceSize = large ? 22.0 : (compact ? 13.0 : 16.0);
    final showPrice = !isChild || item.lineTotal != 0;

    // POS kitchen-style: forced mods often already include "** "
    final displayName = item.itemDescription;

    return Padding(
      padding: EdgeInsets.only(
        left: indent,
        bottom: large ? 8 : (compact ? 3 : 5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: large ? 56 : (compact ? 36 : 44),
            child: Text(
              // Never show "1×" on nested modifiers.
              isChild ? '' : '${_fmtQty(item.qty)}×',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: qtySize,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayName,
              style: TextStyle(
                color: isChild
                    ? const Color(0xFFFF8A80) // POS-like red/pink for mods
                    : Colors.white,
                fontSize: nameSize,
                fontStyle: isChild ? FontStyle.italic : FontStyle.normal,
                height: 1.25,
                fontWeight: isChild ? FontWeight.w600 : FontWeight.w700,
              ),
            ),
          ),
          if (showPrice)
            Text(
              _fmtMoney(item.lineTotal),
              style: TextStyle(
                color: isChild ? Colors.white54 : Colors.white70,
                fontSize: priceSize,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.compact,
    required this.showTotals,
    this.totals,
    this.customerDisplay = false,
  });

  final bool compact;
  final bool customerDisplay;
  final LiveOrderTotals? totals;
  final bool showTotals;

  @override
  Widget build(BuildContext context) {
    if (!showTotals || totals == null) return const SizedBox.shrink();
    final t = totals!;
    final large = customerDisplay && !compact;
    final labelSize = large ? 15.0 : (compact ? 12.0 : 13.0);
    final valueSize = large ? 16.0 : (compact ? 12.0 : 14.0);
    final totalSize = large ? 24.0 : (compact ? 15.0 : 18.0);

    Widget row(
      String label,
      double amount, {
      bool emphasize = false,
      bool muted = false,
    }) {
      return Padding(
        padding: EdgeInsets.only(bottom: large ? 6 : 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: muted
                      ? Colors.white54
                      : (emphasize ? Colors.white : Colors.white70),
                  fontSize: emphasize ? totalSize * 0.7 : labelSize,
                  fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              _fmtMoney(amount),
              style: TextStyle(
                color: emphasize ? Colors.white : Colors.white70,
                fontSize: emphasize ? totalSize : valueSize,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final tipLabel = t.tipPercent > 0
        ? 'Tip (${t.tipPercent == t.tipPercent.roundToDouble() ? '${t.tipPercent.round()}' : t.tipPercent.toStringAsFixed(1)}%)'
        : 'Tip';

    return Container(
      padding: EdgeInsets.fromLTRB(
        large ? 24 : (compact ? 12 : 20),
        large ? 14 : (compact ? 10 : 12),
        large ? 24 : (compact ? 12 : 20),
        large ? 18 : (compact ? 12 : 16),
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.itemCount == 1 ? '1 item' : '${t.itemCount} items',
            style: TextStyle(
              color: Colors.white38,
              fontSize: large ? 13 : (compact ? 11 : 12),
            ),
          ),
          SizedBox(height: large ? 10 : 6),
          row('Subtotal', t.subtotal),
          if (t.tax != 0) row('Tax', t.tax),
          if (t.delivery > 0) row('Delivery', t.delivery),
          if (t.tip > 0 || t.tipPercent > 0) row(tipLabel, t.tip),
          if (t.showCashRounding) row('Cash rounding', t.cashRounding),
          row('Total', t.total, emphasize: true),
          if (t.showCashOption && t.cashOption != null)
            row('Cash option', t.cashOption!, muted: false),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.compact,
    required this.icon,
    required this.text,
  });

  final bool compact;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white24, size: compact ? 36 : 48),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: compact ? 13 : 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

}
