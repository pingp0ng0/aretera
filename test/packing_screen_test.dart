import 'package:bivi/providers/core_providers.dart';
import 'package:bivi/screens/packing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(sp)],
    child: const MaterialApp(home: PackingScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('safety warning banner is gone even with no safety gear packed', (tester) async {
    await _pump(tester);
    expect(find.text('안전 장비가 누락되었습니다'), findsNothing);
  });

  testWidgets('gear ⋮ menu edits name and weight', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('수정 · 삭제').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();

    expect(find.text('장비 수정'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '장비명'), '테스트 텐트');
    await tester.enterText(find.widgetWithText(TextField, '무게'), '777');
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('테스트 텐트'), findsOneWidget);
    expect(find.text('777 g'), findsOneWidget);
  });

  testWidgets('category manager adds a category that shows up as a filter chip', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('카테고리 관리'));
    await tester.pumpAndSettle();
    expect(find.text('카테고리 관리'), findsOneWidget);

    await tester.tap(find.text('카테고리 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '이름'), '식수');
    await tester.pump(); // let the add button enable before tapping it
    await tester.tap(find.widgetWithText(FilledButton, '추가'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.widgetWithText(ListTile, '식수'), findsOneWidget); // listed in the sheet

    Navigator.of(tester.element(find.text('카테고리 관리'))).pop();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '식수'), findsOneWidget);
  });
}
