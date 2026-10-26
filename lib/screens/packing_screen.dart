import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/seed_data.dart';
import '../models/gear_item.dart';
import '../providers/gear_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/gear_icons.dart';
import '../widgets/mascot.dart';
import '../widgets/topo.dart';

/// Pseudo category for items whose category no longer exists.
const _uncategorized = GearCategory(id: '__uncategorized__', name: '미분류', icon: 'category');

/// Tab 2: 내 배낭 (스마트 패킹)
class PackingScreen extends ConsumerWidget {
  const PackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gear = ref.watch(gearProvider);
    final categories = ref.watch(gearCategoriesProvider);
    final filter = ref.watch(gearCategoryFilterProvider);
    final heavy = ref.watch(heavyPackedGearProvider);
    final visible = filter == null ? gear : gear.where((g) => g.categoryId == filter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 배낭'),
        actions: [
          IconButton(
            tooltip: '카테고리 관리',
            icon: const Icon(Icons.tune),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const _CategoryManagerSheet(),
            ),
          ),
          IconButton(
            tooltip: '전체 해제',
            icon: const Icon(Icons.remove_done),
            onPressed: () => ref.read(gearProvider.notifier).unpackAll(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: BiviColors.forest,
        foregroundColor: Colors.white,
        onPressed: () => _openGearEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('장비 추가'),
      ),
      body: gear.isEmpty
          ? EmptyState(
              icon: Icons.backpack_outlined,
              illustration: const MascotImage(Mascot.back, height: 160),
              title: '배낭이 비어 있어요',
              message: '가진 장비를 등록하면 그램 단위로 총무게를 계산해 드려요.',
              action: FilledButton(
                onPressed: () => _openGearEditor(context, ref),
                child: const Text('첫 장비 등록하기'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                const _WeightSummaryCard(),
                const SizedBox(height: 14),
                _CategoryFilterBar(categories: categories, selected: filter),
                const SizedBox(height: 10),
                ..._buildSections(visible, categories),
                if (heavy.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _LightAlternativesSlot(heavyItems: heavy),
                ],
              ],
            ),
    );
  }

  List<Widget> _buildSections(List<GearItem> items, List<GearCategory> categories) {
    final known = {for (final c in categories) c.id};
    final sections = [
      for (final c in categories) (c, items.where((g) => g.categoryId == c.id).toList()),
      (_uncategorized, items.where((g) => !known.contains(g.categoryId)).toList()),
    ];

    final out = <Widget>[];
    for (final (cat, inCat) in sections) {
      if (inCat.isEmpty) continue;
      final packedGrams = inCat.where((g) => g.isPacked).fold<int>(0, (sum, g) => sum + g.weightGrams);
      out
        ..add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Row(
            children: [
              Icon(gearIcon(cat.icon),
                  size: 18,
                  color: cat.id == safetyCategoryId ? BiviColors.amber : BiviColors.forestLight),
              const SizedBox(width: 6),
              Expanded(
                child: Text(cat.name,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text('${formatKg(packedGrams)} kg', style: const TextStyle(color: BiviColors.textSecondary)),
            ],
          ),
        ))
        ..add(Material(
          color: BiviColors.surface,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [for (final g in inCat) _GearTile(item: g)]),
        ));
    }
    return out;
  }
}

/// Opens the add/edit dialog. With [existing] it edits that item; otherwise it adds one.
Future<void> _openGearEditor(BuildContext context, WidgetRef ref, {GearItem? existing}) async {
  final result = await showDialog<({String name, String categoryId, int weightGrams})>(
    context: context,
    builder: (_) => _GearEditorDialog(existing: existing),
  );
  if (result == null) return;
  final gear = ref.read(gearProvider.notifier);
  if (existing == null) {
    gear.add(name: result.name, categoryId: result.categoryId, weightGrams: result.weightGrams);
  } else {
    gear.update(existing.id, name: result.name, categoryId: result.categoryId, weightGrams: result.weightGrams);
  }
}

class _WeightSummaryCard extends ConsumerWidget {
  const _WeightSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(packedWeightProvider);
    final goal = ref.watch(packGoalGramsProvider);
    final packedCount = ref.watch(packedGearProvider).length;
    final over = total > goal;
    final ratio = goal == 0 ? 0.0 : (total / goal).clamp(0.0, 1.0);

    return TopoCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 136,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: v,
                    strokeWidth: 12,
                    strokeCap: StrokeCap.round,
                    backgroundColor: BiviColors.surfaceHigh,
                    color: over ? BiviColors.amber : BiviColors.forestLight,
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatKg(total),
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.1),
                        ),
                        const Text('kg', style: TextStyle(color: BiviColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('총 배낭 무게', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('목표 ${formatKg(goal, digits: 1)} kg',
                    style: const TextStyle(color: BiviColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  over ? '목표 초과 +${formatKg(total - goal)} kg' : '여유 ${formatKg(goal - total)} kg',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: over ? BiviColors.amber : BiviColors.forestLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text('$packedCount개 패킹됨', style: const TextStyle(color: BiviColors.textSecondary)),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => _pickGoal(context, ref, goal),
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('목표 변경'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickGoal(BuildContext context, WidgetRef ref, int current) async {
    const options = [5000, 7000, 9000, 10000, 12000, 15000];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('목표 배낭 무게'),
        children: [
          for (final g in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g),
              child: Row(
                children: [
                  Text('${formatKg(g, digits: 0)} kg'),
                  const Spacer(),
                  if (g == current) const Icon(Icons.check, color: BiviColors.forestLight),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) ref.read(packGoalGramsProvider.notifier).state = picked;
  }
}

class _CategoryFilterBar extends ConsumerWidget {
  const _CategoryFilterBar({required this.categories, required this.selected});

  final List<GearCategory> categories;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void select(String? id) => ref.read(gearCategoryFilterProvider.notifier).state = id;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(label: const Text('전체'), selected: selected == null, onSelected: (_) => select(null)),
          for (final c in categories) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text(c.name),
              selected: selected == c.id,
              onSelected: (_) => select(selected == c.id ? null : c.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _GearTile extends ConsumerWidget {
  const _GearTile({required this.item});

  final GearItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void toggle() => ref.read(gearProvider.notifier).togglePacked(item.id);
    final dim = item.isPacked ? BiviColors.textPrimary : BiviColors.textSecondary;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      onTap: toggle,
      onLongPress: () => _showActions(context, ref),
      leading: Checkbox(value: item.isPacked, onChanged: (_) => toggle()),
      title: Text(item.name, style: TextStyle(color: dim)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${item.weightGrams} g',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: dim,
            ),
          ),
          IconButton(
            tooltip: '수정 · 삭제',
            icon: const Icon(Icons.more_vert, color: BiviColors.textSecondary),
            onPressed: () => _showActions(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('수정'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: BiviColors.amber),
              title: const Text('삭제', style: TextStyle(color: BiviColors.amber)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'edit') {
      await _openGearEditor(context, ref, existing: item);
    } else if (action == 'delete') {
      await _confirmDelete(context, ref);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('장비 삭제'),
        content: Text('"${item.name}"을(를) 내 장비에서 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: BiviColors.amber)),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(gearProvider.notifier).remove(item.id);
  }
}

/// 무거운 장비 선택 시 경량 대체품 추천 (제휴 링크 슬롯)
class _LightAlternativesSlot extends StatelessWidget {
  const _LightAlternativesSlot({required this.heavyItems});

  final List<GearItem> heavyItems;

  @override
  Widget build(BuildContext context) {
    return TopoCard(
      seed: 21,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_down, color: BiviColors.forestLight),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('경량 대체품 추천', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: BiviColors.textSecondary),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('제휴', style: TextStyle(fontSize: 11, color: BiviColors.textSecondary)),
              ),
            ],
          ),
          for (final item in heavyItems) ...[
            const SizedBox(height: 14),
            Text('${item.name} · ${item.weightGrams} g',
                style: const TextStyle(color: BiviColors.textSecondary, fontSize: 13)),
            for (final alt in (lightAlternatives[item.categoryId] ?? const <LightAlternative>[])
                .where((a) => a.weightGrams < item.weightGrams))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(alt.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(alt.note),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${alt.weightGrams} g', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('-${item.weightGrams - alt.weightGrams} g',
                        style: const TextStyle(color: BiviColors.forestLight, fontSize: 12)),
                  ],
                ),
                onTap: () => _openAffiliate(context, alt),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _openAffiliate(BuildContext context, LightAlternative alt) async {
    final url = alt.affiliateUrl;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('제휴 링크 준비 중입니다.')));
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

/// Add or edit one gear item. Pops a record with the entered values.
class _GearEditorDialog extends ConsumerStatefulWidget {
  const _GearEditorDialog({this.existing});

  final GearItem? existing;

  @override
  ConsumerState<_GearEditorDialog> createState() => _GearEditorDialogState();
}

class _GearEditorDialogState extends ConsumerState<_GearEditorDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _weight = TextEditingController(text: widget.existing?.weightGrams.toString() ?? '');
  late String _categoryId = widget.existing?.categoryId ?? _defaultCategoryId();

  /// New items go into the filtered category, else "자작 장비" if it still exists, else the first one.
  String _defaultCategoryId() {
    final categories = ref.read(gearCategoriesProvider);
    final filter = ref.read(gearCategoryFilterProvider);
    if (filter != null && categories.any((c) => c.id == filter)) return filter;
    if (categories.any((c) => c.id == 'myog')) return 'myog';
    return categories.first.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _weight.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && (int.tryParse(_weight.text) ?? 0) > 0;

  Future<void> _createCategory() async {
    final result = await showDialog<({String name, String icon})>(
      context: context,
      builder: (_) => const _CategoryEditorDialog(),
    );
    if (result == null) return;
    final created = ref.read(gearCategoriesProvider.notifier).add(name: result.name, icon: result.icon);
    setState(() => _categoryId = created.id);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(gearCategoriesProvider);
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? '장비 수정' : '장비 추가'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: !editing,
              decoration: const InputDecoration(labelText: '장비명', hintText: '예: MYOG 다이니마 스터프 색'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weight,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '무게', suffixText: 'g'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text('카테고리', style: TextStyle(color: BiviColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    avatar: Icon(gearIcon(c.icon), size: 16),
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('새 카테고리'),
                  onPressed: _createCategory,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(context, (
                    name: _name.text.trim(),
                    categoryId: _categoryId,
                    weightGrams: int.parse(_weight.text),
                  ))
              : null,
          child: Text(editing ? '저장' : '추가'),
        ),
      ],
    );
  }
}

/// Bottom sheet listing categories with add / edit / delete.
class _CategoryManagerSheet extends ConsumerWidget {
  const _CategoryManagerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(gearCategoriesProvider);
    final gear = ref.watch(gearProvider);
    int countOf(String id) => gear.where((g) => g.categoryId == id).length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('카테고리 관리', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in categories)
                    ListTile(
                      leading: Icon(gearIcon(c.icon), color: BiviColors.forestLight),
                      title: Text(c.name),
                      subtitle: Text('장비 ${countOf(c.id)}개'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '수정',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(context, ref, c),
                          ),
                          IconButton(
                            tooltip: '삭제',
                            icon: const Icon(Icons.delete_outline, color: BiviColors.amber),
                            onPressed: categories.length <= 1 ? null : () => _delete(context, ref, c, countOf(c.id)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: BiviColors.forest,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('카테고리 추가'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({String name, String icon})>(
      context: context,
      builder: (_) => const _CategoryEditorDialog(),
    );
    if (result != null) ref.read(gearCategoriesProvider.notifier).add(name: result.name, icon: result.icon);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, GearCategory c) async {
    final result = await showDialog<({String name, String icon})>(
      context: context,
      builder: (_) => _CategoryEditorDialog(existing: c),
    );
    if (result != null) {
      ref.read(gearCategoriesProvider.notifier).update(c.id, name: result.name, icon: result.icon);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, GearCategory c, int itemCount) async {
    final others = ref.read(gearCategoriesProvider).where((o) => o.id != c.id).toList();
    final moveTo = await showDialog<String>(
      context: context,
      builder: (_) => _DeleteCategoryDialog(category: c, itemCount: itemCount, others: others),
    );
    if (moveTo != null) ref.read(gearCategoriesProvider.notifier).remove(c.id, moveTo: moveTo);
  }
}

/// Name + icon for a new or existing category.
class _CategoryEditorDialog extends StatefulWidget {
  const _CategoryEditorDialog({this.existing});

  final GearCategory? existing;

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? 'category';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? '카테고리 수정' : '카테고리 추가'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 20,
              decoration: const InputDecoration(labelText: '이름', hintText: '예: 동계 장비, 식수'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            const Text('아이콘', style: TextStyle(color: BiviColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final MapEntry(key: key, value: icon) in gearIconChoices.entries)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _icon = key),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _icon == key ? BiviColors.forest : BiviColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (name: _name.text.trim(), icon: _icon)),
          child: Text(editing ? '저장' : '추가'),
        ),
      ],
    );
  }
}

/// Confirms deletion and asks where the category's gear should go. Pops the target id.
class _DeleteCategoryDialog extends StatefulWidget {
  const _DeleteCategoryDialog({required this.category, required this.itemCount, required this.others});

  final GearCategory category;
  final int itemCount;
  final List<GearCategory> others;

  @override
  State<_DeleteCategoryDialog> createState() => _DeleteCategoryDialogState();
}

class _DeleteCategoryDialogState extends State<_DeleteCategoryDialog> {
  // Default target: "기타" if it survives, else the first remaining category.
  late String _moveTo = widget.others.any((c) => c.id == 'etc') ? 'etc' : widget.others.first.id;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('카테고리 삭제'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.itemCount == 0
                ? '"${widget.category.name}" 카테고리를 삭제할까요?'
                : '"${widget.category.name}"의 장비 ${widget.itemCount}개를 옮길 카테고리를 고르세요. 장비는 삭제되지 않습니다.'),
            if (widget.itemCount > 0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in widget.others)
                    ChoiceChip(
                      avatar: Icon(gearIcon(c.icon), size: 16),
                      label: Text(c.name),
                      selected: _moveTo == c.id,
                      onSelected: (_) => setState(() => _moveTo = c.id),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        TextButton(
          onPressed: () => Navigator.pop(context, _moveTo),
          child: const Text('삭제', style: TextStyle(color: BiviColors.amber)),
        ),
      ],
    );
  }
}
