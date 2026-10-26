import 'dart:convert';
import 'dart:io';

import 'package:bivi/providers/core_providers.dart';
import 'package:bivi/screens/records_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hike_test_utils.dart';

Future<void> _pump(WidgetTester tester, Map<String, Object> prefsValues) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final sp = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(sp),
      recordsDirProvider.overrideWithValue(Directory.systemTemp),
    ],
    child: const MaterialApp(home: RecordsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no records → mascot empty state', (tester) async {
    await _pump(tester, {});
    expect(find.text('아직 산행 기록이 없어요'), findsOneWidget);
  });

  testWidgets('list shows place, distance and climb; analysis tab shows totals', (tester) async {
    final records = [
      fakeRecord(id: 'a', start: DateTime(2026, 10, 3, 8), place: '북한산 백운대', distanceM: 8400, gainM: 720, rating: 4),
      fakeRecord(id: 'b', start: DateTime(2026, 9, 12, 7), packGrams: 9000),
    ];
    await _pump(tester, {
      'hike_records_v1': jsonEncode([for (final r in records) r.toJson()]),
    });

    expect(find.text('북한산 백운대'), findsOneWidget);
    expect(find.text('이름 없는 산행'), findsOneWidget);
    expect(find.text('8.40 km'), findsOneWidget);
    expect(find.text('+720 m'), findsOneWidget);
    expect(find.text('2026년 10월'), findsOneWidget);

    await tester.tap(find.text('분석'));
    await tester.pumpAndSettle();
    expect(find.text('누적 기록'), findsOneWidget);
    expect(find.text('2회'), findsOneWidget);
    expect(find.text('다음 코스 예상 소요 시간'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '거리'), '10');
    await tester.pump();
    expect(find.textContaining('약 '), findsOneWidget);
  });
}
