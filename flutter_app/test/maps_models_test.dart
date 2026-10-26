import 'package:flutter_test/flutter_test.dart';
import 'package:beta_app/maps/maps_models.dart';

void main() {
  test('route progress uses nearest polyline point', () {
    const route = [MapPoint(0, 0), MapPoint(0, 1), MapPoint(1, 1)];
    expect(nearestPointIndex(route, const MapPoint(.02, .98)), 1);
  });

  test('distance calculation is finite and positive', () {
    final distance = distanceMeters(const MapPoint(0, 0), const MapPoint(0, 1));
    expect(distance, greaterThan(110000));
    expect(distance, lessThan(112000));
  });
}
