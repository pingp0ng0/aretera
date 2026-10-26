/// A user-editable gear category (PRD_step3). Stored on the device.
class GearCategory {
  const GearCategory({required this.id, required this.name, required this.icon});

  /// Stable key saved on each [GearItem.categoryId]. Built-in categories keep the
  /// ids the old fixed enum used ("shelter", "sleep", …) so stored gear still matches.
  final String id;
  final String name;

  /// Key into the icon choices in `lib/widgets/gear_icons.dart`.
  final String icon;

  GearCategory copyWith({String? name, String? icon}) =>
      GearCategory(id: id, name: name ?? this.name, icon: icon ?? this.icon);

  factory GearCategory.fromJson(Map<String, dynamic> j) => GearCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        icon: j['icon'] as String? ?? 'category',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'icon': icon};
}

/// Id of the built-in safety category. The pack tab badge only checks this one.
const safetyCategoryId = 'safety';

/// Categories a fresh install starts with.
const defaultGearCategories = [
  GearCategory(id: 'shelter', name: '쉘터', icon: 'shelter'),
  GearCategory(id: 'sleep', name: '수면', icon: 'sleep'),
  GearCategory(id: 'clothing', name: '의류', icon: 'clothing'),
  GearCategory(id: 'cook', name: '취사', icon: 'cook'),
  GearCategory(id: safetyCategoryId, name: '안전', icon: 'safety'),
  GearCategory(id: 'myog', name: '자작 장비', icon: 'myog'),
  GearCategory(id: 'etc', name: '기타', icon: 'category'),
];

/// Supabase `my_gear` 테이블 한 행 (로컬 우선 저장, 로그인 시 클라우드 동기화)
class GearItem {
  const GearItem({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.weightGrams,
    this.isPacked = false,
  });

  final String id;
  final String name;

  /// [GearCategory.id] this item belongs to.
  final String categoryId;
  final int weightGrams;
  final bool isPacked;

  GearItem copyWith({String? name, String? categoryId, int? weightGrams, bool? isPacked}) =>
      GearItem(
        id: id,
        name: name ?? this.name,
        categoryId: categoryId ?? this.categoryId,
        weightGrams: weightGrams ?? this.weightGrams,
        isPacked: isPacked ?? this.isPacked,
      );

  factory GearItem.fromJson(Map<String, dynamic> j) => GearItem(
        id: j['id'] as String,
        name: j['name'] as String,
        categoryId: j['category'] as String? ?? 'etc',
        weightGrams: (j['weight_grams'] as num).toInt(),
        isPacked: j['is_packed'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': categoryId,
        'weight_grams': weightGrams,
        'is_packed': isPacked,
      };
}
