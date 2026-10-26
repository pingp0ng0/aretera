enum CampsiteType {
  shelter('대피소'),
  forest('자연휴양림'),
  campground('야영장'),

  /// Spots mentioned in blog/cafe reviews. Legality unknown (PRD_step2).
  review('후기 박지'),
  restricted('야영 금지 구역');

  const CampsiteType(this.label);
  final String label;

  static CampsiteType fromName(String? v) => CampsiteType.values
      .firstWhere((t) => t.name == v, orElse: () => CampsiteType.campground);
}

/// 부대시설. null = 출처에 정보 없음 (없다고 단정하지 않는다)
class Facilities {
  const Facilities({this.water, this.toilet, this.shelter});

  final bool? water;
  final bool? toilet;
  final bool? shelter;

  factory Facilities.fromJson(Map<String, dynamic>? j) => Facilities(
        water: j?['water'] as bool?,
        toilet: j?['toilet'] as bool?,
        shelter: j?['shelter'] as bool?,
      );

  Map<String, dynamic> toJson() => {'water': water, 'toilet': toilet, 'shelter': shelter};
}

/// A blog/cafe post that mentions a review spot. Only the link is kept, never the text.
class ReviewLink {
  const ReviewLink({required this.url, required this.date, required this.kind});

  final String url;
  final DateTime date;

  /// "blog" or "cafe"
  final String kind;

  factory ReviewLink.fromJson(Map<String, dynamic> j) => ReviewLink(
        url: j['url'] as String,
        date: DateTime.parse(j['date'] as String),
        kind: j['kind'] as String? ?? 'blog',
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'date': date.toIso8601String().substring(0, 10),
        'kind': kind,
      };
}

/// Supabase `campsites` 테이블 한 행
class Campsite {
  const Campsite({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.isLegal,
    required this.lastVerifiedDate,
    required this.facilities,
    required this.type,
    required this.source,
    this.region,
    this.note,
    this.tel,
    this.url,
    this.mentions,
    this.nationalPark,
    this.links = const [],
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final bool isLegal;
  final DateTime lastVerifiedDate;
  final Facilities facilities;
  final CampsiteType type;
  final String source;
  final String? region;
  final String? note;
  final String? tel;

  /// 예약 페이지 또는 홈페이지
  final String? url;

  // Review spots only (type == review).
  /// Number of distinct posts that mention this spot.
  final int? mentions;

  /// National park the spot falls in — camping there is prohibited outside designated sites.
  final String? nationalPark;

  /// Most recent source posts (up to 5).
  final List<ReviewLink> links;

  /// 최종 검증 후 180일이 지나면 재확인 권장 배지를 띄운다.
  bool isStale(DateTime now) => now.difference(lastVerifiedDate).inDays > 180;

  factory Campsite.fromJson(Map<String, dynamic> j) => Campsite(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        isLegal: j['is_legal'] as bool? ?? true,
        lastVerifiedDate: DateTime.parse(j['last_verified_date'] as String),
        facilities: Facilities.fromJson(j['facilities'] as Map<String, dynamic>?),
        type: CampsiteType.fromName(j['type'] as String?),
        source: j['source'] as String? ?? '출처 미상',
        region: j['region'] as String?,
        note: j['note'] as String?,
        tel: j['tel'] as String?,
        url: j['url'] as String?,
        mentions: (j['mentions'] as num?)?.toInt(),
        nationalPark: j['national_park'] as String?,
        links: [
          for (final l in (j['links'] as List? ?? const []))
            ReviewLink.fromJson(l as Map<String, dynamic>),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'is_legal': isLegal,
        'last_verified_date': lastVerifiedDate.toIso8601String().substring(0, 10),
        'facilities': facilities.toJson(),
        'type': type.name,
        'source': source,
        'region': region,
        'note': note,
        'tel': tel,
        'url': url,
        if (mentions != null) 'mentions': mentions,
        if (nationalPark != null) 'national_park': nationalPark,
        if (links.isNotEmpty) 'links': [for (final l in links) l.toJson()],
      };
}
