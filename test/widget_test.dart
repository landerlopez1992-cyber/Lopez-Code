import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lopez_code_ai/main.dart';

void main() {
  test('MyApp es el widget raíz de Voryxel Code', () {
    expect(const MyApp(), isA<StatelessWidget>());
  });
}
