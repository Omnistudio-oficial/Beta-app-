import 'dart:math' as math;

class MapPoint {
  const MapPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
  List<double> get ors => [longitude, latitude];
}

class MapPlace {
  const MapPlace({required this.label, required this.point});
  final String label;
  final MapPoint point;
}

class RouteStep {
  const RouteStep({required this.instruction, required this.distanceMeters, required this.waypointIndex, int? maneuverIndex})
      : maneuverIndex = maneuverIndex ?? waypointIndex;
  final String instruction;
  final double distanceMeters;
  final int waypointIndex;
  /// Polyline index where this step's maneuver ends/begins, when supplied by ORS.
  final int maneuverIndex;
}

class NavigationRoute {
  const NavigationRoute({required this.points, required this.steps, required this.distanceMeters, required this.durationSeconds, required this.profile});
  final List<MapPoint> points;
  final List<RouteStep> steps;
  final double distanceMeters;
  final double durationSeconds;
  final String profile;
}

double distanceMeters(MapPoint a, MapPoint b) {
  const radius = 6371000.0;
  final dLat = _rad(b.latitude - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLon / 2), 2);
  return radius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _rad(double value) => value * math.pi / 180;

int nearestPointIndex(List<MapPoint> points, MapPoint position) {
  if (points.isEmpty) return 0;
  var best = 0;
  var distance = double.infinity;
  for (var i = 0; i < points.length; i++) {
    final candidate = distanceMeters(points[i], position);
    if (candidate < distance) { distance = candidate; best = i; }
  }
  return best;
}

/// Returns the upcoming instruction based on the point where its maneuver occurs.
/// ORS step waypoints span the segment; using the first waypoint repeats a step
/// for most of its length, while the final waypoint tracks the maneuver itself.
RouteStep? nextRouteStep(NavigationRoute route, int progressIndex) {
  if (route.steps.isEmpty) return null;
  for (final step in route.steps) {
    if (step.maneuverIndex >= progressIndex) return step;
  }
  return route.steps.last;
}
