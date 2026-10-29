import 'package:beta_app/social/face_sticker_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  group('face sticker preview geometry', () {
    test('scales and crops a portrait source to a landscape viewport', () {
      final point = mapFacePointToPreview(
        const Offset(50, 100),
        const Size(100, 200),
        const Size(300, 100),
        mirror: false,
      );
      // cover scale is 3x: rendered height 600, cropped vertically by 250.
      expect(point.dx, 150);
      expect(point.dy, 50);
    });

    test('selfie mirror reflects coordinates in the cropped viewport', () {
      final point = mapFacePointToPreview(
        const Offset(25, 50),
        const Size(100, 100),
        const Size(200, 100),
        mirror: true,
      );
      // Cover scale 2, horizontal crop 0, mirrored x = 200 - 50.
      expect(point, const Offset(150, 50));
    });

    test('mirrored face rectangle remains normalized and has expected width', () {
      final rect = mapFaceRectToPreview(
        const Rect.fromLTWH(10, 20, 30, 40),
        const Size(100, 100),
        const Size(200, 100),
        mirror: true,
      );
      expect(rect.left, 120);
      expect(rect.right, 180);
      expect(rect.top, -10);
      expect(rect.bottom, 70);
    });
  });
}
