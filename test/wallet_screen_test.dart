import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lopez_code_ai/screens/wallet_screen.dart';
import 'package:lopez_code_ai/services/credit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WalletScreen muestra saldo y botones de recarga', (tester) async {
    SharedPreferences.setMockInitialValues({'user_balance': 20.0});
    await tester.pumpWidget(
      const MaterialApp(home: WalletScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Billetera'), findsOneWidget);
    expect(find.textContaining('\$20.00'), findsWidgets);
    expect(find.text('+ \$5'), findsOneWidget);
    expect(find.text('+ \$10'), findsOneWidget);
    expect(find.text('+ \$25'), findsOneWidget);
  });

  testWidgets('recarga +\$5 actualiza saldo', (tester) async {
    SharedPreferences.setMockInitialValues({'user_balance': 20.0});
    await tester.pumpWidget(
      const MaterialApp(home: WalletScreen()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ \$5'));
    await tester.pumpAndSettle();
    expect(find.textContaining('\$25.00'), findsWidgets);
  });

  test('CreditService get/add balance', () async {
    SharedPreferences.setMockInitialValues({});
    final b = await CreditService.getBalance();
    expect(b, 20.0);
    await CreditService.addCredits(5);
    expect(await CreditService.getBalance(), 25.0);
  });
}
