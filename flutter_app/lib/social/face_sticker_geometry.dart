import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Maps coordinates in the upright ML Kit image into the preview's BoxFit.cover
/// viewport, applying the front-camera selfie mirror after scaling/cropping.
Offset mapFacePointToPreview(Offset point, Size source, Size viewport, {required bool mirror}) {
  final scale = math.max(viewport.width / source.width, viewport.height / source.height).toDouble();
  final rendered = Size(source.width * scale, source.height * scale);
  final crop = Offset((viewport.width - rendered.width) / 2, (viewport.height - rendered.height) / 2);
  final x = point.dx * scale + crop.dx;
  return Offset(mirror ? viewport.width - x : x, point.dy * scale + crop.dy);
}

Rect mapFaceRectToPreview(Rect rect, Size source, Size viewport, {required bool mirror}) {
  final a = mapFacePointToPreview(rect.topLeft, source, viewport, mirror: mirror);
  final b = mapFacePointToPreview(rect.bottomRight, source, viewport, mirror: mirror);
  return Rect.fromLTRB(
    math.min(a.dx, b.dx),
    math.min(a.dy, b.dy),
    math.max(a.dx, b.dx),
    math.max(a.dy, b.dy),
  );
}
