import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/credit_transaction.dart';
import 'auth_service.dart';
import 'model_pricing.dart';
import 'wallet_cloud_service.dart';

/// Créditos por cuenta: anónimo ≠ usuario logueado.
/// Cerrar sesión ya no deja ver el saldo de la cuenta.
class CreditService {
  static const String _legacyBalanceKey = 'user_balance';
  static const String _legacyTxKey = 'credit_transactions_v1';
  static const String _legacyMigratedKey = 'credit_migrated_to_uid_v1';
  static const double _initialBalance = 0.0;
  static const int _maxStoredTransactions = 250;

  static String get _ownerId {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return 'anon';
    return uid;
  }

  static String get _balanceKey => 'user_balance_v2_$_ownerId';
  static String get _transactionsKey => 'credit_tx_v2_$_ownerId';

  /// Saldo usable por el agente (> 0).
  static Future<bool> hasPositiveBalance() async {
    return (await getBalance()) > 0;
  }

  /// Saldo de la sesión actual (anon local; cuenta → cache + Firebase).
  static Future<double> getBalance() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(prefs);

    final balance = prefs.getDouble(_balanceKey);
    if (balance == null) {
      await prefs.setDouble(_balanceKey, _initialBalance);
      return _initialBalance;
    }
    return balance;
  }

  static Future<void> setBalance(double balance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_balanceKey, balance);
    // Espejo en Firebase para que viaje con el user.
    if (WalletCloudService.isAvailable) {
      await WalletCloudService.pushBalance(
        balance,
        email: AuthService.instance.currentUser?.email,
      );
    }
  }

  /// Tras login Firebase: trae saldo de la nube (u otros Macs) al cache local.
  static Future<void> syncFromCloudAfterLogin() async {
    if (!WalletCloudService.isAvailable) return;
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(prefs);
    final local = prefs.getDouble(_balanceKey) ?? _initialBalance;
    final resolved = await WalletCloudService.reconcileWithLocal(local);
    if (resolved != null) {
      await prefs.setDouble(_balanceKey, resolved);
    }
    // Cachear historial remoto si viene.
    final remoteTx = await WalletCloudService.fetchTransactions(limit: 80);
    if (remoteTx.isNotEmpty) {
      final encoded = remoteTx.map((t) => jsonEncode(t.toJson())).toList();
      await prefs.setStringList(_transactionsKey, encoded);
    }
  }

  /// Si había saldo global viejo y ahora hay sesión, se lo asigna UNA vez a esa cuenta.
  static Future<void> _migrateLegacyIfNeeded(SharedPreferences prefs) async {
    if (!AuthService.instance.isSignedIn) return;
    if (prefs.getBool(_legacyMigratedKey) == true) return;

    final legacy = prefs.getDouble(_legacyBalanceKey);
    final hasNew = prefs.containsKey(_balanceKey);
    if (legacy != null && !hasNew) {
      await prefs.setDouble(_balanceKey, legacy);
      final legacyTx = prefs.getStringList(_legacyTxKey);
      if (legacyTx != null && legacyTx.isNotEmpty) {
        await prefs.setStringList(_transactionsKey, legacyTx);
      }
    }
    await prefs.setBool(_legacyMigratedKey, true);
    // El legado ya no debe verse en anónimo.
    await prefs.remove(_legacyBalanceKey);
  }

  static double calculateClientCost(TokenUsage usage) {
    return ModelPricing.clientCost(usage);
  }

  /// @deprecated Usa [calculateClientCost] / [deductUsage].
  static double calculateCost(int tokensUsed, double costPerToken) {
    return tokensUsed * costPerToken * ModelPricing.marginMultiplier;
  }

  static Future<bool> deductUsage(
    TokenUsage usage, {
    String? note,
  }) async {
    final currentBalance = await getBalance();
    final cost = calculateClientCost(usage);
    final tokensUsed = usage.totalTokens > 0
        ? usage.totalTokens
        : (usage.promptTokens + usage.completionTokens);

    if (cost <= 0 || tokensUsed <= 0) return true;
    if (currentBalance < cost) return false;

    final newBalance = currentBalance - cost;
    await setBalance(newBalance);
    final openai = ModelPricing.openaiCost(usage);
    await _appendTransaction(
      CreditTransaction(
        id: _newId(),
        date: DateTime.now().toUtc(),
        type: CreditTransactionType.usage,
        model: usage.model,
        tokens: tokensUsed,
        cost: cost,
        balanceAfter: newBalance,
        note: note ??
            'OpenAI \$${openai.toStringAsFixed(5)} → '
                'cliente \$${cost.toStringAsFixed(5)} '
                '(+${((ModelPricing.marginMultiplier - 1) * 100).round()}%)',
      ),
    );
    return true;
  }

  /// @deprecated Usa [deductUsage].
  static Future<bool> deductCredits(
    int tokensUsed,
    double costPerToken, {
    String model = 'unknown',
    String? note,
  }) async {
    return deductUsage(
      TokenUsage.totalOnly(tokensUsed, model: model),
      note: note,
    );
  }

  static Future<bool> hasEnoughBalanceForModel({
    required String model,
    required int estimatedTokens,
  }) async {
    final currentBalance = await getBalance();
    final estimatedCost = ModelPricing.estimateClientCost(
      model: model,
      estimatedTokens: estimatedTokens,
    );
    return currentBalance >= estimatedCost;
  }

  /// @deprecated Usa [hasEnoughBalanceForModel].
  static Future<bool> hasEnoughBalance(
    int estimatedTokens,
    double costPerToken,
  ) async {
    final currentBalance = await getBalance();
    final estimatedCost = calculateCost(estimatedTokens, costPerToken);
    return currentBalance >= estimatedCost;
  }

  static double getEstimatedCostForModel({
    required String model,
    required int estimatedTokens,
  }) {
    return ModelPricing.estimateClientCost(
      model: model,
      estimatedTokens: estimatedTokens,
    );
  }

  /// @deprecated Usa [getEstimatedCostForModel].
  static double getEstimatedCost(int tokens, double costPerToken) {
    return calculateCost(tokens, costPerToken);
  }

  static Future<void> resetBalance() async {
    await setBalance(_initialBalance);
  }

  /// Recarga: solo con sesión. Va al saldo de ESA cuenta.
  static Future<void> addCredits(double amount, {String? note}) async {
    if (!AuthService.instance.isSignedIn) {
      throw AuthException(
        'Inicia sesión para agregar saldo a la billetera',
      );
    }
    if (amount <= 0) {
      throw AuthException('El monto de recarga debe ser mayor a 0');
    }
    final currentBalance = await getBalance();
    final newBalance = currentBalance + amount;
    await setBalance(newBalance);
    final email = AuthService.instance.currentUser?.email ?? 'cuenta';
    await _appendTransaction(
      CreditTransaction(
        id: _newId(),
        date: DateTime.now().toUtc(),
        type: CreditTransactionType.topup,
        model: '—',
        tokens: 0,
        cost: amount,
        balanceAfter: newBalance,
        note: note ?? 'Recarga ($email)',
      ),
    );
  }

  static Future<List<CreditTransaction>> getTransactions({
    int limit = 100,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(prefs);
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

  static Future<void> clearTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_transactionsKey);
  }

  static double getMarginMultiplier() => ModelPricing.marginMultiplier;

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
    if (WalletCloudService.isAvailable) {
      await WalletCloudService.appendTransaction(tx);
    }
  }

  static String _newId() =>
      'tx_${DateTime.now().toUtc().microsecondsSinceEpoch}';
}
