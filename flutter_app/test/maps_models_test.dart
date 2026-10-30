import 'package:flutter_test/flutter_test.dart';
import 'package:beta_app/maps/maps_models.dart';

void main() {
  test('route progress uses nearest polyline point', () {
    const route = [MapPoint(0, 0), MapPoint(0, 1), MapPoint(1, 1)];
    expect(nearestPointIndex(route, const MapPoint(.02, .98)), 1);
  });

  test('next instruction follows maneuver waypoint, not segment start', () {
    const route = NavigationRoute(points: [MapPoint(0, 0), MapPoint(0, 1), MapPoint(0, 2)],
      steps: [RouteStep(instruction: 'Sigue recto', distanceMeters: 100, waypointIndex: 0, maneuverIndex: 1),
        RouteStep(instruction: 'Gira a la derecha', distanceMeters: 20, waypointIndex: 1, maneuverIndex: 2)],
      distanceMeters: 200, durationSeconds: 60, profile: 'driving-car');
    expect(nextRouteStep(route, 0)?.instruction, 'Sigue recto');
    expect(nextRouteStep(route, 1)?.instruction, 'Sigue recto');
    expect(nextRouteStep(route, 2)?.instruction, 'Gira a la derecha');
    expect(nextRouteStep(route, 3)?.instruction, 'Gira a la derecha');
  });

  test('distance calculation is finite and positive', () {
    final distance = distanceMeters(const MapPoint(0, 0), const MapPoint(0, 1));
    expect(distance, greaterThan(110000));
    expect(distance, lessThan(112000));
  });
}
