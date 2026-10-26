import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException, SupabaseClient;

import '../models/hike_record.dart';
import '../utils/format.dart';
import 'hike_insights.dart';
import 'server_session.dart';

/// Most recent hikes sent with the summary.
const reportRecentHikes = 10;

double _r1(double v) => (v * 10).roundToDouble() / 10;

String _month(DateTime d) => '${d.year}-${two(d.month)}';

/// What the `hike-report` Edge Function gets (PRD_step6 6-3): numbers the app already computed.
/// Never coordinates, place names, memos or exact dates — months only.
Map<String, dynamic> buildReportInput(List<HikeRecord> records, HikeInsights i) {
  Map<String, dynamic>? slope(SlopeTotals t, {bool vertical = true}) {
    final kmh = t.kmh;
    if (kmh == null) return null;
    return {
      'km_h': _r1(kmh),
      if (vertical && t.verticalPerHour != null) 'vertical_m_h': t.verticalPerHour!.round(),
    };
  }

  final pace = {
    'up': slope(i.up),
    'down': slope(i.down),
    'flat': slope(i.flat, vertical: false),
  }..removeWhere((_, v) => v == null);
  final recent = (records.where(isStatsEligible).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt)))
      .take(reportRecentHikes);

  return {
    'totals': {
      'hikes': i.count,
      'distance_km': _r1(i.distanceM / 1000),
      'gain_m': i.gainM.round(),
      'hours': _r1(i.duration.inMinutes / 60),
    },
    'months': [
      for (final m in i.months)
        if (m.count > 0)
          {'month': _month(m.month), 'hikes': m.count, 'distance_km': _r1(m.distanceM / 1000), 'gain_m': m.gainM.round()},
    ],
    if (pace.isNotEmpty) 'pace': pace,
    if (i.movingRatio != null)
      'rest': {
        'moving_pct': (i.movingRatio! * 100).round(),
        'rests_per_hike': _r1(i.restsPerHike ?? 0),
        if (i.avgRest != null) 'avg_rest_min': (i.avgRest!.inSeconds / 60).round(),
      },
    if (i.pace != null)
      'effort': {
        'min_per_effort_km': _r1(i.pace!.secPerEffortKm / 60),
        'rest_min_per_moving_hour': (i.pace!.restRatio * 60).round(),
        'based_on': i.pace!.basedOn,
      },
    if (i.packPctPerKg != null) 'pack': {'pct_per_kg': _r1(i.packPctPerKg!), 'hikes': i.weightFit!.n},
    'difficulty': [
      for (final MapEntry(key: stars, value: (avg, n)) in i.gainByRating.entries)
        {'stars': stars, 'avg_gain_m': avg.round(), 'hikes': n},
    ],
    'recent': [
      for (final r in recent)
        {
          'month': _month(r.startedAt),
          'distance_km': _r1(r.stats.distanceM / 1000),
          'gain_m': r.stats.gainM.round(),
          'moving_min': (r.stats.movingSec / 60).round(),
          'rest_min': (r.stats.restSec / 60).round(),
          if (r.packWeightGrams != null) 'pack_kg': _r1(r.packWeightGrams! / 1000),
          if (r.rating != null) 'stars': r.rating,
        },
    ],
  };
}

/// A report the AI wrote, kept on the device with the input it was made from.
class AiReport {
  const AiReport({required this.text, required this.model, required this.createdAt, required this.input});

  final String text;
  final String model;
  final DateTime createdAt;

  /// JSON of the summary that was sent; differs from today's summary once records change.
  final String input;

  /// "nvidia/nemotron-3.5-lightning:free" → "nemotron-3.5-lightning"
  String get modelLabel => model.split('/').last.replaceAll(':free', '');

  Map<String, dynamic> toJson() =>
      {'text': text, 'model': model, 'created_at': createdAt.toIso8601String(), 'input': input};

  factory AiReport.fromJson(Map<String, dynamic> j) => AiReport(
        text: j['text'] as String,
        model: j['model'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        input: j['input'] as String? ?? '',
      );
}

class ReportException implements Exception {
  ReportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Calls the `hike-report` Edge Function. Free models can take a while, hence the long timeout.
class ReportService {
  ReportService(this.client);

  final SupabaseClient client;

  Future<AiReport> generate(Map<String, dynamic> input, String inputJson) async {
    try {
      await ensureSignedIn(client);
      final res = await client.functions
          .invoke('hike-report', body: input)
          .timeout(const Duration(seconds: 160));
      final data = res.data as Map<String, dynamic>;
      return AiReport(
        text: data['report'] as String,
        model: data['model'] as String? ?? '',
        createdAt: DateTime.parse(data['generated_at'] as String).toLocal(),
        input: inputJson,
      );
    } on FunctionException catch (e) {
      final code = e.details is Map ? (e.details as Map)['error'] : null;
      throw ReportException(switch (code) {
        'rate_limited' => '무료 AI 모델이 지금 붐벼요. 잠시 후 다시 시도해 주세요.',
        'timeout' || 'model_unreachable' => 'AI 응답이 너무 늦어요. 잠시 후 다시 시도해 주세요.',
        'bad_model_output' => 'AI 답이 이상해서 쓰지 않았어요. 다시 시도해 주세요.',
        'login_required' => '서버 로그인이 만료되었어요. 앱을 다시 열어 주세요.',
        _ => 'AI 리포트 서버 오류 (${code ?? 'HTTP ${e.status}'})',
      });
    } on TimeoutException {
      throw ReportException('AI 응답이 너무 늦어요. 잠시 후 다시 시도해 주세요.');
    } on SocketException {
      throw ReportException(_offline);
    } on Exception catch (e) {
      // http.ClientException / AuthRetryableFetchException wrap the socket error when offline.
      final s = e.toString();
      if (s.contains('SocketException') || s.contains('host lookup') || s.contains('Connection')) {
        throw ReportException(_offline);
      }
      throw ReportException('AI 리포트를 만들지 못했어요: $e');
    }
  }

  static const _offline = '인터넷에 연결되어 있지 않아요. AI 리포트는 온라인에서만 만들 수 있어요.';
}
