import 'dart:convert';

import 'package:bivi/models/gear_item.dart';
import 'package:bivi/providers/core_providers.dart';
import 'package:bivi/providers/gear_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(sp)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('fresh install starts with the 7 built-in categories', () async {
    final c = await _container();
    expect(c.read(gearCategoriesProvider).map((e) => e.id),
        ['shelter', 'sleep', 'clothing', 'cook', 'safety', 'myog', 'etc']);
  });

  test('gear saved by the old enum version still matches built-in categories', () async {
    final legacy = jsonEncode([
      {'id': 'a', 'name': '텐트', 'category': 'shelter', 'weight_grams': 650, 'is_packed': true},
      {'id': 'b', 'name': '구급약', 'category': 'safety', 'weight_grams': 180, 'is_packed': false},
    ]);
    final c = await _container({'my_gear_v1': legacy});
    final ids = c.read(gearCategoriesProvider).map((e) => e.id).toSet();
    expect(c.read(gearProvider).every((g) => ids.contains(g.categoryId)), isTrue);
  });

  test('add, rename and re-icon a category; it is persisted', () async {
    final c = await _container();
    final created = c.read(gearCategoriesProvider.notifier).add(name: '식수', icon: 'water');
    c.read(gearCategoriesProvider.notifier).update(created.id, name: '물·정수', icon: 'food');

    final sp = c.read(sharedPrefsProvider);
    final stored = (jsonDecode(sp.getString('gear_categories_v1')!) as List).cast<Map<String, dynamic>>();
    final saved = stored.firstWhere((j) => j['id'] == created.id);
    expect(saved['name'], '물·정수');
    expect(saved['icon'], 'food');
  });

  test('deleting a category moves its gear instead of deleting it', () async {
    final c = await _container();
    final before = c.read(gearProvider).where((g) => g.categoryId == 'myog').length;
    expect(before, greaterThan(0));

    c.read(gearCategoriesProvider.notifier).remove('myog', moveTo: 'etc');

    expect(c.read(gearCategoriesProvider).any((x) => x.id == 'myog'), isFalse);
    expect(c.read(gearProvider).where((g) => g.categoryId == 'myog'), isEmpty);
    expect(c.read(gearProvider).where((g) => g.categoryId == 'etc').length, greaterThanOrEqualTo(before));
  });

  test('the last remaining category cannot be deleted', () async {
    final c = await _container({
      'gear_categories_v1': jsonEncode([const GearCategory(id: 'only', name: '전부', icon: 'pack').toJson()]),
    });
    c.read(gearCategoriesProvider.notifier).remove('only', moveTo: 'nowhere');
    expect(c.read(gearCategoriesProvider).single.id, 'only');
  });

  test('editing an item changes name, weight and category but keeps packed state', () async {
    final c = await _container();
    final item = c.read(gearProvider).firstWhere((g) => g.isPacked);
    c.read(gearProvider.notifier).update(item.id, name: '새 이름', categoryId: 'etc', weightGrams: 123);

    final edited = c.read(gearProvider).firstWhere((g) => g.id == item.id);
    expect((edited.name, edited.categoryId, edited.weightGrams, edited.isPacked), ('새 이름', 'etc', 123, true));
  });

  test('no tab badge once the safety category is deleted', () async {
    final c = await _container();
    expect(c.read(missingSafetyProvider), isTrue); // seed gear leaves safety unpacked
    c.read(gearCategoriesProvider.notifier).remove(safetyCategoryId, moveTo: 'etc');
    expect(c.read(missingSafetyProvider), isFalse);
  });
}
