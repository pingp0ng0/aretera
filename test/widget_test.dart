import 'package:bivi/widgets/topo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BiviLogo 와 EmptyState 가 렌더링된다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BiviLogo(size: 48),
              Expanded(
                child: EmptyState(icon: Icons.backpack, title: '비어 있음', message: '장비를 등록하세요'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Bivi 로고'), findsOneWidget);
    expect(tester.takeException(), isNull); // badge asset resolves
    expect(find.text('비어 있음'), findsOneWidget);
  });
}
