import 'dart:convert';
import 'dart:io';

import 'package:bivi/models/campsite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final raw = File('assets/data/blog_spots.json').readAsStringSync();
  final spots = [for (final j in jsonDecode(raw) as List) Campsite.fromJson(j as Map<String, dynamic>)];

  test('bundled review spots parse as review type and are never legal', () {
    expect(spots, isNotEmpty);
    expect(spots.every((s) => s.type == CampsiteType.review), isTrue);
    expect(spots.every((s) => !s.isLegal), isTrue);
  });

  test('every review spot has source links and a mention count', () {
    expect(spots.every((s) => s.links.isNotEmpty && (s.mentions ?? 0) >= 3), isTrue);
  });

  test('coordinates are inside South Korea', () {
    for (final s in spots) {
      expect(s.lat, inInclusiveRange(33.0, 38.7), reason: s.name);
      expect(s.lng, inInclusiveRange(124.5, 131.0), reason: s.name);
    }
  });

  test('JSON round trip keeps review fields', () {
    final s = spots.firstWhere((s) => s.nationalPark != null, orElse: () => spots.first);
    final back = Campsite.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.mentions, s.mentions);
    expect(back.nationalPark, s.nationalPark);
    expect(back.links.length, s.links.length);
  });
}
