import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/credit_transaction.dart';
import '../services/credit_service.dart';
import '../widgets/cursor_theme.dart';

/// Página de billetera / créditos de API (estilo Cursor IDE).
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  double _balance = 0.0;
  bool _loading = true;
  List<CreditTransaction> _transactions = const [];
  Map<DateTime, int> _tokensByDay = const {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final balance = await CreditService.getBalance();
    final txs = await CreditService.getTransactions(limit: 80);
    final byDay = await CreditService.tokensByDay(days: 7);
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _transactions = txs;
      _tokensByDay = byDay;
      if (!silent) _loading = false;
    });
  }

  Future<void> _addCredits(double amount) async {
    await CreditService.addCredits(amount);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Se agregaron \$${amount.toStringAsFixed(2)} a tu billetera'),
        backgroundColor: CursorTheme.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _exportCsv() async {
    if (_transactions.isEmpty) return;
    final buf = StringBuffer('date_utc,type,model,tokens,cost_usd,balance_after,note\n');
    for (final tx in _transactions) {
      buf.writeln(
        '${tx.date.toIso8601String()},${tx.type.wire},${_csv(tx.model)},'
        '${tx.tokens},${tx.cost.toStringAsFixed(6)},'
        '${tx.balanceAfter.toStringAsFixed(4)},${_csv(tx.note ?? '')}',
      );
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV copiado al portapapeles'),
        backgroundColor: CursorTheme.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _csv(String v) {
    final escaped = v.replaceAll('"', '""');
    return '"$escaped"';
  }

  @override
  Widget build(BuildContext context) {
    final low = _balance <= 0;

    return Scaffold(
      backgroundColor: CursorTheme.background,
      appBar: AppBar(
        backgroundColor: CursorTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 18),
          color: CursorTheme.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Volver',
        ),
        title: const Text(
          'Billetera',
          style: TextStyle(
            color: CursorTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: CursorTheme.border),
        ),
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CursorTheme.primary,
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                  children: [
                    _BalanceHero(balance: _balance, low: low),
                    const SizedBox(height: 24),
                    _SectionLabel('Recargar'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TopUpButton(
                            label: '+ \$5',
                            onTap: () => _addCredits(5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TopUpButton(
                            label: '+ \$10',
                            onTap: () => _addCredits(10),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TopUpButton(
                            label: '+ \$25',
                            onTap: () => _addCredits(25),
                            emphasized: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _SectionLabel('Uso (7 días)'),
                    const SizedBox(height: 10),
                    _UsageChart(tokensByDay: _tokensByDay),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        const Expanded(child: _SectionLabel('Transacciones')),
                        TextButton.icon(
                          onPressed:
                              _transactions.isEmpty ? null : _exportCsv,
                          icon: const Icon(Icons.download_outlined, size: 14),
                          label: const Text('Export CSV'),
                          style: TextButton.styleFrom(
                            foregroundColor: CursorTheme.textSecondary,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _TransactionsCard(transactions: _transactions),
                    const SizedBox(height: 28),
                    _SectionLabel('Cómo funciona'),
                    const SizedBox(height: 10),
                    const _InfoCard(
                      children: [
                        _InfoRow(
                          icon: Icons.smart_toy_outlined,
                          title: 'Uso del agente',
                          body:
                              'Cada solicitud al agente consume créditos según tokens usados.',
                        ),
                        SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.percent,
                          title: 'Margen incluido',
                          body:
                              'El costo incluye un margen sobre la tarifa de la API para cubrir operación.',
                        ),
                        SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.lock_outline,
                          title: 'Saldo local',
                          body:
                              'El saldo y el historial se guardan en este dispositivo.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance, required this.low});

  final double balance;
  final bool low;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CursorTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: CursorTheme.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: CursorTheme.border),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: low ? const Color(0xFFE06C75) : CursorTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Saldo disponible',
                  style: TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (low)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE06C75).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFFE06C75).withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Text(
                    'Sin saldo',
                    style: TextStyle(
                      color: Color(0xFFE06C75),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '\$${balance.toStringAsFixed(2)}',
            style: TextStyle(
              color: low ? const Color(0xFFE06C75) : CursorTheme.textPrimary,
              fontSize: 36,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'USD · créditos de API',
            style: TextStyle(
              color: CursorTheme.textDisabled,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageChart extends StatelessWidget {
  const _UsageChart({required this.tokensByDay});

  final Map<DateTime, int> tokensByDay;

  @override
  Widget build(BuildContext context) {
    final days = tokensByDay.keys.toList()..sort();
    final maxTokens = days.isEmpty
        ? 0
        : days.map((d) => tokensByDay[d] ?? 0).fold<int>(0, math.max);
    final total = days.fold<int>(0, (s, d) => s + (tokensByDay[d] ?? 0));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CursorTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Tokens',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                total == 0 ? 'Sin uso esta semana' : _formatTokens(total),
                style: const TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: days.isEmpty
                ? const Center(
                    child: Text(
                      'Aún no hay datos',
                      style: TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final day in days) ...[
                        Expanded(
                          child: _DayBar(
                            tokens: tokensByDay[day] ?? 0,
                            maxTokens: math.max(maxTokens, 1),
                            label: _weekday(day),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _weekday(DateTime d) {
    const names = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return names[d.weekday - 1];
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.tokens,
    required this.maxTokens,
    required this.label,
  });

  final int tokens;
  final int maxTokens;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ratio = (tokens / maxTokens).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Tooltip(
                message: tokens == 0 ? '0 tokens' : _formatTokens(tokens),
                child: FractionallySizedBox(
                  heightFactor: tokens == 0 ? 0.04 : math.max(0.08, ratio),
                  widthFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: tokens == 0
                          ? CursorTheme.border
                          : CursorTheme.primary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionsCard extends StatelessWidget {
  const _TransactionsCard({required this.transactions});

  final List<CreditTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CursorTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: transactions.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 28),
              child: Center(
                child: Text(
                  'Todavía no hay transacciones.\nUsa el agente o recarga para ver el historial.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            )
          : Column(
              children: [
                const _TxHeader(),
                const Divider(height: 1, color: CursorTheme.border),
                for (var i = 0; i < transactions.length; i++) ...[
                  _TxRow(tx: transactions[i]),
                  if (i != transactions.length - 1)
                    const Divider(height: 1, color: CursorTheme.border),
                ],
              ],
            ),
    );
  }
}

class _TxHeader extends StatelessWidget {
  const _TxHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      color: CursorTheme.background.withValues(alpha: 0.45),
      child: const Row(
        children: [
          Expanded(flex: 3, child: _H('Fecha')),
          Expanded(flex: 2, child: _H('Tipo')),
          Expanded(flex: 3, child: _H('Modelo')),
          Expanded(flex: 2, child: _H('Tokens', align: TextAlign.right)),
          Expanded(flex: 2, child: _H('Costo', align: TextAlign.right)),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text, {this.align = TextAlign.left});
  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: const TextStyle(
        color: CursorTheme.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});
  final CreditTransaction tx;

  @override
  Widget build(BuildContext context) {
    final isTopup = tx.type == CreditTransactionType.topup;
    final costText = isTopup
        ? '+${tx.cost.toStringAsFixed(2)}'
        : '-${tx.cost.toStringAsFixed(4)}';
    final costColor =
        isTopup ? const Color(0xFF22C55E) : CursorTheme.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              _formatDate(tx.date.toLocal()),
              style: const TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isTopup
                      ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                      : CursorTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tx.typeLabel,
                  style: TextStyle(
                    color: isTopup
                        ? const Color(0xFF22C55E)
                        : CursorTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              tx.model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              tx.tokens == 0 ? '—' : _formatTokens(tx.tokens),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              costText,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: costColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, $h:$m';
  }
}

String _formatTokens(int tokens) {
  if (tokens >= 1000000) {
    return '${(tokens / 1000000).toStringAsFixed(1)}M';
  }
  if (tokens >= 1000) {
    return '${(tokens / 1000).toStringAsFixed(1)}K';
  }
  return '$tokens';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: CursorTheme.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _TopUpButton extends StatefulWidget {
  const _TopUpButton({
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  State<_TopUpButton> createState() => _TopUpButtonState();
}

class _TopUpButtonState extends State<_TopUpButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.emphasized
        ? (_hover ? CursorTheme.primaryHover : CursorTheme.primary)
        : (_hover ? CursorTheme.surfaceHover : CursorTheme.surface);
    final fg = widget.emphasized ? Colors.white : CursorTheme.textPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: widget.emphasized
                  ? null
                  : Border.all(color: CursorTheme.border),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CursorTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: CursorTheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
