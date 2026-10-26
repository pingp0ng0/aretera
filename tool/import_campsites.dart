// 실제 야영지 데이터를 받아 앱 번들(assets/data/campsites.json)과 Supabase 업서트 SQL 을 만든다.
//
//   dart run tool/import_campsites.dart            (env.json 의 KMA_API_KEY = 공공데이터포털 키 사용)
//
// 출처
//  1) 한국관광공사 고캠핑 OpenAPI — 관광진흥법상 등록 야영장 (운영 중 · 일반/자동차야영장만)
//  2) 국립공원공단 예약시스템 대피소 목록(아래 화이트리스트) + 좌표는 OpenStreetMap
//     → 공식 목록에 있고 OSM 에서 좌표를 찾은 대피소만 포함한다.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _ua = 'Bivi/1.0 (com.bivi.bivi; data import)';

/// 국립공원공단 예약시스템 기준 숙박 가능 대피소 (2026-10 확인).
/// 피아골(숙박 불가) · 중청(숙박 중단)은 제외. 키워드는 OSM name 매칭용.
const _officialShelters = <String, List<String>>{
  '지리산국립공원': ['노고단', '로타리|로터리', '벽소령', '세석', '연하천', '장터목', '치밭목'],
  '설악산국립공원': ['소청', '수렴동', '양폭', '희운각'],
  '덕유산국립공원': ['삿갓재'],
  '소백산국립공원': ['제2연화봉'],
};

Future<void> main() async {
  final env = jsonDecode(File('env.json').readAsStringSync()) as Map<String, dynamic>;
  final key = (env['KMA_API_KEY'] as String?) ?? '';
  if (key.isEmpty) {
    stderr.writeln('env.json 에 KMA_API_KEY(공공데이터포털 인증키)가 필요합니다.');
    exit(1);
  }

  final today = DateTime.now().toIso8601String().substring(0, 10);
  final camps = await _fetchGoCamping(key);
  final shelters = await _fetchShelters(today);
  final all = [...shelters, ...camps];

  Directory('assets/data').createSync(recursive: true);
  File('assets/data/campsites.json').writeAsStringSync(jsonEncode(all));
  File('supabase/campsites_import.sql').writeAsStringSync(_toSql(all, today));

  stdout.writeln('대피소 ${shelters.length}곳 + 등록 야영장 ${camps.length}곳 = ${all.length}곳');
  stdout.writeln('→ assets/data/campsites.json, supabase/campsites_import.sql');
}

// ───────────────────────── 고캠핑 ─────────────────────────

Future<List<Map<String, dynamic>>> _fetchGoCamping(String key) async {
  final uri = Uri.https('apis.data.go.kr', '/B551011/GoCamping/basedList', {
    'serviceKey': key,
    'numOfRows': '5000',
    'pageNo': '1',
    'MobileOS': 'AND',
    'MobileApp': 'bivi',
    '_type': 'json',
  });
  final res = await http.get(uri).timeout(const Duration(seconds: 90));
  final body = jsonDecode(utf8.decode(res.bodyBytes))['response']['body'];
  final items = (body['items']['item'] as List).cast<Map<String, dynamic>>();
  stdout.writeln('고캠핑 원본 ${items.length}곳 (totalCount ${body['totalCount']})');

  final out = <Map<String, dynamic>>[];
  for (final i in items) {
    final lat = double.tryParse('${i['mapY']}') ?? 0;
    final lng = double.tryParse('${i['mapX']}') ?? 0;
    final induty = '${i['induty']}';
    if (i['manageSttus'] != '운영' || lat == 0 || lng == 0) continue;
    if (!induty.contains('일반야영장') && !induty.contains('자동차야영장')) continue;

    final name = '${i['facltNm']}'.trim();
    final div = '${i['facltDivNm']}'.trim();
    final isForest = div == '자연휴양림' || name.contains('휴양림');
    final modified = '${i['modifiedtime']}';
    final contentId = '${i['contentId']}';

    out.add({
      'id': 'c0ca0000-0000-4000-8000-${contentId.padLeft(12, '0')}',
      'name': name,
      'lat': lat,
      'lng': lng,
      'is_legal': true,
      'last_verified_date': modified.length >= 10 ? modified.substring(0, 10) : '${i['createdtime']}',
      // 고캠핑은 미입력 항목이 0 으로 오므로 0 은 '정보 없음(null)' 으로 둔다
      'facilities': {
        'water': _countOrNull(i['wtrplCo']),
        'toilet': _countOrNull(i['toiletCo']),
        'shelter': null,
      },
      'type': isForest ? 'forest' : 'campground',
      'source': '한국관광공사 고캠핑 등록 야영장${div.isEmpty ? '' : ' · $div'}',
      'region': '${i['doNm']} ${i['sigunguNm']}'.trim(),
      'note': [
        induty,
        if ('${i['lctCl']}'.isNotEmpty) '입지: ${i['lctCl']}',
        if ('${i['lineIntro']}'.isNotEmpty) '${i['lineIntro']}',
      ].join('\n'),
      'tel': _blankToNull(i['tel']),
      'url': _blankToNull(i['resveUrl']) ?? _blankToNull(i['homepage']),
    });
  }
  return out;
}

bool? _countOrNull(Object? v) => (int.tryParse('$v') ?? 0) > 0 ? true : null;

String? _blankToNull(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty ? null : s;
}

// ───────────────────────── 국립공원 대피소 ─────────────────────────

Future<List<Map<String, dynamic>>> _fetchShelters(String today) async {
  const query = '[out:json][timeout:60];'
      '(nwr["tourism"="alpine_hut"](33.0,124.5,38.62,131.0);'
      'nwr["amenity"="shelter"]["name"~"대피소"](33.0,124.5,38.62,131.0););'
      'out center tags;';

  List elements = const [];
  for (var attempt = 0, wait = 5; attempt < 5; attempt++, wait *= 2) {
    try {
      final res = await http
          .post(Uri.parse('https://overpass-api.de/api/interpreter'),
              headers: {'User-Agent': _ua}, body: {'data': query})
          .timeout(const Duration(seconds: 90));
      if (res.statusCode == 200) {
        elements = jsonDecode(utf8.decode(res.bodyBytes))['elements'] as List;
        break;
      }
      stdout.writeln('Overpass ${res.statusCode}, $wait초 후 재시도');
    } catch (e) {
      stdout.writeln('Overpass 오류($e), $wait초 후 재시도');
    }
    await Future<void>.delayed(Duration(seconds: wait));
  }
  if (elements.isEmpty) throw StateError('OpenStreetMap 대피소 조회 실패');

  final out = <Map<String, dynamic>>[];
  for (final MapEntry(key: park, value: keywords) in _officialShelters.entries) {
    for (final kw in keywords) {
      final pattern = RegExp('($kw)\\s*대피소');
      final hit = elements.cast<Map<String, dynamic>>().where((e) {
        final name = '${(e['tags'] as Map)['name'] ?? ''}';
        return pattern.hasMatch(name);
      }).firstOrNull;
      if (hit == null) {
        stdout.writeln('⚠️  OSM 에서 좌표를 못 찾음: $park $kw대피소 (제외)');
        continue;
      }
      final center = (hit['center'] ?? hit) as Map<String, dynamic>;
      final typeCode = hit['type'] == 'node' ? '1' : '2';
      final label = kw.split('|').first;
      out.add({
        'id': 'a1b2000$typeCode-0000-4000-8000-${'${hit['id']}'.padLeft(12, '0')}',
        'name': '${park.replaceAll('국립공원', '')} $label대피소',
        'lat': (center['lat'] as num).toDouble(),
        'lng': (center['lon'] as num).toDouble(),
        'is_legal': true,
        'last_verified_date': today,
        'facilities': {'water': null, 'toilet': true, 'shelter': true},
        'type': 'shelter',
        'source': '국립공원공단 예약시스템 (좌표 © OpenStreetMap)',
        'region': park,
        'note': '사전 예약제 대피소. 대피소 외 텐트 야영 불가. '
            '산불조심기간 등 통제 일정은 예약시스템(res.knps.or.kr)에서 확인하세요.',
        'tel': '1670-9201',
        'url': 'https://res.knps.or.kr',
      });
    }
  }
  return out;
}

// ───────────────────────── Supabase SQL ─────────────────────────

String _toSql(List<Map<String, dynamic>> rows, String today) {
  String q(Object? v) => v == null ? 'null' : "'${'$v'.replaceAll("'", "''")}'";
  final b = StringBuffer()
    ..writeln('-- tool/import_campsites.dart 로 $today 생성. SQL Editor 에서 실행하세요.')
    ..writeln('insert into public.campsites')
    ..writeln('  (id, name, lat, lng, is_legal, last_verified_date, facilities, type, source, region, note, tel, url)')
    ..writeln('values');
  b.writeln([
    for (final r in rows)
      '  (${q(r['id'])}, ${q(r['name'])}, ${r['lat']}, ${r['lng']}, ${r['is_legal']}, '
          "${q(r['last_verified_date'])}, ${q(jsonEncode(r['facilities']))}::jsonb, ${q(r['type'])}, "
          '${q(r['source'])}, ${q(r['region'])}, ${q(r['note'])}, ${q(r['tel'])}, ${q(r['url'])})',
  ].join(',\n'));
  b.writeln('on conflict (id) do update set');
  b.writeln([
    for (final c in ['name', 'lat', 'lng', 'is_legal', 'last_verified_date', 'facilities', 'type', 'source', 'region', 'note', 'tel', 'url'])
      '  $c = excluded.$c',
  ].join(',\n'));
  b.writeln(';');
  return b.toString();
}
