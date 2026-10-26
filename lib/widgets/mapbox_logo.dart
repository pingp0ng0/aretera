import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/env.dart';

/// Mapbox 이용약관: Mapbox 타일을 쓰는 모든 지도 위에 워드마크 로고 표시 필수
class MapboxLogo extends StatelessWidget {
  const MapboxLogo({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Env.hasMapbox) return const SizedBox.shrink();
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: SvgPicture.asset('assets/images/mapbox-logo.svg', width: 88, height: 23),
        ),
      ),
    );
  }
}
