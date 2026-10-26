import 'dart:convert';
import 'dart:io';

import 'package:bivi/providers/core_providers.dart';
import 'package:bivi/screens/packing_screen.dart';
import 'package:bivi/screens/records_screen.dart';
import 'package:bivi/widgets/mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every Mascot entry has a file in assets/character', () {
    final missing = [for (final m in Mascot.values) if (!File(m.asset).existsSync()) m.asset];
    expect(missing, isEmpty);
  });

  testWidgets('records tab shows the viewing mascot', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(sp),
        recordsDirProvider.overrideWithValue(Directory.systemTemp),
      ],
      child: const MaterialApp(home: RecordsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(Mascot.viewing.label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty pack shows the mascot instead of the icon badge', (tester) async {
    SharedPreferences.setMockInitialValues({'my_gear_v1': jsonEncode([])});
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(sp)],
      child: const MaterialApp(home: PackingScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(Mascot.back.label), findsOneWidget);
    expect(find.byIcon(Icons.backpack_outlined), findsNothing);
  });
}
