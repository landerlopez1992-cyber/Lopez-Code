import 'dart:async';

import 'package:flutter/material.dart';
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
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadBalance();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _loadBalance();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    final balance = await CreditService.getBalance();
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _loading = false;
    });
  }

  Future<void> _addCredits(double amount) async {
    await CreditService.addCredits(amount);
    await _loadBalance();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Se agregaron \$${amount.toStringAsFixed(2)} a tu billetera'),
        backgroundColor: CursorTheme.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                  children: [
                    _BalanceHero(balance: _balance, low: low),
                    const SizedBox(height: 28),
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
                              'El saldo se guarda en este dispositivo. Recargas rápidas sirven para pruebas.',
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
