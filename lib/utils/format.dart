import 'dart:math';

final _rnd = Random.secure();

/// Supabase uuid PK 와 호환되는 v4 UUID
String uuidV4() {
  final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

String two(int n) => n.toString().padLeft(2, '0');

String formatKg(int grams, {int digits = 2}) => (grams / 1000).toStringAsFixed(digits);

String formatDate(DateTime d) => '${d.year}.${two(d.month)}.${two(d.day)}';

String formatTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 2026.10.23 (금)
String formatDateWeekday(DateTime d) => '${formatDate(d)} (${_weekdays[d.weekday - 1]})';

String formatDistance(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(m >= 10000 ? 1 : 2)} km' : '${m.round()} m';

/// 3시간 25분 · 45분
String formatDuration(Duration d) {
  final minutes = (d.inSeconds / 60).round();
  if (minutes < 60) return '$minutes분';
  final m = minutes % 60;
  return m == 0 ? '${minutes ~/ 60}시간' : '${minutes ~/ 60}시간 $m분';
}

/// Seconds per km → 18'30"/km
String formatPace(double secPerKm) {
  final s = secPerKm.round();
  return "${s ~/ 60}'${two(s % 60)}\"/km";
}

String formatHms(Duration d) {
  final s = d.inSeconds.abs();
  return '${two(s ~/ 3600)}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
}

String formatAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inSeconds < 60) return '${max(d.inSeconds, 0)}초 전';
  if (d.inMinutes < 60) return '${d.inMinutes}분 전';
  if (d.inHours < 24) return '${d.inHours}시간 ${d.inMinutes % 60}분 전';
  return '${d.inDays}일 전';
}

/// 37.56650 → 37°33'59.4" N
String toDms(double deg, {required bool isLat}) {
  final hemi = isLat ? (deg >= 0 ? 'N' : 'S') : (deg >= 0 ? 'E' : 'W');
  final a = deg.abs();
  final d = a.floor();
  final minutesFull = (a - d) * 60;
  final m = minutesFull.floor();
  final s = (minutesFull - m) * 60;
  return '$d°${two(m)}\'${s.toStringAsFixed(1).padLeft(4, '0')}" $hemi';
}
