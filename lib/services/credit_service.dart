import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/credit_transaction.dart';

/// Servicio para gestionar créditos/tokens del usuario
/// Similar a cómo Cursor maneja los créditos de API
class CreditService {
  static const String _balanceKey = 'user_balance';
  static const String _transactionsKey = 'credit_transactions_v1';
  static const double _initialBalance = 20.0; // $20 iniciales
  static const double _marginMultiplier =
      1.2; // 20% de margen (ejemplo: OpenAI cobra $5, nosotros $6)
  static const int _maxStoredTransactions = 250;

  /// Obtiene el saldo actual del usuario
  static Future<double> getBalance() async {
    final prefs = await SharedPreferences.getInstance();
    final balance = prefs.getDouble(_balanceKey);

    // Si no existe, inicializar con saldo inicial
    if (balance == null) {
      await setBalance(_initialBalance);
      return _initialBalance;
    }

    return balance;
  }

  /// Establece el saldo del usuario
  static Future<void> setBalance(double balance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_balanceKey, balance);
  }

  /// Calcula el costo de una solicitud basado en tokens usados
  ///
  /// Parámetros:
  /// - tokensUsed: Número de tokens usados en la solicitud
  /// - costPerToken: Costo por token de la API (ejemplo: 0.00001 para GPT-4o-mini)
  ///
  /// Retorna: Costo total con margen aplicado
  static double calculateCost(int tokensUsed, double costPerToken) {
    final baseCost = tokensUsed * costPerToken;
    final costWithMargin = baseCost * _marginMultiplier;
    return costWithMargin;
  }

  /// Descuenta créditos de una solicitud y registra la transacción.
  ///
  /// Retorna: true si se pudo descontar, false si no hay suficiente saldo
  static Future<bool> deductCredits(
    int tokensUsed,
    double costPerToken, {
    String model = 'unknown',
    String? note,
  }) async {
    final currentBalance = await getBalance();
    final cost = calculateCost(tokensUsed, costPerToken);

    if (currentBalance < cost) {
      return false; // Saldo insuficiente
    }

    final newBalance = currentBalance - cost;
    await setBalance(newBalance);
    await _appendTransaction(
      CreditTransaction(
        id: _newId(),
        date: DateTime.now().toUtc(),
        type: CreditTransactionType.usage,
        model: model,
        tokens: tokensUsed,
        cost: cost,
        balanceAfter: newBalance,
        note: note ?? 'Llamada al agente',
      ),
    );
    return true;
  }

  /// Verifica si hay suficiente saldo para una solicitud
  static Future<bool> hasEnoughBalance(
    int estimatedTokens,
    double costPerToken,
  ) async {
    final currentBalance = await getBalance();
    final estimatedCost = calculateCost(estimatedTokens, costPerToken);
    return currentBalance >= estimatedCost;
  }

  /// Obtiene el costo estimado de una solicitud sin descontar
  static double getEstimatedCost(int tokens, double costPerToken) {
    return calculateCost(tokens, costPerToken);
  }

  /// Reinicia el saldo al valor inicial (útil para testing)
  static Future<void> resetBalance() async {
    await setBalance(_initialBalance);
  }

  /// Agrega créditos al saldo (útil para recargas) y registra la transacción.
  static Future<void> addCredits(double amount, {String? note}) async {
    final currentBalance = await getBalance();
    final newBalance = currentBalance + amount;
    await setBalance(newBalance);
    await _appendTransaction(
      CreditTransaction(
        id: _newId(),
        date: DateTime.now().toUtc(),
        type: CreditTransactionType.topup,
        model: '—',
        tokens: 0,
        cost: amount,
        balanceAfter: newBalance,
        note: note ?? 'Recarga manual',
      ),
    );
  }

  /// Historial reciente (más nuevo primero).
  static Future<List<CreditTransaction>> getTransactions({
    int limit = 100,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_transactionsKey) ?? const <String>[];
    final items = <CreditTransaction>[];
    for (final line in raw) {
      try {
        final map = jsonDecode(line);
        if (map is Map) {
          items.add(
            CreditTransaction.fromJson(Map<String, dynamic>.from(map)),
          );
        }
      } catch (_) {}
    }
    items.sort((a, b) => b.date.compareTo(a.date));
    if (items.length <= limit) return items;
    return items.take(limit).toList();
  }

  /// Tokens usados por día (UTC) en los últimos [days] días.
  static Future<Map<DateTime, int>> tokensByDay({int days = 7}) async {
    final txs = await getTransactions(limit: _maxStoredTransactions);
    final now = DateTime.now().toUtc();
    final start = DateTime.utc(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final map = <DateTime, int>{};
    for (var i = 0; i < days; i++) {
      map[start.add(Duration(days: i))] = 0;
    }
    for (final tx in txs) {
      if (tx.type != CreditTransactionType.usage) continue;
      final day = DateTime.utc(tx.date.year, tx.date.month, tx.date.day);
      if (day.isBefore(start)) continue;
      map[day] = (map[day] ?? 0) + tx.tokens;
    }
    return map;
  }

  /// Borra el historial (no toca el saldo).
  static Future<void> clearTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_transactionsKey);
  }

  /// Obtiene el multiplicador de margen actual
  static double getMarginMultiplier() => _marginMultiplier;

  /// Obtiene el saldo inicial
  static double getInitialBalance() => _initialBalance;

  static Future<void> _appendTransaction(CreditTransaction tx) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = List<String>.from(
      prefs.getStringList(_transactionsKey) ?? const <String>[],
    );
    raw.insert(0, jsonEncode(tx.toJson()));
    if (raw.length > _maxStoredTransactions) {
      raw.removeRange(_maxStoredTransactions, raw.length);
    }
    await prefs.setStringList(_transactionsKey, raw);
  }

  static String _newId() =>
      'tx_${DateTime.now().toUtc().microsecondsSinceEpoch}';
}
