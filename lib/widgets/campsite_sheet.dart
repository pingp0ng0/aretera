import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/campsite.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

IconData campsiteIcon(CampsiteType t) => switch (t) {
      CampsiteType.shelter => Icons.night_shelter,
      CampsiteType.forest => Icons.forest,
      CampsiteType.campground => Icons.cabin,
      CampsiteType.review => Icons.forum,
      CampsiteType.restricted => Icons.do_not_disturb_on,
    };

/// 지도 핀 · 필터 칩 공통 유형 색상 (주황은 경고 전용이라 금지 구역에만 사용)
Color campsiteColor(CampsiteType t) => switch (t) {
      CampsiteType.shelter => const Color(0xFF9A5B2C), // 산장 갈색
      CampsiteType.forest => const Color(0xFF2E7D32), // 숲 초록
      CampsiteType.campground => const Color(0xFF2F6DB5), // 야영장 파랑
      CampsiteType.review => const Color(0xFF6B7280), // grey: legality unknown
      CampsiteType.restricted => BiviColors.amber,
    };

/// Pin color for a specific site: review spots inside a national park get the warning color.
Color siteColor(Campsite s) {
  if (s.type == CampsiteType.review && s.nationalPark != null) return const Color(0xFFC62828);
  return s.isLegal || s.type == CampsiteType.review ? campsiteColor(s.type) : BiviColors.amber;
}

Future<void> showCampsiteSheet(BuildContext context, Campsite site) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CampsiteSheet(site: site),
    );

/// 핀 상세 바텀 시트: 이름 · 합법 배지 · 부대시설 · 공식 출처 · 최종 검증일 · 연락처
class CampsiteSheet extends StatelessWidget {
  const CampsiteSheet({super.key, required this.site});

  final Campsite site;

  @override
  Widget build(BuildContext context) {
    if (site.type == CampsiteType.review) return _ReviewSpotSheet(site: site);

    final now = DateTime.now();
    final days = now.difference(site.lastVerifiedDate).inDays;
    final stale = site.isStale(now);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(campsiteIcon(site.type), color: campsiteColor(site.type)),
                  const SizedBox(width: 8),
                  Text(site.type.label, style: const TextStyle(color: BiviColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 6),
              Text(site.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              if (site.region != null) ...[
                const SizedBox(height: 2),
                Text(site.region!, style: const TextStyle(color: BiviColors.textSecondary)),
              ],
              const SizedBox(height: 12),
              _LegalBadge(isLegal: site.isLegal),
              const SizedBox(height: 20),
              const Text('부대시설', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _FacilityChip(icon: Icons.water_drop, label: '개수대·물', available: site.facilities.water),
                  const SizedBox(width: 8),
                  _FacilityChip(icon: Icons.wc, label: '화장실', available: site.facilities.toilet),
                  const SizedBox(width: 8),
                  _FacilityChip(icon: Icons.roofing, label: '대피 시설', available: site.facilities.shelter),
                ],
              ),
              const SizedBox(height: 20),
              _InfoRow(icon: Icons.verified_outlined, label: '공식 출처', value: site.source),
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.event_available,
                label: '최종 검증일',
                value: '${formatDate(site.lastVerifiedDate)} ($days일 전)',
                valueColor: stale ? BiviColors.amber : null,
              ),
              if (stale) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BiviColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BiviColors.amber.withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    '검증 후 6개월이 지났습니다. 방문 전 공식 채널에서 운영 여부를 다시 확인하세요.',
                    style: TextStyle(color: BiviColors.amber, height: 1.4),
                  ),
                ),
              ],
              if (site.note != null && site.note!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(site.note!, style: const TextStyle(height: 1.5)),
              ],
              if (site.tel != null || site.url != null) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (site.tel != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: site.tel)),
                          icon: const Icon(Icons.call),
                          label: Text(site.tel!, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    if (site.tel != null && site.url != null) const SizedBox(width: 8),
                    if (site.url != null)
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: BiviColors.forest),
                          onPressed: () => _openUrl(site.url!),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(site.type == CampsiteType.shelter ? '예약하기' : '예약·홈페이지'),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _LegalBadge extends StatelessWidget {
  const _LegalBadge({required this.isLegal});
  final bool isLegal;

  @override
  Widget build(BuildContext context) {
    final color = isLegal ? BiviColors.forestLight : BiviColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isLegal ? Icons.check_circle : Icons.block, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            isLegal ? '합법 야영·숙박 허가' : '야영 금지 구역',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _FacilityChip extends StatelessWidget {
  const _FacilityChip({required this.icon, required this.label, required this.available});
  final IconData icon;
  final String label;

  /// null = 출처에 정보 없음
  final bool? available;

  @override
  Widget build(BuildContext context) {
    final yes = available == true;
    final color = yes ? BiviColors.textPrimary : BiviColors.textSecondary.withValues(alpha: 0.6);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: BiviColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: yes ? BiviColors.forestLight : color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
            Text(
              switch (available) { true => '있음', false => '없음', null => '정보 없음' },
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value, this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: BiviColors.textSecondary),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(color: BiviColors.textSecondary)),
        ),
        Expanded(
          child: Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: valueColor)),
        ),
      ],
    );
  }
}

/// Sheet for review-based spots: never shown as legal; links to the source posts.
class _ReviewSpotSheet extends StatelessWidget {
  const _ReviewSpotSheet({required this.site});

  final Campsite site;

  @override
  Widget build(BuildContext context) {
    final park = site.nationalPark;
    final warnColor = park != null ? const Color(0xFFE57373) : BiviColors.textSecondary;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(campsiteIcon(site.type), color: siteColor(site)),
                  const SizedBox(width: 8),
                  Text(site.type.label, style: const TextStyle(color: BiviColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 6),
              Text(site.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              if (site.region != null) ...[
                const SizedBox(height: 2),
                Text(site.region!, style: const TextStyle(color: BiviColors.textSecondary)),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: warnColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: warnColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(park != null ? Icons.block : Icons.help_outline, size: 16, color: warnColor),
                    const SizedBox(width: 6),
                    Text(
                      park != null ? '국립공원 내 — 야영 금지' : '합법 여부 미확인',
                      style: TextStyle(color: warnColor, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                park != null
                    ? '$park 안에서는 지정 야영장 밖 야영·취사가 과태료 대상입니다.'
                    : '후기에서 자주 언급된 장소일 뿐, 야영이 허용된다는 뜻은 아닙니다. '
                        '해당 지자체·관리 주체의 규정을 확인하세요.',
                style: const TextStyle(color: BiviColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 20),
              _InfoRow(icon: Icons.forum_outlined, label: '출처', value: site.source),
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.history,
                label: '최근 언급',
                value: formatDate(site.lastVerifiedDate),
              ),
              if (site.links.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('최근 후기', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                for (final l in site.links)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(l.kind == 'cafe' ? Icons.groups_outlined : Icons.article_outlined),
                    title: Text(
                      Uri.tryParse(l.url)?.host ?? l.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${l.kind == 'cafe' ? '카페' : '블로그'} · ${formatDate(l.date)}'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => launchUrl(Uri.parse(l.url), mode: LaunchMode.externalApplication),
                  ),
              ],
              if (site.url != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(site.url!), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('카카오맵에서 보기'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
