import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lopez_code_ai/screens/wallet_screen.dart';
import 'package:lopez_code_ai/widgets/cursor_theme.dart';

/// Réplica del chip de billetera (misma navegación que en multi_chat_screen).
class _TestWalletChip extends StatelessWidget {
  const _TestWalletChip();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const WalletScreen()),
        );
      },
      child: const Text('\$20.00'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('clic en chip abre WalletScreen', (tester) async {
    SharedPreferences.setMockInitialValues({'user_balance': 20.0});
    await tester.pumpWidget(
      MaterialApp(
        theme: CursorTheme.theme,
        home: Scaffold(
          appBar: AppBar(
            actions: const [Center(child: _TestWalletChip())],
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WalletScreen), findsNothing);

    await tester.tap(find.text('\$20.00'));
    await tester.pumpAndSettle();

    expect(find.byType(WalletScreen), findsOneWidget);
    expect(find.text('Billetera'), findsOneWidget);
  });
}
