import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../theme/app_theme.dart';

/// Shared gesture tuning for every map in the app.
///
/// Tuning history (user feedback on a Galaxy S10):
/// - flutter_map default (20°, no race): the map spun while pinch-zooming.
/// - 45° + race with a 0.3 zoom threshold: rotation felt sluggish, because the
///   zoom gesture usually won the race first and blocked rotation for the whole touch.
/// Now: rotation starts after a 25° twist and zoom needs a clearer pinch (0.5).
/// Whichever wins first decides the touch: a zoom never rotates, but once rotation
/// has started you can also zoom and pan in the same gesture (like most map apps).
const biviMapInteraction = InteractionOptions(
  enableMultiFingerGestureRace: true,
  rotationThreshold: 25,
  rotationWinGestures:
      MultiFingerGesture.rotate | MultiFingerGesture.pinchZoom | MultiFingerGesture.pinchMove,
  pinchZoomThreshold: 0.5,
  pinchZoomWinGestures: MultiFingerGesture.pinchZoom | MultiFingerGesture.pinchMove,
  pinchMoveThreshold: 40,
  pinchMoveWinGestures: MultiFingerGesture.pinchZoom | MultiFingerGesture.pinchMove,
);

/// Compass shown while the map is rotated; tap to snap back to north-up.
class NorthUpButton extends StatelessWidget {
  const NorthUpButton({super.key, required this.rotation, required this.onPressed});

  /// Current map rotation in degrees.
  final double rotation;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BiviColors.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(side: BorderSide(color: BiviColors.contour)),
      child: IconButton(
        tooltip: '북쪽 위로',
        onPressed: onPressed,
        icon: Transform.rotate(
          // The needle points to true north, so counter-rotate by the map rotation.
          angle: -rotation * math.pi / 180,
          child: const Icon(Icons.navigation, color: Color(0xFFE53935)),
        ),
      ),
    );
  }
}
