/// Movimiento de créditos (uso de API o recarga).
class CreditTransaction {
  final String id;
  final DateTime date;
  final CreditTransactionType type;
  final String model;
  final int tokens;
  final double cost;
  final double balanceAfter;
  final String? note;

  const CreditTransaction({
    required this.id,
    required this.date,
    required this.type,
    required this.model,
    required this.tokens,
    required this.cost,
    required this.balanceAfter,
    this.note,
  });

  factory CreditTransaction.fromJson(Map<String, dynamic> json) {
    return CreditTransaction(
      id: (json['id'] ?? '').toString(),
      date: DateTime.tryParse(json['date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      type: CreditTransactionTypeX.fromWire(json['type']?.toString()),
      model: (json['model'] ?? '—').toString(),
      tokens: (json['tokens'] as num?)?.toInt() ?? 0,
      cost: (json['cost'] as num?)?.toDouble() ?? 0,
      balanceAfter: (json['balanceAfter'] as num?)?.toDouble() ?? 0,
      note: json['note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'type': type.wire,
        'model': model,
        'tokens': tokens,
        'cost': cost,
        'balanceAfter': balanceAfter,
        if (note != null) 'note': note,
      };

  String get typeLabel {
    switch (type) {
      case CreditTransactionType.usage:
        return 'Uso';
      case CreditTransactionType.topup:
        return 'Recarga';
    }
  }
}

enum CreditTransactionType { usage, topup }

extension CreditTransactionTypeX on CreditTransactionType {
  String get wire {
    switch (this) {
      case CreditTransactionType.usage:
        return 'usage';
      case CreditTransactionType.topup:
        return 'topup';
    }
  }

  static CreditTransactionType fromWire(String? value) {
    switch (value) {
      case 'topup':
        return CreditTransactionType.topup;
      case 'usage':
      default:
        return CreditTransactionType.usage;
    }
  }
}
