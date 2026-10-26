import 'package:flutter/material.dart';

/// Bivi mascot cutouts made by `tool/extract_character_assets.dart` (PRD_step4).
/// Screens refer to these names only, so a higher-resolution sheet can replace
/// the files without touching UI code.
enum Mascot {
  front('front.png', 'Bivi 캐릭터'),
  side('side.png', 'Bivi 캐릭터 옆모습'),
  back('back.png', 'Bivi 캐릭터 뒷모습'),
  smile('face_smile.png', '미소 짓는 Bivi'),
  happy('face_happy.png', '신난 Bivi'),
  surprised('face_surprised.png', '놀란 Bivi'),
  tired('face_tired.png', '피곤한 Bivi'),
  hiking('scene_hiking.png', '등산하는 Bivi'),
  camping('scene_camping.png', '캠핑하는 Bivi'),
  viewing('scene_viewing.png', '풍경을 보는 Bivi'),
  mapReading('scene_map.png', '지도를 보는 Bivi'),
  iconBackpack('icon_backpack.png', '배낭'),
  iconPoles('icon_poles.png', '등산스틱'),
  iconTent('icon_tent.png', '텐트'),
  iconCup('icon_cup.png', '컵'),
  iconMap('icon_map.png', '지도'),
  iconLogo('icon_logo.png', '산 로고'),
  hero('hero.jpg', '노을 진 산 정상의 Bivi');

  const Mascot(this.file, this.label);

  final String file;

  /// Screen-reader description.
  final String label;

  String get asset => 'assets/character/$file';
}

/// Mascot image at a fixed height (width follows the artwork).
class MascotImage extends StatelessWidget {
  const MascotImage(this.mascot, {super.key, this.height = 140});

  final Mascot mascot;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      mascot.asset,
      height: height,
      fit: BoxFit.contain,
      // Source cutouts are small (~150–250 px); smooth upscaling looks better than nearest.
      filterQuality: FilterQuality.medium,
      semanticLabel: mascot.label,
      errorBuilder: (_, __, ___) => SizedBox(height: height),
    );
  }
}
