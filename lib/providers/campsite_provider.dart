import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories.dart';
import '../models/campsite.dart';
import 'core_providers.dart';

final campsiteRepositoryProvider = Provider(
  (ref) => CampsiteRepository(ref.watch(sharedPrefsProvider), ref.watch(supabaseClientProvider)),
);

final campsitesProvider = FutureProvider<List<Campsite>>(
  (ref) => ref.watch(campsiteRepositoryProvider).fetchAll(),
);

/// null = 전체
final campsiteFilterProvider = StateProvider<CampsiteType?>((ref) => null);

final filteredCampsitesProvider = Provider<AsyncValue<List<Campsite>>>((ref) {
  final filter = ref.watch(campsiteFilterProvider);
  return ref
      .watch(campsitesProvider)
      .whenData((list) => filter == null ? list : list.where((c) => c.type == filter).toList());
});
