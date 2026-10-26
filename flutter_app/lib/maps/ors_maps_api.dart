import 'dart:convert';
import 'package:http/http.dart' as http;
import 'maps_models.dart';

const orsApiKey = String.fromEnvironment('OPENROUTESERVICE_API_KEY');

class OrsMapsApi {
  OrsMapsApi({http.Client? client, String? apiKey, this.baseUrl = 'https://api.openrouteservice.org'})
      : _client = client ?? http.Client(), _apiKey = apiKey ?? orsApiKey;
  final http.Client _client;
  final String _apiKey;
  final String baseUrl;

  Future<List<MapPlace>> searchPlaces(String query) async {
    final data = await _get('/geocode/search', {'text': query, 'size': '6'});
    final features = data['features'] as List? ?? const [];
    return features.map((item) {
      final feature = item as Map<String, dynamic>;
      final coordinates = (feature['geometry']['coordinates'] as List).cast<num>();
      final label = (feature['properties']['label'] ?? feature['properties']['name'] ?? 'Place').toString();
      return MapPlace(label: label, point: MapPoint(coordinates[1].toDouble(), coordinates[0].toDouble()));
    }).toList();
  }

  Future<String> reverseGeocode(MapPoint point) async {
    final data = await _get('/geocode/reverse', {'point.lon': '${point.longitude}', 'point.lat': '${point.latitude}', 'size': '1'});
    final features = data['features'] as List? ?? const [];
    if (features.isEmpty) return 'Ubicación actual';
    final props = (features.first as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
    return (props['label'] ?? props['name'] ?? 'Ubicación actual').toString();
  }

  Future<NavigationRoute> directions(MapPoint from, MapPoint to, String profile) async {
    final response = await _client.post(Uri.parse('$baseUrl/v2/directions/$profile/geojson'),
      headers: {'Authorization': _apiKey, 'Content-Type': 'application/json; charset=utf-8', 'Accept': 'application/geo+json'},
      body: jsonEncode({'coordinates': [from.ors, to.ors], 'instructions': true, 'geometry': true, 'units': 'm'}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw OrsException('Route service returned ${response.statusCode}');
    final feature = (jsonDecode(response.body) as Map<String, dynamic>)['features'][0] as Map<String, dynamic>;
    final geometry = feature['geometry']['coordinates'] as List;
    final summary = feature['properties']['summary'] as Map<String, dynamic>;
    final segments = feature['properties']['segments'] as List;
    final rawSteps = segments.isEmpty ? const [] : (segments.first['steps'] as List? ?? const []);
    final steps = rawSteps.map((step) {
      final map = step as Map<String, dynamic>;
      final instruction = (map['instruction'] ?? '').toString();
      final waypoints = (map['way_points'] as List?)?.cast<num>() ?? const <num>[];
      return RouteStep(instruction: instruction.isEmpty ? 'Continue on route' : instruction,
        distanceMeters: (map['distance'] as num? ?? 0).toDouble(),
        waypointIndex: waypoints.isEmpty ? 0 : waypoints.first.toInt(),
        maneuverIndex: waypoints.length < 2 ? (waypoints.isEmpty ? 0 : waypoints.first.toInt()) : waypoints.last.toInt());
    }).toList();
    return NavigationRoute(points: geometry.map((pair) { final c = (pair as List).cast<num>(); return MapPoint(c[1].toDouble(), c[0].toDouble()); }).toList(),
      steps: steps, distanceMeters: (summary['distance'] as num).toDouble(), durationSeconds: (summary['duration'] as num).toDouble(), profile: profile);
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> params) async {
    if (_apiKey.isEmpty) throw const OrsException('OpenRouteService key is not configured');
    final response = await _client.get(Uri.parse('$baseUrl$path').replace(queryParameters: {...params, 'api_key': _apiKey}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw OrsException('Place service returned ${response.statusCode}');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class OrsException implements Exception {
  const OrsException(this.message);
  final String message;
  @override
  String toString() => message;
}
