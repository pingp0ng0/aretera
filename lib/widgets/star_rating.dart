import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _starColor = Color(0xFFFFC23C);

/// Perceived-difficulty labels for 1–5 stars (PRD_step5).
const difficultyLabels = ['아주 쉬움', '쉬움', '보통', '힘듦', '아주 힘듦'];

/// Tap a star to set the rating, tap the same star again to clear it.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({super.key, required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value ?? 0;
    return Row(
      children: [
        for (var star = 1; star <= 5; star++)
          IconButton(
            tooltip: '난이도 $star',
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(star == value ? null : star),
            icon: Icon(
              star <= v ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 34,
              color: star <= v ? _starColor : BiviColors.textSecondary,
            ),
          ),
        const SizedBox(width: 8),
        Text(
          value == null ? '선택 안 함' : difficultyLabels[value! - 1],
          style: const TextStyle(color: BiviColors.textSecondary),
        ),
      ],
    );
  }
}

/// Small read-only stars for lists.
class StarRatingView extends StatelessWidget {
  const StarRatingView({super.key, required this.value, this.size = 14});

  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Icon(
            star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: star <= value ? _starColor : BiviColors.contour,
          ),
      ],
    );
  }
}
