import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/core_providers.dart';
import '../providers/safe_trip_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 비상 원터치 카드 — 네트워크 호출 없이 로컬 캐시만으로 즉시 렌더링 (고대비)
class SosCardScreen extends ConsumerWidget {
  const SosCardScreen({super.key});

  static const _label = TextStyle(color: BiviColors.amber, fontSize: 16, fontWeight: FontWeight.w800);
  static const _big = TextStyle(
    color: Colors.white,
    fontSize: 34,
    fontWeight: FontWeight.w900,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const _mid = TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700);
  static const _small = TextStyle(color: Colors.white70, fontSize: 16);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(safeTripProvider.select((s) => s.lastPosition));
    final med = ref.watch(medicalInfoProvider);
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now();

    Widget field(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k, style: _small),
              Text(v.isEmpty ? '미입력' : v, style: _mid),
            ],
          ),
        );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Row(
              children: [
                const Text('SOS',
                    style: TextStyle(color: BiviColors.amber, fontSize: 44, fontWeight: FontWeight.w900)),
                const SizedBox(width: 12),
                const Expanded(child: Text('비상 정보 카드', style: _mid)),
                IconButton(
                  iconSize: 36,
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('현재 위치 (마지막 저장 좌표)', style: _label),
            const SizedBox(height: 8),
            if (pos == null)
              const Text('저장된 좌표가 없습니다.\n산행 모드를 시작하면 위치가 기기에 저장됩니다.', style: _mid)
            else ...[
              Text('위도  ${pos.lat.toStringAsFixed(5)}', style: _big),
              Text('경도  ${pos.lng.toStringAsFixed(5)}', style: _big),
              const SizedBox(height: 4),
              Text('${toDms(pos.lat, isLat: true)}\n${toDms(pos.lng, isLat: false)}', style: _small),
              const SizedBox(height: 12),
              Text('고도  ${pos.altitude.round()} m', style: _big),
              const SizedBox(height: 8),
              Text(
                '${formatDate(pos.timestamp)} ${formatTime(pos.timestamp)} 저장 · '
                '${formatAgo(pos.timestamp, now)} · 오차 ±${pos.accuracy.round()}m',
                style: _small,
              ),
            ],
            const Divider(color: Colors.white24, height: 40),
            const Text('의료 정보', style: _label),
            field('혈액형', med.bloodType),
            field('기저질환', med.conditions),
            field('알레르기', med.allergies),
            field('복용 중인 약', med.medications),
            const Divider(color: Colors.white24, height: 40),
            const Text('비상 연락처', style: _label),
            field(med.contactName.isEmpty ? '보호자' : med.contactName, med.contactPhone),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: BiviColors.amber,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(64),
                textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: '119')),
              icon: const Icon(Icons.call, size: 28),
              label: const Text('119 긴급 전화'),
            ),
            if (med.contactPhone.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: med.contactPhone)),
                icon: const Icon(Icons.contact_phone),
                label: Text('${med.contactName.isEmpty ? '보호자' : med.contactName}에게 전화'),
              ),
            ],
            const SizedBox(height: 16),
            const Text('구조대에 위 위도 · 경도와 고도를 그대로 불러주세요.', style: _small),
          ],
        ),
      ),
    );
  }
}
