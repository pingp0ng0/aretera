import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trip.dart';
import '../providers/core_providers.dart';
import '../providers/gpx_provider.dart';
import '../providers/safe_trip_provider.dart';
import '../services/battery_guard.dart';
import '../services/temperature_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/mascot.dart';
import '../widgets/topo.dart';
import 'finish_trip_screen.dart';
import 'route_follow_screen.dart';
import 'sos_card_screen.dart';

/// Tab 3: 산행 모드 (세이프 트립)
class SafeTripScreen extends ConsumerWidget {
  const SafeTripScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(safeTripProvider);

    void showMessage(String? prev, String? next) {
      if (next != null && next != prev) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next)));
      }
    }

    ref.listen<String?>(safeTripProvider.select((s) => s.message), showMessage);
    ref.listen<String?>(gpxProvider.select((s) => s.message), showMessage);

    return Scaffold(
      appBar: AppBar(
        title: const Text('산행 모드'),
        actions: [
          if (trip.active)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 10, color: BiviColors.forestLight),
                  SizedBox(width: 6),
                  Text('위치 저장 중', style: TextStyle(color: BiviColors.forestLight)),
                ],
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!trip.active) _StartCard(trip: trip) else ...[
            _CountdownCard(trip: trip),
            const SizedBox(height: 12),
            _TemperatureCard(trip: trip),
            const SizedBox(height: 12),
            _GpsCard(trip: trip),
          ],
          const SizedBox(height: 12),
          const _RouteCard(),
          const SizedBox(height: 16),
          const _SosTrigger(),
          const SizedBox(height: 16),
          const _MedicalCard(),
          if (trip.active) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: BiviColors.textPrimary,
                side: const BorderSide(color: BiviColors.contour),
              ),
              // Opens the finish screen; the hike record is saved there (PRD_step5).
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(fullscreenDialog: true, builder: (_) => const FinishTripScreen()),
              ),
              icon: const Icon(Icons.flag),
              label: const Text('하산 완료 · 산행 종료'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> pickTargetTime(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final current = ref.read(safeTripProvider).targetTime ?? now.add(const Duration(hours: 6));
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(current),
    helpText: '예정 하산 시간',
  );
  if (picked == null) return;
  var target = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
  if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
  ref.read(safeTripProvider.notifier).setTargetTime(target);
}

class _StartCard extends ConsumerWidget {
  const _StartCard({required this.trip});

  final SafeTripState trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = trip.targetTime;
    return TopoCard(
      seed: 5,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('산행 시작 전 준비', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    SizedBox(height: 8),
                    Text(
                      '시작하면 현재 좌표·고도를 기기에 주기적으로 저장하고, 주변 지형도 일부를 오프라인용으로 내려받습니다. '
                      '전파가 끊겨도 SOS 카드에서 마지막 좌표를 바로 확인할 수 있어요.',
                      style: TextStyle(color: BiviColors.textSecondary, height: 1.5),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              MascotImage(Mascot.hiking, height: 104),
            ],
          ),
          const _BatteryTip(),
          const SizedBox(height: 16),
          Material(
            color: BiviColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: const Icon(Icons.schedule, color: BiviColors.forestLight),
              title: const Text('예정 하산 시간'),
              subtitle: Text(target == null ? '설정 필요' : '${formatDate(target)} ${formatTime(target)}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => pickTargetTime(context, ref),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: BiviColors.forest,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            onPressed: trip.busy
                ? null
                : () async {
                    if (ref.read(safeTripProvider).targetTime == null) {
                      await pickTargetTime(context, ref);
                    }
                    await ref.read(safeTripProvider.notifier).start();
                  },
            icon: trip.busy
                ? const SizedBox.square(
                    dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.hiking),
            label: Text(trip.busy ? 'GPS 확인 중…' : '산행 시작'),
          ),
        ],
      ),
    );
  }
}

/// Before a hike: if Android may still put Bivi to sleep, offer the exemption (PRD_step5 5-5).
class _BatteryTip extends ConsumerStatefulWidget {
  const _BatteryTip();

  @override
  ConsumerState<_BatteryTip> createState() => _BatteryTipState();
}

class _BatteryTipState extends ConsumerState<_BatteryTip> {
  // The system dialog returns to the app; read the setting again then.
  late final _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(batteryUnrestrictedProvider));

  @override
  void initState() {
    super.initState();
    _lifecycle; // create the listener now
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(batteryUnrestrictedProvider).valueOrNull != false) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: BiviColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.battery_alert, color: BiviColors.amber),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '긴 산행 전에: 배터리 사용을 \'제한 없음\'으로 허용하면 폰이 앱을 재우지 않아 기록이 끊기지 않아요.',
              style: TextStyle(height: 1.4, fontSize: 13),
            ),
          ),
          TextButton(onPressed: BatteryGuard.requestUnrestricted, child: const Text('허용하기')),
        ],
      ),
    );
  }
}

class _CountdownCard extends ConsumerWidget {
  const _CountdownCard({required this.trip});

  final SafeTripState trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now();
    final target = trip.targetTime!;
    final remaining = target.difference(now);
    final overdue = remaining.isNegative;
    final started = trip.startedAt ?? now;
    final total = target.difference(started).inSeconds;
    final progress = total <= 0 ? 1.0 : (now.difference(started).inSeconds / total).clamp(0.0, 1.0);
    final accent = overdue ? BiviColors.amber : BiviColors.forestLight;

    return TopoCard(
      seed: 9,
      color: overdue ? const Color(0xFF2A1A12) : BiviColors.surface,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(overdue ? '예정 하산 시간 초과' : '하산까지 남은 시간',
              style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '${overdue ? '+' : ''}${formatHms(remaining)}',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: overdue ? BiviColors.amber : BiviColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: accent,
              backgroundColor: BiviColors.surfaceHigh,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('시작 ${formatTime(started)}', style: const TextStyle(color: BiviColors.textSecondary)),
              const Spacer(),
              Text('예정 하산 ${formatTime(target)}',
                  style: const TextStyle(color: BiviColors.textSecondary)),
            ],
          ),
          if (overdue) ...[
            const SizedBox(height: 12),
            const Text(
              '안전하다면 하산 시간을 연장하세요. 보호자 자동 알림은 서버 연동 후 활성화됩니다.',
              style: TextStyle(color: BiviColors.amber, height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () =>
                    ref.read(safeTripProvider.notifier).extendTarget(const Duration(minutes: 30)),
                icon: const Icon(Icons.more_time),
                label: const Text('+30분 연장'),
              ),
              TextButton.icon(
                onPressed: () => pickTargetTime(context, ref),
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('시간 변경'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemperatureCard extends ConsumerWidget {
  const _TemperatureCard({required this.trip});

  final SafeTripState trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = trip.lastPosition;
    final base = trip.baseTempC;
    final baseAlt = trip.baseAltitudeM;
    final corrected = (pos != null && base != null && baseAlt != null)
        ? TemperatureService.altitudeCorrected(
            baseTempC: base, baseAltitudeM: baseAlt, currentAltitudeM: pos.altitude)
        : null;
    final feels = corrected == null ? null : TemperatureService.feelsLike(corrected, trip.windMs ?? 0);

    return _Card(
      icon: Icons.thermostat,
      title: '고도 보정 체감 온도',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            feels == null ? '-- °C' : '${feels.toStringAsFixed(1)} °C',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: (feels ?? 99) <= 0 ? Colors.lightBlue.shade200 : BiviColors.textPrimary,
            ),
          ),
          if (corrected != null && feels != corrected)
            Text('기온 ${corrected.toStringAsFixed(1)}°C · 바람 ${trip.windMs!.toStringAsFixed(1)} m/s 반영',
                style: const TextStyle(color: BiviColors.textSecondary)),
          const SizedBox(height: 10),
          _kv('현재 고도', pos == null ? '-' : '${pos.altitude.round()} m'),
          _kv('기준(들머리) 고도', baseAlt == null ? '-' : '${baseAlt.round()} m'),
          _kv(
            '기준 기온',
            base == null
                ? '미수신'
                : '${base.toStringAsFixed(1)}°C'
                    '${trip.weatherObservedAt == null ? '' : ' · ${formatTime(trip.weatherObservedAt!)} 기준'}',
          ),
          const SizedBox(height: 8),
          const Text(
            '기상청 기온에 100m 상승당 약 0.65°C 하강을 적용한 보수적 추정치입니다. 실제 산악 미기후와 다를 수 있습니다.',
            style: TextStyle(color: BiviColors.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (ref.watch(supabaseClientProvider) != null)
                TextButton.icon(
                  onPressed: () => ref.read(safeTripProvider.notifier).refreshWeather(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('기상청 갱신'),
                ),
              TextButton.icon(
                onPressed: () => _manualInput(context, ref),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('기준 기온 입력'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _manualInput(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(double, double?)>(
      context: context,
      builder: (_) => const _ManualWeatherDialog(),
    );
    if (result == null) return;
    ref.read(safeTripProvider.notifier).setManualWeather(tempC: result.$1, windMs: result.$2);
  }
}

class _GpsCard extends ConsumerWidget {
  const _GpsCard({required this.trip});

  final SafeTripState trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = trip.lastPosition;
    final now = ref.watch(nowProvider).valueOrNull ?? DateTime.now();
    return _Card(
      icon: Icons.gps_fixed,
      title: '로컬 캐싱된 위치',
      child: pos == null
          ? const Text('GPS 신호 대기 중…', style: TextStyle(color: BiviColors.textSecondary))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('위도', pos.lat.toStringAsFixed(5)),
                _kv('경도', pos.lng.toStringAsFixed(5)),
                _kv('고도', '${pos.altitude.round()} m'),
                _kv('정확도', '±${pos.accuracy.round()} m'),
                _kv('저장 시각', '${formatTime(pos.timestamp)} (${formatAgo(pos.timestamp, now)})'),
                _kv('오프라인 지도', '${trip.cachedTiles}개 타일 저장됨'),
              ],
            ),
    );
  }
}

class _SosTrigger extends StatelessWidget {
  const _SosTrigger();

  void _open(BuildContext context) {
    HapticFeedback.heavyImpact();
    Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SosCardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -250) _open(context);
      },
      child: Material(
        color: BiviColors.amber,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _open(context),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 22, horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.sos, size: 44, color: Colors.black),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('비상 원터치 카드',
                          style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w900)),
                      SizedBox(height: 2),
                      Text('탭 또는 위로 스와이프 · 오프라인에서도 동작',
                          style: TextStyle(color: Colors.black87)),
                    ],
                  ),
                ),
                Icon(Icons.keyboard_double_arrow_up, color: Colors.black),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MedicalCard extends ConsumerWidget {
  const _MedicalCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final med = ref.watch(medicalInfoProvider);
    String v(String s) => s.isEmpty ? '미입력' : s;
    return _Card(
      icon: Icons.medical_information_outlined,
      title: '의료 정보 · 비상 연락처',
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: () async {
          final result = await showDialog<MedicalInfo>(
            context: context,
            builder: (_) => _MedicalDialog(initial: med),
          );
          if (result != null) ref.read(medicalInfoProvider.notifier).save(result);
        },
      ),
      child: med.isEmpty
          ? const Text('SOS 카드에 표시될 혈액형 · 기저질환 · 비상 연락처를 미리 등록하세요.',
              style: TextStyle(color: BiviColors.amber, height: 1.4))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('혈액형', v(med.bloodType)),
                _kv('기저질환', v(med.conditions)),
                _kv('알레르기', v(med.allergies)),
                _kv('복용 약', v(med.medications)),
                _kv('비상 연락처', med.contactPhone.isEmpty ? '미입력' : '${med.contactName} ${med.contactPhone}'),
              ],
            ),
    );
  }
}

// ───────────────────────── 공용 위젯 ─────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.child, this.trailing});

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 16),
      decoration: BoxDecoration(
        color: BiviColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: BiviColors.forestLight),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(k, style: const TextStyle(color: BiviColors.textSecondary)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );

class _ManualWeatherDialog extends StatefulWidget {
  const _ManualWeatherDialog();

  @override
  State<_ManualWeatherDialog> createState() => _ManualWeatherDialogState();
}

class _ManualWeatherDialogState extends State<_ManualWeatherDialog> {
  final _temp = TextEditingController();
  final _wind = TextEditingController();

  @override
  void dispose() {
    _temp.dispose();
    _wind.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const numeric = TextInputType.numberWithOptions(decimal: true, signed: true);
    return AlertDialog(
      title: const Text('기준 기온 입력'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('현재 위치(고도)에서의 기온을 입력하면, 이후 고도 변화에 따라 보정됩니다.',
              style: TextStyle(color: BiviColors.textSecondary)),
          TextField(
            controller: _temp,
            keyboardType: numeric,
            decoration: const InputDecoration(labelText: '기온', suffixText: '°C'),
          ),
          TextField(
            controller: _wind,
            keyboardType: numeric,
            decoration: const InputDecoration(labelText: '풍속 (선택)', suffixText: 'm/s'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () {
            final t = double.tryParse(_temp.text.trim());
            if (t == null) return;
            Navigator.pop(context, (t, double.tryParse(_wind.text.trim())));
          },
          child: const Text('적용'),
        ),
      ],
    );
  }
}

class _MedicalDialog extends StatefulWidget {
  const _MedicalDialog({required this.initial});

  final MedicalInfo initial;

  @override
  State<_MedicalDialog> createState() => _MedicalDialogState();
}

class _MedicalDialogState extends State<_MedicalDialog> {
  late final _blood = TextEditingController(text: widget.initial.bloodType);
  late final _conditions = TextEditingController(text: widget.initial.conditions);
  late final _allergies = TextEditingController(text: widget.initial.allergies);
  late final _meds = TextEditingController(text: widget.initial.medications);
  late final _contactName = TextEditingController(text: widget.initial.contactName);
  late final _contactPhone = TextEditingController(text: widget.initial.contactPhone);

  @override
  void dispose() {
    for (final c in [_blood, _conditions, _allergies, _meds, _contactName, _contactPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {String? hint, TextInputType? type}) =>
        TextField(
          controller: c,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, hintText: hint),
        );

    return AlertDialog(
      title: const Text('의료 정보'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('이 정보는 기기에만 저장되며 서버로 전송되지 않습니다.',
                style: TextStyle(color: BiviColors.textSecondary, fontSize: 12)),
            field(_blood, '혈액형', hint: '예: A형 Rh+'),
            field(_conditions, '기저질환', hint: '예: 천식, 고혈압'),
            field(_allergies, '알레르기', hint: '예: 페니실린'),
            field(_meds, '복용 중인 약'),
            field(_contactName, '비상 연락처 이름', hint: '예: 어머니'),
            field(_contactPhone, '비상 연락처 번호', type: TextInputType.phone),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            MedicalInfo(
              bloodType: _blood.text.trim(),
              conditions: _conditions.text.trim(),
              allergies: _allergies.text.trim(),
              medications: _meds.text.trim(),
              contactName: _contactName.text.trim(),
              contactPhone: _contactPhone.text.trim(),
            ),
          ),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// GPX 경로 불러오기 · 따라가기 진입
class _RouteCard extends ConsumerWidget {
  const _RouteCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gpx = ref.watch(gpxProvider);
    final route = gpx.route;
    final notifier = ref.read(gpxProvider.notifier);

    return _Card(
      icon: Icons.route,
      title: 'GPX 경로 따라가기',
      trailing: route == null
          ? null
          : IconButton(
              tooltip: '경로 삭제',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => notifier.clear(),
            ),
      child: route == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '등산 앱이나 산악회에서 받은 GPX 파일을 불러오면, 지도에서 내 위치와 남은 거리를 보며 따라갈 수 있어요. '
                        '경로 주변 지도는 오프라인용으로 함께 저장됩니다.',
                        style: TextStyle(color: BiviColors.textSecondary, height: 1.5),
                      ),
                    ),
                    SizedBox(width: 8),
                    MascotImage(Mascot.mapReading, height: 88),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: BiviColors.forest,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => notifier.importFromPicker(),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('GPX 파일 불러오기'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(route.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                _kv('총 거리', formatDistance(route.totalMeters)),
                _kv('누적 상승', '${route.elevationGain.round()} m'),
                _kv('경유지', '${route.waypoints.length}곳'),
                if (gpx.prefetching) ...[
                  const SizedBox(height: 8),
                  Text('오프라인 지도 저장 중… ${gpx.tilesDone}/${gpx.tilesTotal}',
                      style: const TextStyle(color: BiviColors.textSecondary)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: gpx.tilesDone / gpx.tilesTotal),
                ] else if (gpx.tilesTotal > 0)
                  _kv('오프라인 지도', '${gpx.tilesSaved}/${gpx.tilesTotal} 타일 저장됨'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: BiviColors.forest,
                    minimumSize: const Size.fromHeight(52),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RouteFollowScreen()),
                  ),
                  icon: const Icon(Icons.navigation),
                  label: const Text('지도에서 따라가기'),
                ),
                TextButton.icon(
                  onPressed: () => notifier.importFromPicker(),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('다른 GPX 불러오기'),
                ),
              ],
            ),
    );
  }
}
