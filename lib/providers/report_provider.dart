import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/report_service.dart';
import 'core_providers.dart';
import 'records_provider.dart';

class AiReportState {
  const AiReportState({this.report, this.busy = false, this.error});

  final AiReport? report;
  final bool busy;
  final String? error;
}

/// Last AI report (kept on the device) and the in-flight request (PRD_step6 6-3).
final aiReportProvider = NotifierProvider<AiReportNotifier, AiReportState>(AiReportNotifier.new);

/// Summary JSON for today's records; compared with the saved report's input to spot a stale report.
final reportInputProvider = Provider<Map<String, dynamic>>(
  (ref) => buildReportInput(ref.watch(hikeRecordsProvider), ref.watch(hikeInsightsProvider)),
);

class AiReportNotifier extends Notifier<AiReportState> {
  static const _key = 'ai_report_v1';

  @override
  AiReportState build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_key);
    if (raw == null) return const AiReportState();
    try {
      return AiReportState(report: AiReport.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    } catch (e) {
      debugPrint('saved AI report unreadable: $e');
      return const AiReportState();
    }
  }

  /// Forgets the saved report (used when demo hikes are removed, so no demo-based report stays).
  Future<void> clear() async {
    await ref.read(sharedPrefsProvider).remove(_key);
    state = const AiReportState();
  }

  Future<void> generate() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null || state.busy) return;
    final input = ref.read(reportInputProvider);
    state = AiReportState(report: state.report, busy: true);
    try {
      final report = await ReportService(client).generate(input, jsonEncode(input));
      await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(report.toJson()));
      state = AiReportState(report: report);
    } on ReportException catch (e) {
      state = AiReportState(report: state.report, error: e.message);
    }
  }
}
