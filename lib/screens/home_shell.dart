import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/gear_provider.dart';
import '../providers/safe_trip_provider.dart';
import '../theme/app_theme.dart';
import 'map_screen.dart';
import 'packing_screen.dart';
import 'records_screen.dart';
import 'safe_trip_screen.dart';

/// Selected bottom tab. Other screens can switch tabs (e.g. finish hike → 기록).
final homeTabProvider = StateProvider<int>((ref) => 0);

const recordsTabIndex = 3;

/// 4탭 하단 네비게이션. IndexedStack 으로 지도 상태(줌·위치)를 유지한다.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabProvider);
    final missingSafety = ref.watch(missingSafetyProvider);
    final tripActive = ref.watch(safeTripProvider.select((s) => s.active));

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [MapScreen(), PackingScreen(), SafeTripScreen(), RecordsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(homeTabProvider.notifier).state = i,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: '탐색',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: missingSafety,
              backgroundColor: BiviColors.amber,
              smallSize: 9,
              child: const Icon(Icons.backpack_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: missingSafety,
              backgroundColor: BiviColors.amber,
              smallSize: 9,
              child: const Icon(Icons.backpack),
            ),
            label: '내 배낭',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: tripActive,
              backgroundColor: BiviColors.forestLight,
              smallSize: 9,
              child: const Icon(Icons.hiking),
            ),
            selectedIcon: const Icon(Icons.hiking),
            label: '산행 모드',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '기록',
          ),
        ],
      ),
    );
  }
}
