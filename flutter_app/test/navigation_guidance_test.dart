import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:beta_app/maps/maps_models.dart';
import 'package:beta_app/maps/navigation_guidance.dart';

class FakeSpeech implements SpeechOutput {
  final spoken = <String>[];
  int stops = 0;
  @override
  Future<void> speak(String text) async { spoken.add(text); }
  @override
  Future<void> stop() async { stops++; }
}

NavigationRoute sampleRoute({String instruction = 'Gira a la derecha'}) => NavigationRoute(
  points: const [MapPoint(0, 0), MapPoint(0, .001), MapPoint(0, .002)],
  steps: [RouteStep(instruction: instruction, distanceMeters: 100, waypointIndex: 1)],
  distanceMeters: 222,
  durationSeconds: 30,
  profile: 'driving-car',
);

void main() {
  test('speaks once per distance threshold and step change', () async {
    final speech = FakeSpeech();
    final guidance = VoiceGuidanceEngine(speech);
    final route = sampleRoute();
    await guidance.update(route: route, position: const MapPoint(0, .0005), progressIndex: 0);
    await guidance.update(route: route, position: const MapPoint(0, .0006), progressIndex: 0);
    expect(speech.spoken, hasLength(1));
    final changed = NavigationRoute(
      points: route.points,
      steps: [
        route.steps.first,
        const RouteStep(instruction: 'Sigue recto', distanceMeters: 80, waypointIndex: 2),
      ],
      distanceMeters: route.distanceMeters,
      durationSeconds: route.durationSeconds,
      profile: route.profile,
    );
    await guidance.update(route: changed, position: const MapPoint(0, .0015), progressIndex: 2);
    expect(speech.spoken, hasLength(2));
    expect(speech.spoken.last, contains('Sigue recto'));
  });

  test('voice toggle prevents speech while disabled and resumes after enabled', () async {
    final speech = FakeSpeech();
    final guidance = VoiceGuidanceEngine(speech);
    final route = sampleRoute();
    await guidance.setEnabled(false);
    await guidance.update(route: route, position: const MapPoint(0, .0005), progressIndex: 0);
    expect(speech.spoken, isEmpty);
    expect(speech.stops, 1);
    await guidance.setEnabled(true);
    await guidance.update(route: route, position: const MapPoint(0, .0005), progressIndex: 0);
    expect(speech.spoken, hasLength(1));
  });

  test('off-route detection requires consecutive fixes and recovers inside hysteresis', () {
    final detector = OffRouteDetector();
    const route = [MapPoint(0, 0), MapPoint(0, .01)];
    expect(detector.update(route, const MapPoint(.0001, .005)), isFalse);
    expect(detector.update(route, const MapPoint(.001, .005)), isFalse);
    expect(detector.update(route, const MapPoint(.001, .005)), isTrue);
    expect(detector.update(route, const MapPoint(.0001, .005)), isFalse);
    expect(detector.update(route, const MapPoint(.001, .005)), isFalse);
  });

  test('off-route detector calculates distance to segment interior', () {
    expect(distanceToPolylineMeters(const [MapPoint(0, 0), MapPoint(0, .01)], const MapPoint(.001, .005)), closeTo(111, 3));
  });

  test('reroute uses latest origin and suppresses concurrent and cooldown requests', () async {
    var now = DateTime(2026, 1, 1);
    final coordinator = RerouteCoordinator(clock: () => now);
    var requests = 0;
    final pending = Completer<NavigationRoute>();
    final request = (MapPoint origin, MapPoint destination, String profile) {
      requests++;
      expect(origin.latitude, 1);
      expect(destination.longitude, 4);
      expect(profile, 'driving-car');
      return pending.future;
    };
    final first = coordinator.reroute(origin: const MapPoint(1, 2), destination: const MapPoint(3, 4), profile: 'driving-car', request: request);
    final suppressed = await coordinator.reroute(origin: const MapPoint(1, 2), destination: const MapPoint(3, 4), profile: 'driving-car', request: request);
    expect(suppressed, isNull);
    expect(requests, 1);
    pending.complete(sampleRoute());
    expect(await first, isNotNull);
    expect(await coordinator.reroute(origin: const MapPoint(1, 2), destination: const MapPoint(3, 4), profile: 'driving-car', request: request), isNull);
    now = now.add(const Duration(seconds: 31));
    expect(await coordinator.reroute(origin: const MapPoint(1, 2), destination: const MapPoint(3, 4), profile: 'driving-car', request: request), isNotNull);
    expect(requests, 2);
  });

  test('reroute failure releases lock and leaves existing route untouched', () async {
    final coordinator = RerouteCoordinator();
    final existingRoute = sampleRoute();
    final result = await coordinator.reroute(
      origin: const MapPoint(1, 2), destination: const MapPoint(3, 4), profile: 'driving-car',
      request: (_, __, ___) => Future<NavigationRoute>.error(StateError('offline')),
    ).catchError((_) => existingRoute);
    expect(result, same(existingRoute));
    expect(coordinator.inFlight, isFalse);
  });
}
