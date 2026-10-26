// Collect frequently mentioned backpacking spots (박지) from blog/cafe reviews
// via the official Kakao Search API, geocode them with Kakao Local, and flag
// spots inside national parks. Personal use — see PRD_step2.md.
//
//   dart run tool/import_blog_spots.dart           # search (cached) + geocode + review list
//   dart run tool/import_blog_spots.dart --refresh # ignore the search cache
//
// Only place names, coordinates, mention counts, dates and source links are
// stored. Review text itself is never saved.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

const _outDir = 'build/blog_spots';
const _queries = [
  '백패킹 박지',
  '백패킹 박지 추천',
  '노지 백패킹',
  '백패킹 성지',
  '백패킹 명소',
  '동계 백패킹',
  '섬 백패킹',
  '솔로 백패킹',
  '비박 박지',
  '백패킹 후기 박지',
];
const _pagesPerQuery = 15; // Kakao allows up to 50 pages of 50 results
const _minMentions = 3; // distinct posts that must mention a spot

/// Suffixes that make a token look like a natural place name.
const _placeSuffixes = [
  '해수욕장', '자연휴양림', '휴양림', '전망대', '해변', '해안', '계곡', '오름', '언덕', '평전', '목장',
  '고개', '저수지', '호수', '습지', '포구', '등대', '능선', '바위', '평원', '초원', '공원', '대피소',
  '산', '봉', '섬', '도', '재', '령', '곶', '숲', '골', '항', '호', '대',
];

/// Tokens that end like a place but are not one.
const _stopTokens = {
  '정도', '온도', '속도', '난이도', '지도', '태도', '각도', '고도', '습도', '강도', '시도', '포도', '인도',
  '보도', '차도', '그래도', '제주도', '강원도', '경기도', '충청도', '전라도', '경상도', '충북도', '전남도',
  '경남도', '경북도', '전북도', '충남도', '산', '섬', '대', '호', '골', '재', '령', '항', '봉', '숲', '도',
  '등산', '하산', '야산', '근교산', '명산', '최고', '최대', '반도', '절대', '기대', '세대', '시대', '대대',
  '이번', '지난', '첫', '계곡', '공원', '해변', '바다', '주차장', '데크', '노지', '감성', '프라이빗',
  // seen as noise in the first run
  '부산', '바위', '내돈내산', '능선', '언덕', '무인도', '나도', '월간산', '설산', '전망대', '해수욕장',
  '청도', '서산', '군산', '포항', '안산', '양산', '인천섬', '신안섬', '신비의섬', '잣숲', '잣나무숲',
  '오지계곡', '지금떠나는경기도', '하게도', '마도',
};

/// Words ending in 시/군/구 that are not city/county names.
const _notRegions = {'다시', '혹시', '잠시', '또다시', '반드시', '원시', '산행시', '입문시', '카카오택시', '당시', '동시', '역시', '무시', '가끔시'};

/// Kakao Local category segments (split on " > ") that indicate an outdoor place.
/// Matched per segment — substring matching let "산업용품"/"수산물판매" through.
const _outdoorSegments = {'관광,명소', '캠핑장', '야영장', '자연휴양림', '휴양림', '국립공원', '도립공원'};

Future<void> main(List<String> args) async {
  final env = jsonDecode(File('env.json').readAsStringSync()) as Map<String, dynamic>;
  final key = (env['KAKAO_REST_KEY'] as String?) ?? '';
  if (key.isEmpty) _fail('env.json needs KAKAO_REST_KEY');
  Directory(_outDir).createSync(recursive: true);
  final watch = Stopwatch()..start();

  final posts = await _searchPosts(key, refresh: args.contains('--refresh'));
  stdout.writeln('posts: ${posts.length} (${watch.elapsed.inSeconds}s)');

  final candidates = _extractCandidates(posts);
  stdout.writeln('candidates mentioned in >= $_minMentions posts: ${candidates.length}');
  _writeJson('$_outDir/candidates.json', candidates);

  final geocoded = await _geocode(key, candidates);
  if (geocoded == null) {
    stdout.writeln('Kakao Local is not enabled for this app — stopped after extraction.');
    stdout.writeln('Enable "카카오맵" in Kakao Developers, then run again.');
    exit(2);
  }
  stdout.writeln('geocoded: ${geocoded.length} (${watch.elapsed.inSeconds}s)');

  final parks = await _nationalParks();
  final registered = _loadRegisteredSites();
  for (final s in geocoded) {
    s['national_park'] = _parkAt(parks, s['lat'] as double, s['lng'] as double);
    s['near_registered'] = _nearestRegistered(registered, s['lat'] as double, s['lng'] as double);
  }
  _writeJson('$_outDir/spots.json', geocoded);
  File('$_outDir/review.md').writeAsStringSync(_reviewMarkdown(geocoded));

  // App asset: same-name (ambiguous) places are left out until confirmed by hand.
  final appSpots = [for (final s in geocoded) if (s['ambiguous'] != true) _toCampsiteJson(s)];
  File('assets/data/blog_spots.json').writeAsStringSync(jsonEncode(appSpots));
  stdout.writeln('app asset: ${appSpots.length} spots (excluded ${geocoded.length - appSpots.length} ambiguous)');
  stdout.writeln('done in ${watch.elapsed.inSeconds}s → $_outDir/review.md');
}

/// Shape matches lib/models/campsite.dart (type "review").
Map<String, dynamic> _toCampsiteJson(Map<String, dynamic> s) {
  final park = s['national_park'] as String?;
  return {
    'id': 'b1095000-0000-4000-8000-${'${s['kakao_id']}'.padLeft(12, '0')}',
    'name': s['place_name'],
    'lat': s['lat'],
    'lng': s['lng'],
    'is_legal': false, // unknown — never shown as legal
    'last_verified_date': s['last_mentioned'],
    'facilities': {'water': null, 'toilet': null, 'shelter': null},
    'type': 'review',
    'source': '블로그·카페 후기 ${s['mentions']}건 (카카오 검색)',
    'region': s['address'],
    'note': park == null ? null : '$park 안 — 지정 야영장 외 야영·취사는 과태료 대상입니다.',
    'url': s['kakao_url'],
    'mentions': s['mentions'],
    'national_park': park,
    'links': s['links'],
  };
}

Never _fail(String msg) {
  stderr.writeln(msg);
  exit(1);
}

void _writeJson(String path, Object data) =>
    File(path).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(data));

// ───────────────────────── 1. search ─────────────────────────

Future<List<Map<String, dynamic>>> _searchPosts(String key, {required bool refresh}) async {
  final cache = File('$_outDir/search_cache.json');
  if (!refresh && cache.existsSync()) {
    return (jsonDecode(cache.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  }
  final byUrl = <String, Map<String, dynamic>>{};
  for (final q in _queries) {
    for (final kind in ['blog', 'cafe']) {
      for (var page = 1; page <= _pagesPerQuery; page++) {
        final uri = Uri.https('dapi.kakao.com', '/v2/search/$kind', {
          'query': q,
          'size': '50',
          'page': '$page',
          'sort': 'accuracy',
        });
        final res = await http.get(uri, headers: {'Authorization': 'KakaoAK $key'});
        if (res.statusCode != 200) {
          stdout.writeln('search $kind "$q" p$page → HTTP ${res.statusCode}');
          break;
        }
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        for (final d in (body['documents'] as List).cast<Map<String, dynamic>>()) {
          byUrl[d['url'] as String] = {
            'kind': kind,
            'title': _clean(d['title'] as String),
            'contents': _clean(d['contents'] as String),
            'url': d['url'],
            'date': (d['datetime'] as String).substring(0, 10),
          };
        }
        if ((body['meta'] as Map)['is_end'] == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
    stdout.writeln('  "$q": ${byUrl.length} unique posts so far');
  }
  final posts = byUrl.values.toList();
  _writeJson(cache.path, posts);
  return posts;
}

String _clean(String s) => s
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");

// ───────────────────────── 2. extract ─────────────────────────

final _keyword = RegExp(r'(백패킹|박지|비박|노지캠핑)');
final _token = RegExp(r'[가-힣A-Za-z0-9]+');

bool _isPlace(String t) =>
    t.length >= 2 &&
    !_stopTokens.contains(t) &&
    !RegExp(r'^[0-9]').hasMatch(t) &&
    _placeSuffixes.any((s) => t.endsWith(s));

/// Region words (city/county) used only as a geocoding hint.
bool _isRegion(String t) =>
    t.length >= 2 &&
    RegExp(r'^[가-힣]+(시|군|구)$').hasMatch(t) &&
    !_notRegions.contains(t) &&
    !_isPlace(t);

List<Map<String, dynamic>> _extractCandidates(List<Map<String, dynamic>> posts) {
  final mentions = <String, Map<String, dynamic>>{};

  for (final p in posts) {
    final seenInPost = <String>{};
    for (final text in [p['title'] as String, p['contents'] as String]) {
      for (final m in _keyword.allMatches(text)) {
        // Up to 4 tokens right before "백패킹/박지", e.g. "인제 소양호 백패킹".
        final before = text.substring(math.max(0, m.start - 40), m.start);
        final tokens = _token.allMatches(before).map((t) => t.group(0)!).toList();
        if (tokens.isEmpty) continue;
        final last = tokens.last;
        if (!_isPlace(last)) continue;
        final prev = tokens.length >= 2 ? tokens[tokens.length - 2] : null;
        // "굴업도 개머리언덕" / "방태산 적가리골": keep the parent place as part of the name.
        final name = (prev != null && prev != last && _isPlace(prev)) ? '$prev $last' : last;
        final hint = tokens.reversed.skip(1).firstWhere(_isRegion, orElse: () => '');
        final norm = name.replaceAll(' ', '');
        if (!seenInPost.add(norm)) continue;

        final e = mentions.putIfAbsent(norm, () => {'name': name, 'hints': <String, int>{}, 'posts': <Map>[]});
        if (hint.isNotEmpty) {
          final hints = e['hints'] as Map<String, int>;
          hints[hint] = (hints[hint] ?? 0) + 1;
        }
        (e['posts'] as List).add({'url': p['url'], 'date': p['date'], 'kind': p['kind']});
      }
    }
  }

  final out = <Map<String, dynamic>>[];
  for (final e in mentions.values) {
    final posts = (e['posts'] as List).cast<Map>();
    if (posts.length < _minMentions) continue;
    posts.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    final hints = (e['hints'] as Map<String, int>).entries.toList()..sort((a, b) => b.value - a.value);
    out.add({
      'name': e['name'],
      'region_hint': hints.isEmpty ? null : hints.first.key,
      'mentions': posts.length,
      'last_mentioned': posts.first['date'],
      'links': posts.take(5).toList(),
    });
  }
  out.sort((a, b) => (b['mentions'] as int) - (a['mentions'] as int));
  return out;
}

// ───────────────────────── 3. geocode ─────────────────────────

/// Returns null when Kakao Local is not enabled for the app (HTTP 403).
Future<List<Map<String, dynamic>>?> _geocode(String key, List<Map<String, dynamic>> candidates) async {
  final out = <Map<String, dynamic>>[];
  for (final c in candidates) {
    final name = c['name'] as String;
    final hint = c['region_hint'] as String?;
    Map<String, dynamic>? hit;
    for (final q in [if (hint != null) '$hint $name', name]) {
      final uri = Uri.https('dapi.kakao.com', '/v2/local/search/keyword.json', {'query': q, 'size': '5'});
      final res = await http.get(uri, headers: {'Authorization': 'KakaoAK $key'});
      if (res.statusCode == 403) return null;
      if (res.statusCode != 200) continue;
      final docs = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['documents'] as List).cast<Map<String, dynamic>>();
      hit = _bestPlace(docs, name);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (hit != null) break;
    }
    if (hit == null) {
      stdout.writeln('  no confident match: $name');
      continue;
    }
    // "선자령" and "대관령 선자령" resolve to the same Kakao place → merge mentions.
    final dup = out.where((o) => o['kakao_id'] == hit!['id']).firstOrNull;
    if (dup != null) {
      dup['mentions'] = (dup['mentions'] as int) + (c['mentions'] as int);
      final links = [...(dup['links'] as List), ...(c['links'] as List)]
        ..sort((a, b) => ((b as Map)['date'] as String).compareTo((a as Map)['date'] as String));
      dup['links'] = links.take(5).toList();
      if ((c['last_mentioned'] as String).compareTo(dup['last_mentioned'] as String) > 0) {
        dup['last_mentioned'] = c['last_mentioned'];
      }
      continue;
    }
    out.add({
      ...c,
      'kakao_id': hit['id'],
      'place_name': hit['place_name'],
      'category': hit['category_name'],
      'address': (hit['road_address_name'] as String?)?.isNotEmpty == true
          ? hit['road_address_name']
          : hit['address_name'],
      'lat': double.parse(hit['y'] as String),
      'lng': double.parse(hit['x'] as String),
      'kakao_url': hit['place_url'],
      // Only trust the match when a region hint pinned it down.
      'ambiguous': hit['ambiguous'] == true && hint == null,
    });
  }
  return out;
}

/// Businesses that share a place's name (pensions, restaurants, markets) are never spots.
const _excludedCategories = ['숙박', '음식점', '시장', '카페', '쇼핑', '병원', '부동산'];

/// Pick a result whose name contains the extracted name and whose category is outdoorsy.
/// Marks the hit as `ambiguous` when equally good matches exist in other regions.
Map<String, dynamic>? _bestPlace(List<Map<String, dynamic>> docs, String name) {
  final core = name.split(' ').last;
  final matches = docs.where((d) {
    final placeName = (d['place_name'] as String).replaceAll(' ', '');
    final category = d['category_name'] as String? ?? '';
    final segments = category.split(' > ').toSet();
    return placeName.contains(core) &&
        !_excludedCategories.any(category.contains) &&
        segments.any(_outdoorSegments.contains);
  }).toList();
  if (matches.isEmpty) return null;

  // "시/도 + 시/군" of each match; more than one → same name in different places.
  String area(Map<String, dynamic> d) => (d['address_name'] as String).split(' ').take(2).join(' ');
  final areas = matches.map(area).toSet();
  return {...matches.first, 'ambiguous': areas.length > 1};
}

// ───────────────────────── 4. national parks ─────────────────────────

typedef _Park = ({String name, List<(double, double, double, double)> edges});

/// National park boundaries from OpenStreetMap. Point-in-polygon uses the
/// even-odd rule over every member way's segments, so rings need not be assembled.
Future<List<_Park>> _nationalParks() async {
  final cache = File('$_outDir/national_parks.json');
  String raw;
  if (cache.existsSync()) {
    raw = cache.readAsStringSync();
  } else {
    const query = '[out:json][timeout:120];'
        'relation["boundary"="national_park"](33.0,124.5,38.62,131.0);out geom;';
    raw = '';
    for (var wait = 5; wait <= 80; wait *= 2) {
      final res = await http.post(Uri.parse('https://overpass-api.de/api/interpreter'),
          headers: {'User-Agent': 'Bivi/1.0 (data import)'}, body: {'data': query});
      if (res.statusCode == 200) {
        raw = utf8.decode(res.bodyBytes);
        break;
      }
      stdout.writeln('Overpass ${res.statusCode}, retry in ${wait}s');
      await Future<void>.delayed(Duration(seconds: wait));
    }
    if (raw.isEmpty) {
      stdout.writeln('national park boundaries unavailable — skipping that check');
      return [];
    }
    cache.writeAsStringSync(raw);
  }

  final parks = <_Park>[];
  for (final rel in (jsonDecode(raw)['elements'] as List).cast<Map<String, dynamic>>()) {
    final name = ((rel['tags'] as Map?)?['name'] as String?) ?? '';
    if (!RegExp(r'[가-힣]').hasMatch(name) || name.contains('도립')) continue; // Korean national parks only
    final edges = <(double, double, double, double)>[];
    for (final m in (rel['members'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final geom = (m['geometry'] as List?)?.cast<Map<String, dynamic>>();
      if (geom == null) continue;
      for (var i = 0; i + 1 < geom.length; i++) {
        edges.add((
          (geom[i]['lat'] as num).toDouble(),
          (geom[i]['lon'] as num).toDouble(),
          (geom[i + 1]['lat'] as num).toDouble(),
          (geom[i + 1]['lon'] as num).toDouble(),
        ));
      }
    }
    if (edges.isNotEmpty) parks.add((name: name, edges: edges));
  }
  stdout.writeln('national parks loaded: ${parks.length}');
  return parks;
}

String? _parkAt(List<_Park> parks, double lat, double lng) {
  for (final p in parks) {
    var inside = false;
    for (final (aLat, aLng, bLat, bLng) in p.edges) {
      if ((aLat > lat) != (bLat > lat)) {
        final xCross = aLng + (lat - aLat) / (bLat - aLat) * (bLng - aLng);
        if (lng < xCross) inside = !inside;
      }
    }
    if (inside) return p.name;
  }
  return null;
}

// ───────────────────────── 5. overlap with registered sites ─────────────────────────

List<(String, double, double)> _loadRegisteredSites() {
  final f = File('assets/data/campsites.json');
  if (!f.existsSync()) return const [];
  return [
    for (final s in (jsonDecode(f.readAsStringSync()) as List).cast<Map<String, dynamic>>())
      (s['name'] as String, (s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
  ];
}

/// Name of a registered campsite/shelter within 500 m, if any.
String? _nearestRegistered(List<(String, double, double)> sites, double lat, double lng) {
  for (final (name, sLat, sLng) in sites) {
    final dy = (sLat - lat) * 110540;
    final dx = (sLng - lng) * 111320 * math.cos(lat * math.pi / 180);
    if (dx * dx + dy * dy < 500 * 500) return name;
  }
  return null;
}

// ───────────────────────── review list ─────────────────────────

String _reviewMarkdown(List<Map<String, dynamic>> spots) {
  final b = StringBuffer()
    ..writeln('# 후기 기반 박지 후보 (검토용)')
    ..writeln()
    ..writeln('카카오 블로그·카페 검색에서 $_minMentions개 이상의 글이 언급한 장소. 합법 여부는 확인되지 않았습니다.')
    ..writeln()
    ..writeln('| # | 추출명 | 카카오 장소 | 주소 | 언급 | 최근 | 국립공원 | 등록 야영장 근접 | 동명 장소 |')
    ..writeln('|---|---|---|---|---|---|---|---|---|');
  var i = 0;
  for (final s in spots) {
    i++;
    b.writeln('| $i | ${s['name']} | ${s['place_name']} | ${s['address']} | ${s['mentions']} | '
        '${s['last_mentioned']} | ${s['national_park'] ?? ''} | ${s['near_registered'] ?? ''} | '
        '${s['ambiguous'] == true ? '⚠️ 위치 확인' : ''} |');
  }
  return b.toString();
}
