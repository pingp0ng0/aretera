import 'dart:convert';

import 'package:bivi/services/hike_insights.dart';
import 'package:bivi/services/report_service.dart';
import 'package:bivi/widgets/report_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'hike_test_utils.dart';

void main() {
  final now = DateTime(2026, 10, 23);
  final records = [
    fakeRecord(
        id: 'a', start: DateTime(2026, 10, 3, 7, 12), packGrams: 6000, rating: 2, gainM: 400,
        place: '북한산 백운대', memo: '물 2L 부족했음'),
    fakeRecord(id: 'b', start: DateTime(2026, 9, 12, 6, 40), packGrams: 9000, rating: 4, gainM: 900, movingMin: 240),
    fakeRecord(id: 'c', start: DateTime(2026, 9, 1, 8), packGrams: 12000, rating: 4, gainM: 1100, movingMin: 300),
    fakeRecord(id: 'd', start: DateTime(2026, 8, 1), distanceM: 200, gainM: 0, movingMin: 5, restMin: 0),
  ];
  final input = buildReportInput(records, HikeInsights.from(records, now: now));
  final text = jsonEncode(input);

  test('summary carries no places, memos, coordinates or exact dates', () {
    expect(text, isNot(contains('북한산')));
    expect(text, isNot(contains('물 2L')));
    expect(text, isNot(contains('2026-10-03')));
    expect(text, isNot(contains('lat')));
    expect(text, isNot(contains('lng')));
    expect(text, contains('"month":"2026-10"'));
  });

  test('summary numbers come from the app statistics', () {
    // 210 + 270 + 330 + 5 minutes = 13.6 h
    expect(input['totals'], {'hikes': 4, 'distance_km': 24.2, 'gain_m': 2400, 'hours': 13.6});
    expect((input['months'] as List).length, 3); // Aug, Sep, Oct — empty months are left out
    expect(input['effort']['based_on'], 3);
    expect(input['pack']['pct_per_kg'], lessThan(0)); // heavier pack → slower in this data
    expect((input['recent'] as List).length, 3); // the 200 m record is too short for statistics
    expect((input['recent'] as List).first, containsPair('pack_kg', 6.0));
    expect(utf8.encode(text).length, lessThan(20000)); // the function's input limit
  });

  test('saved report round-trips and shows a short model name', () {
    final r = AiReport(
      text: '## 한눈에 보기\n- 꾸준히 다녀오셨어요.',
      model: 'nvidia/nemotron-3.5-lightning:free',
      createdAt: DateTime(2026, 10, 26, 9, 30),
      input: text,
    );
    final back = AiReport.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
    expect(back.text, r.text);
    expect(back.input, text);
    expect(back.createdAt.isAtSameMomentAs(r.createdAt), isTrue);
    expect(back.modelLabel, 'nemotron-3.5-lightning');
  });

  testWidgets('report text renders headings and bullets without the markup', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ReportText('## 한눈에 보기\n- 6회 다녀오셨어요.\n\n## 다음 산행 제안\n그냥 문단이에요.')),
    ));
    expect(find.text('한눈에 보기'), findsOneWidget);
    expect(find.text('다음 산행 제안'), findsOneWidget);
    expect(find.text('6회 다녀오셨어요.'), findsOneWidget);
    expect(find.text('그냥 문단이에요.'), findsOneWidget);
    expect(find.textContaining('##'), findsNothing);
  });
}
