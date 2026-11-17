/// Precios oficiales OpenAI (USD / 1M tokens) + margen del producto.
/// Fuente: https://developers.openai.com/api/docs/pricing (Standard).
class ModelTokenRates {
  /// USD por 1M tokens de input.
  final double inputPerMillion;

  /// USD por 1M tokens de output.
  final double outputPerMillion;

  const ModelTokenRates({
    required this.inputPerMillion,
    required this.outputPerMillion,
  });

  double get inputPerToken => inputPerMillion / 1000000.0;
  double get outputPerToken => outputPerMillion / 1000000.0;
}

class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final String model;

  const TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.model,
  });

  factory TokenUsage.fromApiUsage(
    Map usage, {
    required String model,
  }) {
    final prompt = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
    final completion = (usage['completion_tokens'] as num?)?.toInt() ?? 0;
    final total = (usage['total_tokens'] as num?)?.toInt() ??
        (prompt + completion);
    return TokenUsage(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: total,
      model: model,
    );
  }

  factory TokenUsage.totalOnly(int total, {required String model}) {
    return TokenUsage(
      promptTokens: 0,
      completionTokens: 0,
      totalTokens: total,
      model: model,
    );
  }
}

/// Tabla de cobro: costo OpenAI + margen hacia el cliente.
class ModelPricing {
  /// Margen sobre lo que cobra OpenAI (1.20 = +20% ganancia bruta).
  static const double marginMultiplier = 1.20;

  /// Mix conservador si solo llega total_tokens (agentes ≈ mucho input).
  /// 65% input / 35% output → no subestimar output caro.
  static const double _fallbackInputShare = 0.65;

  static const ModelTokenRates _fallback = ModelTokenRates(
    inputPerMillion: 2.00,
    outputPerMillion: 8.00,
  );

  /// Precios Standard OpenAI ($ / 1M tokens).
  static const Map<String, ModelTokenRates> _rates = {
    'gpt-4.1': ModelTokenRates(inputPerMillion: 2.00, outputPerMillion: 8.00),
    'gpt-4.1-mini':
        ModelTokenRates(inputPerMillion: 0.40, outputPerMillion: 1.60),
    'gpt-4.1-nano':
        ModelTokenRates(inputPerMillion: 0.10, outputPerMillion: 0.40),
    'gpt-4o': ModelTokenRates(inputPerMillion: 2.50, outputPerMillion: 10.00),
    'gpt-4o-mini':
        ModelTokenRates(inputPerMillion: 0.15, outputPerMillion: 0.60),
    'gpt-4-turbo':
        ModelTokenRates(inputPerMillion: 10.00, outputPerMillion: 30.00),
    'gpt-4': ModelTokenRates(inputPerMillion: 30.00, outputPerMillion: 60.00),
    'gpt-3.5-turbo':
        ModelTokenRates(inputPerMillion: 0.50, outputPerMillion: 1.50),
    'o4-mini': ModelTokenRates(inputPerMillion: 1.10, outputPerMillion: 4.40),
    'o3': ModelTokenRates(inputPerMillion: 2.00, outputPerMillion: 8.00),
    'o3-mini': ModelTokenRates(inputPerMillion: 1.10, outputPerMillion: 4.40),
    'o1': ModelTokenRates(inputPerMillion: 15.00, outputPerMillion: 60.00),
    'o1-mini': ModelTokenRates(inputPerMillion: 1.10, outputPerMillion: 4.40),
    'o1-preview':
        ModelTokenRates(inputPerMillion: 15.00, outputPerMillion: 60.00),
  };

  static ModelTokenRates ratesFor(String model) {
    final id = _normalize(model);
    final exact = _rates[id];
    if (exact != null) return exact;

    // Prefijos / snapshots: gpt-4.1-2025-04-14 → gpt-4.1
    final keys = _rates.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (id == key || id.startsWith('$key-') || id.startsWith('${key}_')) {
        return _rates[key]!;
      }
    }
    return _fallback;
  }

  /// Costo que OpenAI nos cobra (sin margen).
  static double openaiCost(TokenUsage usage) {
    final rates = ratesFor(usage.model);
    if (usage.promptTokens > 0 || usage.completionTokens > 0) {
      return usage.promptTokens * rates.inputPerToken +
          usage.completionTokens * rates.outputPerToken;
    }
    // Solo total: estimar mix input/output.
    final total = usage.totalTokens;
    if (total <= 0) return 0;
    final input = (total * _fallbackInputShare).round();
    final output = total - input;
    return input * rates.inputPerToken + output * rates.outputPerToken;
  }

  /// Lo que le cobramos al cliente (= OpenAI × margen).
  static double clientCost(TokenUsage usage) {
    return openaiCost(usage) * marginMultiplier;
  }

  /// Estimación previa al envío (solo total tokens previstos).
  static double estimateClientCost({
    required String model,
    required int estimatedTokens,
  }) {
    return clientCost(
      TokenUsage.totalOnly(estimatedTokens, model: model),
    );
  }

  /// Resumen legible para auditoría / UI.
  static Map<String, dynamic> auditRow(String model) {
    final r = ratesFor(model);
    final openaiBlended =
        r.inputPerMillion * _fallbackInputShare +
        r.outputPerMillion * (1 - _fallbackInputShare);
    return {
      'model': model,
      'openai_input_per_1m': r.inputPerMillion,
      'openai_output_per_1m': r.outputPerMillion,
      'openai_blended_est_per_1m':
          double.parse(openaiBlended.toStringAsFixed(4)),
      'client_input_per_1m':
          double.parse((r.inputPerMillion * marginMultiplier).toStringAsFixed(4)),
      'client_output_per_1m':
          double.parse((r.outputPerMillion * marginMultiplier).toStringAsFixed(4)),
      'client_blended_est_per_1m': double.parse(
        (openaiBlended * marginMultiplier).toStringAsFixed(4),
      ),
      'margin_pct': ((marginMultiplier - 1) * 100).round(),
    };
  }

  static List<Map<String, dynamic>> auditAllOfferedModels() {
    const offered = [
      'gpt-4.1',
      'gpt-4.1-mini',
      'gpt-4o',
      'gpt-4o-mini',
      'o4-mini',
      'gpt-4-turbo',
      'gpt-4',
      'gpt-3.5-turbo',
      'o1',
      'o1-mini',
    ];
    return offered.map(auditRow).toList();
  }

  static String _normalize(String model) {
    var id = model.trim().toLowerCase();
    // date snapshots ya se resuelven por prefijo
    return id;
  }
}
