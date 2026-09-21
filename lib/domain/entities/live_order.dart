/// In-memory order snapshot from the POS Live order HTTP service.
class LiveOrderSnapshot {
  const LiveOrderSnapshot({
    required this.updatedAt,
    required this.isTest,
    required this.empty,
    required this.tableName,
    required this.registerName,
    required this.seats,
    required this.totals,
  });

  final String updatedAt;
  final bool isTest;
  final bool empty;

  /// Empty when Order Entry has no mesa / special ticket selected.
  final String tableName;
  final String registerName;
  final List<LiveOrderSeat> seats;
  final LiveOrderTotals totals;

  double get subtotal => totals.subtotal;
  int get itemCount => totals.itemCount;

  bool get hasTableName => tableName.trim().isNotEmpty;

  /// Whether the Customer Display ticket should be visible.
  /// Hide when empty / no parents / itemCount==0 (no "No items yet" screen).
  bool get shouldShowTicket =>
      !empty && itemCount > 0 && seats.any((s) => s.items.isNotEmpty);

  bool get hasItems => shouldShowTicket;

  factory LiveOrderSnapshot.fromJson(Map<String, dynamic> json) {
    final seatsRaw = json['seats'];
    final seats = <LiveOrderSeat>[];
    if (seatsRaw is List) {
      for (final entry in seatsRaw) {
        if (entry is Map<String, dynamic>) {
          seats.add(LiveOrderSeat.fromJson(entry));
        } else if (entry is Map) {
          seats.add(LiveOrderSeat.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }

    final totalsRaw = json['totals'];
    Map<String, dynamic>? totalsMap;
    if (totalsRaw is Map<String, dynamic>) {
      totalsMap = totalsRaw;
    } else if (totalsRaw is Map) {
      totalsMap = Map<String, dynamic>.from(totalsRaw);
    }

    // tableName may be omitted entirely when no mesa is selected.
    final hasTableKey = json.containsKey('tableName');
    final tableName = hasTableKey ? '${json['tableName'] ?? ''}'.trim() : '';

    return LiveOrderSnapshot(
      updatedAt: '${json['updatedAt'] ?? ''}',
      isTest: json['isTest'] == true,
      empty: json['empty'] == true || seats.every((s) => s.items.isEmpty),
      tableName: tableName,
      registerName: '${json['registerName'] ?? ''}'.trim(),
      seats: List.unmodifiable(seats),
      totals: LiveOrderTotals.fromJson(totalsMap ?? const {}),
    );
  }

  static double asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static int asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse('$v') ?? 0;
  }

  static double? asDoubleOrNull(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = '$v'.trim();
    if (s.isEmpty || s == 'null') return null;
    return double.tryParse(s);
  }
}

/// Order Entry landscape footer totals from POS.
class LiveOrderTotals {
  const LiveOrderTotals({
    required this.subtotal,
    required this.tax,
    required this.delivery,
    required this.tip,
    required this.tipPercent,
    required this.total,
    required this.cashRounding,
    required this.cashOption,
    required this.showCashRounding,
    required this.showCashOption,
    required this.itemCount,
  });

  final double subtotal;
  final double tax;
  final double delivery;
  final double tip;
  final double tipPercent;
  final double total;
  final double cashRounding;
  final double? cashOption;
  final bool showCashRounding;
  final bool showCashOption;
  final int itemCount;

  factory LiveOrderTotals.fromJson(Map<String, dynamic> json) {
    final cashOption = LiveOrderSnapshot.asDoubleOrNull(json['cashOption']);
    final showCashOption = json.containsKey('showCashOption')
        ? json['showCashOption'] == true
        : cashOption != null;
    final showCashRounding = json.containsKey('showCashRounding')
        ? json['showCashRounding'] == true
        : LiveOrderSnapshot.asDouble(json['cashRounding']) != 0;

    return LiveOrderTotals(
      subtotal: LiveOrderSnapshot.asDouble(json['subtotal']),
      tax: LiveOrderSnapshot.asDouble(json['tax']),
      delivery: LiveOrderSnapshot.asDouble(json['delivery']),
      tip: LiveOrderSnapshot.asDouble(json['tip']),
      tipPercent: LiveOrderSnapshot.asDouble(json['tipPercent']),
      total: LiveOrderSnapshot.asDouble(json['total']),
      cashRounding: LiveOrderSnapshot.asDouble(json['cashRounding']),
      cashOption: cashOption,
      showCashRounding: showCashRounding,
      showCashOption: showCashOption,
      itemCount: LiveOrderSnapshot.asInt(json['itemCount']),
    );
  }
}

enum LiveOrderModifierKind { none, forced, regular }

LiveOrderModifierKind liveOrderModifierKindFrom(String? raw) {
  switch ((raw ?? 'none').trim().toLowerCase()) {
    case 'forced':
      return LiveOrderModifierKind.forced;
    case 'regular':
      return LiveOrderModifierKind.regular;
    default:
      return LiveOrderModifierKind.none;
  }
}

class LiveOrderSeat {
  const LiveOrderSeat({required this.seat, required this.items});

  final String seat;

  /// Parent lines only (each may carry nested [LiveOrderItem.modifiers]).
  final List<LiveOrderItem> items;

  factory LiveOrderSeat.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final rawItems = <LiveOrderItem>[];
    if (itemsRaw is List) {
      for (final entry in itemsRaw) {
        if (entry is Map<String, dynamic>) {
          rawItems.add(LiveOrderItem.fromJson(entry));
        } else if (entry is Map) {
          rawItems.add(
            LiveOrderItem.fromJson(Map<String, dynamic>.from(entry)),
          );
        }
      }
    }
    return LiveOrderSeat(
      seat: '${json['seat'] ?? ''}'.trim(),
      items: List.unmodifiable(_nestParents(rawItems)),
    );
  }

  /// Ensures parents-only list: nested `modifiers[]` preferred; legacy flat
  /// `isModifier=true` siblings are attached to the previous parent.
  static List<LiveOrderItem> _nestParents(List<LiveOrderItem> raw) {
    if (raw.isEmpty) return const [];

    final hasNested = raw.any((i) => i.modifiers.isNotEmpty);
    final hasFlatMods = raw.any((i) => i.isModifier);

    if (hasNested || !hasFlatMods) {
      // Drop any accidental top-level modifier siblings when nested exists.
      return [
        for (final i in raw)
          if (!i.isModifier) i,
      ];
    }

    // Legacy flat payload fallback.
    final parents = <LiveOrderItem>[];
    for (final line in raw) {
      if (!line.isModifier) {
        parents.add(line);
      } else if (parents.isNotEmpty) {
        final last = parents.removeLast();
        parents.add(
          last.copyWith(
            modifiers: [
              ...last.modifiers,
              line.copyWith(modifiers: const []),
            ],
          ),
        );
      }
      // Orphan modifier with no parent — skip (never promote to 1× row).
    }
    return parents;
  }
}

class LiveOrderItem {
  const LiveOrderItem({
    required this.itemDescription,
    required this.qty,
    required this.itemPrice,
    required this.lineTotal,
    required this.isModifier,
    required this.modifierKind,
    this.modifiers = const [],
    this.itemId = '',
    this.action = '',
    this.modCharge,
  });

  /// CamaleonDB.itemDescription as currently on the in-memory check line.
  final String itemDescription;
  final double qty;

  /// CamaleonDB.itemSalePrice on that same in-memory line.
  final double itemPrice;
  final double lineTotal;
  final bool isModifier;

  /// Only meaningful for children: forced | regular. Parents use [none]
  /// (JSON omits modifierKind for parents).
  final LiveOrderModifierKind modifierKind;

  /// Child modifier lines (parents only). Empty for children.
  final List<LiveOrderItem> modifiers;
  final String itemId;
  final String action;
  final double? modCharge;

  /// Alias for UI that still says "name".
  String get name => itemDescription;

  /// Alias for UI that still says "unitPrice".
  double get unitPrice => itemPrice;

  bool get isParent => !isModifier;

  LiveOrderItem copyWith({
    String? itemDescription,
    double? qty,
    double? itemPrice,
    double? lineTotal,
    bool? isModifier,
    LiveOrderModifierKind? modifierKind,
    List<LiveOrderItem>? modifiers,
    String? itemId,
    String? action,
    double? modCharge,
  }) {
    return LiveOrderItem(
      itemDescription: itemDescription ?? this.itemDescription,
      qty: qty ?? this.qty,
      itemPrice: itemPrice ?? this.itemPrice,
      lineTotal: lineTotal ?? this.lineTotal,
      isModifier: isModifier ?? this.isModifier,
      modifierKind: modifierKind ?? this.modifierKind,
      modifiers: modifiers ?? this.modifiers,
      itemId: itemId ?? this.itemId,
      action: action ?? this.action,
      modCharge: modCharge ?? this.modCharge,
    );
  }

  factory LiveOrderItem.fromJson(Map<String, dynamic> json) {
    final qty = LiveOrderSnapshot.asDouble(json['qty']);

    // Prefer new POS keys; fall back to legacy name/unitPrice/kitchenName.
    final desc = _firstNonEmpty([
      json['itemDescription'],
      json['name'],
      json['kitchenName'],
      json['modifierName'],
      json['screenName'],
    ]);

    final price = json.containsKey('itemPrice')
        ? LiveOrderSnapshot.asDouble(json['itemPrice'])
        : LiveOrderSnapshot.asDouble(json['unitPrice']);

    final total = json.containsKey('lineTotal')
        ? LiveOrderSnapshot.asDouble(json['lineTotal'])
        : qty * price;

    // Parents omit modifierKind. Presence of forced|regular (or isModifier)
    // marks a child. Never treat missing kind as a modifier.
    final kindRaw = '${json['modifierKind'] ?? ''}'.trim();
    final hasKind = kindRaw.isNotEmpty;
    final kind = liveOrderModifierKindFrom(kindRaw);
    final isMod =
        json['isModifier'] == true ||
        (hasKind && kind != LiveOrderModifierKind.none);

    final modsRaw = json['modifiers'];
    final mods = <LiveOrderItem>[];
    if (modsRaw is List) {
      for (final entry in modsRaw) {
        if (entry is Map<String, dynamic>) {
          mods.add(LiveOrderItem.fromJson(entry));
        } else if (entry is Map) {
          mods.add(LiveOrderItem.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }

    return LiveOrderItem(
      itemDescription: desc,
      qty: qty,
      itemPrice: price,
      lineTotal: total,
      isModifier: isMod,
      modifierKind: !isMod
          ? LiveOrderModifierKind.none
          : (kind == LiveOrderModifierKind.none
                ? LiveOrderModifierKind.regular
                : kind),
      modifiers: List.unmodifiable(mods),
      itemId: '${json['itemId'] ?? ''}',
      action: '${json['action'] ?? ''}'.trim(),
      modCharge: LiveOrderSnapshot.asDoubleOrNull(json['modCharge']),
    );
  }

  static String _firstNonEmpty(List<Object?> values) {
    for (final v in values) {
      final s = '${v ?? ''}'.trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }
}

class LiveOrderHealth {
  const LiveOrderHealth({
    required this.ok,
    required this.port,
    required this.updatedAt,
    required this.itemCount,
    required this.empty,
  });

  final bool ok;
  final int port;
  final String updatedAt;
  final int itemCount;
  final bool empty;

  factory LiveOrderHealth.fromJson(Map<String, dynamic> json) {
    return LiveOrderHealth(
      ok: json['ok'] == true,
      port: LiveOrderSnapshot.asInt(json['port']),
      updatedAt: '${json['updatedAt'] ?? ''}',
      itemCount: LiveOrderSnapshot.asInt(json['itemCount']),
      empty: json['empty'] == true,
    );
  }
}
