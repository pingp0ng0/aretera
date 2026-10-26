import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories.dart';
import '../data/seed_data.dart';
import '../models/gear_item.dart';
import '../utils/format.dart';
import 'core_providers.dart';

final gearRepositoryProvider = Provider(
  (ref) => GearRepository(ref.watch(sharedPrefsProvider), ref.watch(supabaseClientProvider)),
);

final gearProvider = NotifierProvider<GearNotifier, List<GearItem>>(GearNotifier.new);

class GearNotifier extends Notifier<List<GearItem>> {
  late GearRepository _repo;

  @override
  List<GearItem> build() {
    _repo = ref.watch(gearRepositoryProvider);
    return _repo.loadLocal();
  }

  void togglePacked(String id) {
    state = [
      for (final g in state)
        if (g.id == id) g.copyWith(isPacked: !g.isPacked) else g,
    ];
    _persist(changedId: id);
  }

  void unpackAll() {
    state = [for (final g in state) g.copyWith(isPacked: false)];
    _persist();
  }

  void add({required String name, required String categoryId, required int weightGrams}) {
    final item = GearItem(
      id: uuidV4(),
      name: name,
      categoryId: categoryId,
      weightGrams: weightGrams,
      isPacked: true,
    );
    state = [...state, item];
    _persist(changedId: item.id);
  }

  /// Edit name / category / weight of an existing item (packed state is kept).
  void update(String id, {required String name, required String categoryId, required int weightGrams}) {
    state = [
      for (final g in state)
        if (g.id == id) g.copyWith(name: name, categoryId: categoryId, weightGrams: weightGrams) else g,
    ];
    _persist(changedId: id);
  }

  /// Re-file every item of one category into another (used when a category is deleted).
  void moveCategory(String fromId, String toId) {
    if (!state.any((g) => g.categoryId == fromId)) return;
    state = [
      for (final g in state)
        if (g.categoryId == fromId) g.copyWith(categoryId: toId) else g,
    ];
    _persist();
  }

  void remove(String id) {
    state = state.where((g) => g.id != id).toList();
    _repo.saveLocal(state);
    _repo.deleteRemote(id);
  }

  void _persist({String? changedId}) {
    _repo.saveLocal(state);
    _repo.upsertRemote(
      changedId == null ? state : state.where((g) => g.id == changedId).toList(),
    );
  }
}

final gearCategoriesProvider =
    NotifierProvider<GearCategoriesNotifier, List<GearCategory>>(GearCategoriesNotifier.new);

/// Add / rename / re-icon / delete pack categories (PRD_step3).
class GearCategoriesNotifier extends Notifier<List<GearCategory>> {
  late GearRepository _repo;

  @override
  List<GearCategory> build() {
    _repo = ref.watch(gearRepositoryProvider);
    return _repo.loadCategories();
  }

  /// Returns the new category so callers can select it right away.
  GearCategory add({required String name, required String icon}) {
    final category = GearCategory(id: uuidV4(), name: name, icon: icon);
    state = [...state, category];
    _repo.saveCategories(state);
    return category;
  }

  void update(String id, {required String name, required String icon}) {
    state = [
      for (final c in state)
        if (c.id == id) c.copyWith(name: name, icon: icon) else c,
    ];
    _repo.saveCategories(state);
  }

  /// Deletes [id] after moving its gear into [moveTo]. The last category can't be deleted.
  void remove(String id, {required String moveTo}) {
    if (state.length <= 1 || id == moveTo) return;
    ref.read(gearProvider.notifier).moveCategory(id, moveTo);
    state = state.where((c) => c.id != id).toList();
    _repo.saveCategories(state);
    if (ref.read(gearCategoryFilterProvider) == id) {
      ref.read(gearCategoryFilterProvider.notifier).state = null;
    }
  }
}

/// 패킹 목표 무게 (g)
final packGoalGramsProvider = StateProvider<int>((ref) => 10000);

/// Category filter on the pack screen: a category id, or null for all.
final gearCategoryFilterProvider = StateProvider<String?>((ref) => null);

final packedGearProvider = Provider<List<GearItem>>(
  (ref) => ref.watch(gearProvider).where((g) => g.isPacked).toList(),
);

final packedWeightProvider = Provider<int>(
  (ref) => ref.watch(packedGearProvider).fold(0, (sum, g) => sum + g.weightGrams),
);

/// Pack tab badge: the safety category exists but nothing in it is packed.
/// (The top warning banner was removed in PRD_step3.)
final missingSafetyProvider = Provider<bool>((ref) {
  final hasSafety = ref.watch(gearCategoriesProvider).any((c) => c.id == safetyCategoryId);
  return hasSafety && !ref.watch(packedGearProvider).any((g) => g.categoryId == safetyCategoryId);
});

/// 경량 대체품 추천 대상 (무거운 패킹 장비 중 대체품이 존재하는 것)
final heavyPackedGearProvider = Provider<List<GearItem>>(
  (ref) => ref
      .watch(packedGearProvider)
      .where((g) =>
          g.weightGrams >= heavyItemThresholdGrams &&
          (lightAlternatives[g.categoryId] ?? const []).any((a) => a.weightGrams < g.weightGrams))
      .toList(),
);
