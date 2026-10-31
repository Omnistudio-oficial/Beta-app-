import 'dart:math' as math;

import 'maps_models.dart';

abstract interface class SpeechOutput {
  Future<void> speak(String text);
  Future<void> stop();
}

/// Produces a small number of distance-triggered announcements per maneuver.
class VoiceGuidanceEngine {
  VoiceGuidanceEngine(this.output);

  final SpeechOutput output;
  bool enabled = true;
  int? _announcedStep;
  final Set<int> _announcedThresholds = <int>{};

  static const thresholdsMeters = <int>[500, 150, 40];

  Future<void> update({
    required NavigationRoute route,
    required MapPoint position,
    required int progressIndex,
  }) async {
    if (!enabled || route.steps.isEmpty || route.points.isEmpty) return;
    final stepIndex = route.steps.indexWhere((step) => step.maneuverIndex >= progressIndex);
    final index = stepIndex < 0 ? route.steps.length - 1 : stepIndex;
    final step = route.steps[index];
    if (_announcedStep != index) {
      _announcedStep = index;
      _announcedThresholds.clear();
    }
    final pointIndex = step.maneuverIndex.clamp(0, route.points.length - 1).toInt();
    final distance = distanceMeters(position, route.points[pointIndex]);
    final crossed = thresholdsMeters.where((threshold) => distance <= threshold).toList();
    final newlyCrossed = crossed.where(_announcedThresholds.add).toList();
    if (newlyCrossed.isNotEmpty) {
      final threshold = newlyCrossed.last;
      final wording = threshold == 40 ? 'Ahora, ${step.instruction}' : 'En $threshold metros, ${step.instruction}';
      try {
        await output.speak(wording);
      } catch (_) {
        // Navigation remains usable when speech services are unavailable.
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    _announcedStep = null;
    _announcedThresholds.clear();
    if (!value) await output.stop();
  }

  void reset() {
    _announcedStep = null;
    _announcedThresholds.clear();
  }
}

/// Hysteresis avoids rerouting on a single noisy GPS fix.
class OffRouteDetector {
  OffRouteDetector({this.offRouteMeters = 50, this.recoveryMeters = 25, this.requiredFixes = 2});

  final double offRouteMeters;
  final double recoveryMeters;
  final int requiredFixes;
  int _outsideFixes = 0;

  bool update(List<MapPoint> route, MapPoint position) {
    final gap = distanceToPolylineMeters(route, position);
    if (gap <= recoveryMeters) {
      _outsideFixes = 0;
      return false;
    }
    if (gap > offRouteMeters) _outsideFixes++;
    else _outsideFixes = 0;
    if (_outsideFixes >= requiredFixes) {
      _outsideFixes = 0;
      return true;
    }
    return false;
  }
}

double distanceToPolylineMeters(List<MapPoint> points, MapPoint position) {
  if (points.isEmpty) return double.infinity;
  if (points.length == 1) return distanceMeters(points.first, position);
  var minimum = double.infinity;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    // Local equirectangular projection is accurate enough for short route segments.
    final latitude = position.latitude * math.pi / 180;
    final xScale = 111320 * math.cos(latitude);
    const yScale = 111320.0;
    final ax = (a.longitude - position.longitude) * xScale;
    final ay = (a.latitude - position.latitude) * yScale;
    final bx = (b.longitude - position.longitude) * xScale;
    final by = (b.latitude - position.latitude) * yScale;
    final dx = bx - ax;
    final dy = by - ay;
    final denominator = dx * dx + dy * dy;
    final t = denominator == 0 ? 0.0 : (-(ax * dx + ay * dy) / denominator).clamp(0.0, 1.0);
    final gap = math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2));
    if (gap < minimum) minimum = gap;
  }
  return minimum;
}

/// Serializes reroute requests and enforces a cooldown, independent of UI.
class RerouteCoordinator {
  RerouteCoordinator({DateTime Function()? clock, this.cooldown = const Duration(seconds: 30)}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration cooldown;
  DateTime? _lastRequest;
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  Future<NavigationRoute?> reroute({
    required MapPoint origin,
    required MapPoint destination,
    required String profile,
    required Future<NavigationRoute> Function(MapPoint, MapPoint, String) request,
  }) async {
    final now = _clock();
    if (_inFlight || (_lastRequest != null && now.difference(_lastRequest!) < cooldown)) return null;
    _inFlight = true;
    _lastRequest = now;
    try {
      return await request(origin, destination, profile);
    } finally {
      _inFlight = false;
    }
  }
}
