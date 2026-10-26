// Cut the Bivi character sheet into reusable PNG assets (PRD_step4).
//
//   dart run tool/extract_character_assets.dart
//
// Source: assets_src/character_sheet.webp (1254×1254 design sheet).
// Output: assets/character/*.png (transparent background) + hero.jpg,
//         build/character_contact_sheet.png (dark + light backgrounds, 2×) to eyeball the result.
//
// Regions are hand-measured on the 1254px sheet. If a higher-resolution sheet
// with the same layout is supplied, scale them with [_scale].
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _src = 'assets_src/character_sheet.webp';
const _out = 'assets/character';

/// (name, x, y, w, h) on the 1254px sheet. Keep labels (정면, 신남 …) outside the box.
const _cutouts = <(String, int, int, int, int)>[
  // 기본 디자인
  ('front', 28, 728, 170, 252),
  ('side', 208, 728, 165, 252),
  ('back', 385, 728, 165, 252),
  // 표정
  ('face_smile', 590, 730, 128, 115),
  ('face_happy', 722, 730, 128, 115),
  ('face_surprised', 590, 885, 128, 105),
  ('face_tired', 722, 880, 128, 110),
  // 일상 속 모습 — heights stop just above the captions (등산, 캠핑 …).
  ('scene_hiking', 878, 725, 165, 149),
  ('scene_camping', 1045, 725, 185, 149),
  ('scene_viewing', 880, 908, 172, 128),
  ('scene_map', 1072, 908, 145, 135),
  // 아이콘 / 소품
  ('icon_backpack', 396, 1090, 72, 82),
  ('icon_poles', 486, 1090, 66, 82),
  ('icon_tent', 560, 1095, 98, 70),
  ('icon_cup', 666, 1100, 62, 60),
  ('icon_map', 740, 1098, 74, 64),
  ('icon_logo', 826, 1100, 88, 52),
];

/// Full-body figures stand on a soft grey floor shadow that gets re-made as a translucent black one.
const _figures = {'front', 'side', 'back'};

/// Hero photo: the character on the summit at sunset, without the "Bivi" lettering on the left.
const _hero = (440, 0, 814, 676);

/// Colour palette swatch centres (카키 · 브라운 · 베이지 · 오렌지 · 그레이).
const _palette = <(String, int, int)>[
  ('khaki', 68, 1135),
  ('brown', 130, 1135),
  ('beige', 193, 1135),
  ('orange', 256, 1135),
  ('gray', 318, 1135),
];

const _scale = 1.0;
const _tolerance = 26.0; // colour distance still counted as background

/// The front view's cream face is almost the sheet background colour and has no
/// outline on one side, so the default tolerance floods into it. Use a stricter one.
const _toleranceOverride = <String, double>{'front': 9};

void main() {
  final sheet = img.decodeWebP(File(_src).readAsBytesSync());
  if (sheet == null) {
    stderr.writeln('cannot decode $_src');
    exit(1);
  }
  stdout.writeln('sheet ${sheet.width}x${sheet.height}');
  Directory(_out).createSync(recursive: true);

  final made = <(String, img.Image)>[];
  for (final (name, x, y, w, h) in _cutouts) {
    final crop = img.copyCrop(sheet,
        x: (x * _scale).round(), y: (y * _scale).round(), width: (w * _scale).round(), height: (h * _scale).round());
    final cut = _trim(
      _cutout(crop.convert(numChannels: 4),
          tolerance: _toleranceOverride[name] ?? _tolerance, floorShadow: _figures.contains(name)),
      pad: 3,
    );
    File('$_out/$name.png').writeAsBytesSync(img.encodePng(cut));
    made.add((name, cut));
    stdout.writeln('  $name.png ${cut.width}x${cut.height}');
  }

  final (hx, hy, hw, hh) = _hero;
  final hero = img.copyCrop(sheet, x: hx, y: hy, width: hw, height: hh);
  File('$_out/hero.jpg').writeAsBytesSync(img.encodeJpg(hero, quality: 88));
  stdout.writeln('  hero.jpg ${hero.width}x${hero.height}');

  stdout.writeln('palette:');
  for (final (name, x, y) in _palette) {
    final p = sheet.getPixel(x, y);
    final hex = [p.r, p.g, p.b].map((c) => c.toInt().toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    stdout.writeln('  $name #$hex');
  }

  _contactSheet(made);
}

/// Background removal for illustrations on a flat light sheet:
///  1. flood-fill the background from the crop border (colour distance ≤ [tolerance]);
///  2. drop small foreground islands (stray specks, caption dots);
///  3. optionally turn the grey floor shadow into a translucent black shadow;
///  4. erode the subject by 1px (edge pixels are blended with the light background → halo);
///  5. feather the edge with a small blur of the mask (no jagged stair-steps);
///  6. de-fringe: semi-transparent edge pixels take the colour of the nearest solid pixels.
img.Image _cutout(img.Image im, {required double tolerance, required bool floorShadow}) {
  final w = im.width, h = im.height, n = w * h;
  final r = List<double>.filled(n, 0), g = List<double>.filled(n, 0), b = List<double>.filled(n, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      final i = y * w + x;
      r[i] = p.r.toDouble();
      g[i] = p.g.toDouble();
      b[i] = p.b.toDouble();
    }
  }
  final (br, bg, bb) = _borderColour(r, g, b, w, h);
  double dist(int i) => math.sqrt(math.pow(r[i] - br, 2) + math.pow(g[i] - bg, 2) + math.pow(b[i] - bb, 2));
  double luma(int i) => 0.299 * r[i] + 0.587 * g[i] + 0.114 * b[i];
  final bgLuma = 0.299 * br + 0.587 * bg + 0.114 * bb;
  Iterable<int> nbrs(int i) sync* {
    final x = i % w, y = i ~/ w;
    if (x > 0) yield i - 1;
    if (x < w - 1) yield i + 1;
    if (y > 0) yield i - w;
    if (y < h - 1) yield i + w;
  }

  // 1. background flood fill
  final isBg = List<bool>.filled(n, false);
  final queue = <int>[];
  void seed(int i, bool Function(int) ok, List<bool> mask) {
    if (!mask[i] && ok(i)) {
      mask[i] = true;
      queue.add(i);
    }
  }

  bool bgLike(int i) => dist(i) <= tolerance;
  for (var x = 0; x < w; x++) {
    seed(x, bgLike, isBg);
    seed((h - 1) * w + x, bgLike, isBg);
  }
  for (var y = 0; y < h; y++) {
    seed(y * w, bgLike, isBg);
    seed(y * w + w - 1, bgLike, isBg);
  }
  while (queue.isNotEmpty) {
    for (final j in nbrs(queue.removeLast())) {
      seed(j, bgLike, isBg);
    }
  }

  // 2. remove foreground islands smaller than 0.4% of the crop (min 25 px)
  final minIsland = math.max(25, (n * 0.004).round());
  final seen = List<bool>.filled(n, false);
  for (var start = 0; start < n; start++) {
    if (isBg[start] || seen[start]) continue;
    final comp = <int>[start];
    seen[start] = true;
    for (var k = 0; k < comp.length; k++) {
      for (final j in nbrs(comp[k])) {
        if (!isBg[j] && !seen[j]) {
          seen[j] = true;
          comp.add(j);
        }
      }
    }
    if (comp.length < minIsland) {
      for (final i in comp) {
        isBg[i] = true;
      }
    }
  }

  // 3. floor shadow: neutral, slightly darker than the sheet, connected to the
  //    background, in the bottom fifth (keeps light socks/faces out of it).
  final shadowAlpha = List<double>.filled(n, 0);
  if (floorShadow) {
    bool shadowLike(int i) {
      if (isBg[i] || i ~/ w < h * 0.8) return false;
      final chroma = [r[i], g[i], b[i]].reduce(math.max) - [r[i], g[i], b[i]].reduce(math.min);
      final l = luma(i);
      return chroma <= 16 && l >= bgLuma - 75 && l < bgLuma - 2;
    }

    final isShadow = List<bool>.filled(n, false);
    for (var i = 0; i < n; i++) {
      if (isBg[i]) {
        for (final j in nbrs(i)) {
          seed(j, shadowLike, isShadow);
        }
      }
    }
    while (queue.isNotEmpty) {
      for (final j in nbrs(queue.removeLast())) {
        seed(j, shadowLike, isShadow);
      }
    }
    // Background/shadow pockets enclosed between the boots never touch the flood fill;
    // in the bottom tenth (below socks and faces) catch them without the connectivity rule.
    for (var i = (h * 0.9).floor() * w; i < n; i++) {
      if (isBg[i]) continue;
      final chroma = [r[i], g[i], b[i]].reduce(math.max) - [r[i], g[i], b[i]].reduce(math.min);
      // Also neutral pixels *brighter* than the sheet (paper-white specks next to the boots).
      final neutralLight = chroma <= 24 && luma(i) >= bgLuma - 75;
      if (dist(i) <= tolerance * 1.4 || neutralLight) isShadow[i] = true;
    }
    for (var i = 0; i < n; i++) {
      if (isShadow[i]) {
        isBg[i] = true;
        shadowAlpha[i] = ((bgLuma - luma(i)) / 75 * 0.55).clamp(0.0, 0.55);
      }
    }
  }

  // 4. erode the subject by 1px
  final core = List<bool>.generate(n, (i) => !isBg[i] && nbrs(i).every((j) => !isBg[j]));

  // 5. feather: 3×3 binomial blur of the core mask
  const kernel = [1, 2, 1, 2, 4, 2, 1, 2, 1];
  final alpha = List<double>.filled(n, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var sum = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx, yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          if (core[yy * w + xx]) sum += kernel[(dy + 1) * 3 + dx + 1];
        }
      }
      alpha[y * w + x] = sum / 16;
    }
  }

  // 6. de-fringe edge colours from solid neighbours (radius 2), then compose with the shadow
  final out = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      var a = alpha[i];
      var (cr, cg, cb) = (r[i], g[i], b[i]);
      if (a > 0 && !core[i]) {
        var sr = 0.0, sg = 0.0, sb = 0.0, cnt = 0;
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            final j = yy * w + xx;
            if (core[j]) {
              sr += r[j];
              sg += g[j];
              sb += b[j];
              cnt++;
            }
          }
        }
        if (cnt > 0) (cr, cg, cb) = (sr / cnt, sg / cnt, sb / cnt);
      }
      if (a < shadowAlpha[i]) {
        // Shadow shows through where the subject is (nearly) transparent.
        final t = a / shadowAlpha[i];
        (cr, cg, cb) = (cr * t, cg * t, cb * t);
        a = shadowAlpha[i];
      }
      out.setPixelRgba(x, y, cr.round(), cg.round(), cb.round(), (a * 255).round());
    }
  }
  return out;
}

/// Median colour of the crop's outer ring = the sheet background around this cutout.
(double, double, double) _borderColour(List<double> r, List<double> g, List<double> b, int w, int h) {
  final rs = <double>[], gs = <double>[], bs = <double>[];
  void add(int i) {
    rs.add(r[i]);
    gs.add(g[i]);
    bs.add(b[i]);
  }

  for (var x = 0; x < w; x++) {
    add(x);
    add((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    add(y * w);
    add(y * w + w - 1);
  }
  double median(List<double> v) => (v..sort())[v.length ~/ 2];
  return (median(rs), median(gs), median(bs));
}

/// Crop to the visible content plus [pad] px.
img.Image _trim(img.Image im, {int pad = 0}) {
  var minX = im.width, minY = im.height, maxX = -1, maxY = -1;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).a > 8) {
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
    }
  }
  if (maxX < 0) return im;
  final x0 = math.max(0, minX - pad), y0 = math.max(0, minY - pad);
  final x1 = math.min(im.width - 1, maxX + pad), y1 = math.min(im.height - 1, maxY + pad);
  return img.copyCrop(im, x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1);
}

/// Every cutout at 2× on the app's dark background and on white, side by side,
/// to check halos, specks and shadows.
void _contactSheet(List<(String, img.Image)> items) {
  const cell = 300, cols = 6;
  final rows = (items.length / cols).ceil();
  final out = img.Image(width: cell * cols * 2, height: cell * rows, numChannels: 4);
  img.fill(out, color: img.ColorRgba8(0x12, 0x12, 0x12, 255));
  img.fillRect(out,
      x1: cell * cols, y1: 0, x2: out.width - 1, y2: out.height - 1, color: img.ColorRgba8(255, 255, 255, 255));
  for (var i = 0; i < items.length; i++) {
    final (_, im) = items[i];
    final s = math.min(2.0, (cell - 16) / math.max(im.width, im.height));
    final scaled = img.copyResize(im, width: (im.width * s).round(), interpolation: img.Interpolation.cubic);
    for (final half in [0, cell * cols]) {
      img.compositeImage(out, scaled,
          dstX: half + (i % cols) * cell + (cell - scaled.width) ~/ 2,
          dstY: (i ~/ cols) * cell + (cell - scaled.height) ~/ 2);
    }
  }
  Directory('build').createSync(recursive: true);
  File('build/character_contact_sheet.png').writeAsBytesSync(img.encodePng(out));
  stdout.writeln('contact sheet → build/character_contact_sheet.png');
}
