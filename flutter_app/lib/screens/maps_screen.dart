import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:beta_app/maps/navigation_guidance.dart';
import 'package:beta_app/maps/tts_speech_output.dart';
import 'package:beta_app/maps/maps_models.dart';
import 'package:beta_app/maps/ors_maps_api.dart';
import 'package:beta_app/maps/maps_controls.dart';

class MapsScreen extends StatefulWidget {
  const MapsScreen({super.key, this.api, this.positionStream, this.currentPosition, this.showMap = true, this.autoLocate = true, this.speechOutput});
  final OrsMapsApi? api;
  final SpeechOutput? speechOutput;
  final Stream<Position>? positionStream;
  final Future<Position> Function()? currentPosition;
  final bool showMap;
  final bool autoLocate;
  @override
  State<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends State<MapsScreen> {
  late final OrsMapsApi _api = widget.api ?? OrsMapsApi();
  final _destinationController = TextEditingController();
  MapLibreMapController? _map;
  Position? _position;
  StreamSubscription<Position>? _positionSubscription;
  MapPlace? _destination;
  List<MapPlace> _suggestions = [];
  NavigationRoute? _route;
  String? _originAddress;
  String? _error;
  String _profile = 'driving-car';
  bool _loading = false;
  bool _guiding = false;
  bool _rerouting = false;
  bool _voiceEnabled = true;
  MapBaseLayer _layer = MapBaseLayer.options.first;
  int _progressIndex = 0;
  final FlutterTts _tts = FlutterTts();
  late final VoiceGuidanceEngine _voice;
  final OffRouteDetector _offRouteDetector = OffRouteDetector();
  final RerouteCoordinator _rerouteCoordinator = RerouteCoordinator();
  static const _profiles = <String, String>{
    'Auto': 'driving-car', 'A pie': 'foot-walking', 'Bici': 'cycling-regular',
    'Bici eléctrica': 'cycling-electric', 'Senderismo': 'foot-hiking',
    'Silla de ruedas': 'wheelchair',
  };

  @override
  void initState() {
    super.initState();
    _voice = VoiceGuidanceEngine(widget.speechOutput ?? TtsSpeechOutput(_tts));
    _voice.setEnabled(_voiceEnabled);
    if (widget.speechOutput == null) {
      _tts.setLanguage('es-CR').catchError((_) => _tts.setLanguage('es'));
      _tts.setSpeechRate(0.48);
      _tts.setVolume(1.0);
    }
    if (widget.autoLocate) _locate();
  }
  @override
  void dispose() { _positionSubscription?.cancel(); _tts.stop(); _destinationController.dispose(); super.dispose(); }

  Future<void> _locate() async {
    try {
      var enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw Exception('Activa los servicios de ubicación del dispositivo.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw Exception('Se necesita permiso de ubicación para iniciar la navegación.');
      final position = await (widget.currentPosition?.call() ?? Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)));
      if (!mounted) return;
      setState(() { _position = position; _error = null; });
      _setOrigin(position);
      _positionSubscription ??= (widget.positionStream ?? Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5))).listen(_onPosition, onError: (_) { if (mounted) setState(() => _error = 'Se perdió la señal GPS. La navegación continúa con la última ubicación disponible.'); });
    } catch (error) { if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', '')); }
  }

  void _setOrigin(Position p) {
    final point = MapPoint(p.latitude, p.longitude);
    _api.reverseGeocode(point).then((address) { if (mounted) setState(() => _originAddress = address == 'Ubicación actual' ? 'Tu ubicación actual' : address); }).catchError((_) { if (mounted) setState(() => _originAddress = 'Tu ubicación actual'); });
    _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 15));
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    setState(() => _position = p);
    if (_guiding) {
      final route = _route;
      if (route == null) return;
      final point = MapPoint(p.latitude, p.longitude);
      final index = nearestPointIndex(route.points, point);
      setState(() => _progressIndex = index);
      _map?.animateCamera(CameraUpdate.newLatLng(LatLng(p.latitude, p.longitude)));
      _voice.update(route: route, position: point, progressIndex: index);
      if (_offRouteDetector.update(route.points, point)) _reroute(point);
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 3) return;
    setState(() { _loading = true; _error = null; });
    try { final found = await _api.searchPlaces(query.trim()); if (mounted) setState(() => _suggestions = found); }
    catch (_) { if (mounted) setState(() => _error = 'No se pudo buscar el destino. Revisa tu conexión e inténtalo de nuevo.'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _makeRoute() async {
    final origin = _position; final destination = _destination;
    if (origin == null || destination == null) { setState(() => _error = 'Selecciona un destino y espera la ubicación GPS.'); return; }
    setState(() { _loading = true; _error = null; _guiding = false; });
    try {
      final route = await _api.directions(MapPoint(origin.latitude, origin.longitude), destination.point, _profile);
      if (!mounted) return;
      setState(() { _route = route; _progressIndex = 0; });
      await _drawRoute(route);
      _map?.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(
        southwest: LatLng(route.points.map((p) => p.latitude).reduce((a,b) => a < b ? a : b), route.points.map((p) => p.longitude).reduce((a,b) => a < b ? a : b)),
        northeast: LatLng(route.points.map((p) => p.latitude).reduce((a,b) => a > b ? a : b), route.points.map((p) => p.longitude).reduce((a,b) => a > b ? a : b))), left: 32, top: 120, right: 32, bottom: 220));
    } catch (_) { if (mounted) setState(() => _error = 'No se pudo calcular la ruta. Revisa la conexión, el destino o el modo de viaje e inténtalo de nuevo.'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _reroute(MapPoint origin) async {
    final destination = _destination;
    final currentRoute = _route;
    if (!_guiding || destination == null || currentRoute == null || _rerouting) return;
    setState(() { _rerouting = true; _error = null; });
    try {
      final updated = await _rerouteCoordinator.reroute(
        origin: origin,
        destination: destination.point,
        profile: currentRoute.profile,
        request: _api.directions,
      );
      if (!mounted || updated == null) return;
      // Preserve the existing route unless a complete replacement was received.
      setState(() { _route = updated; _progressIndex = 0; });
      _offRouteDetector.update(updated.points, origin);
      _voice.reset();
      await _drawRoute(updated);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo recalcular la ruta. Se mantiene la ruta anterior.');
    } finally {
      if (mounted) setState(() => _rerouting = false);
    }
  }

  Future<void> _setVoiceEnabled(bool enabled) async {
    setState(() => _voiceEnabled = enabled);
    await _voice.setEnabled(enabled);
  }

  Future<void> _drawRoute(NavigationRoute route) async {
    final map = _map; if (map == null) return;
    await map.clearLines();
    if (route.points.length > 1) await map.addLine(LineOptions(geometry: route.points.map((p) => LatLng(p.latitude, p.longitude)).toList(), lineColor: '#6C63FF', lineWidth: 6, lineOpacity: .9));
  }

  void _startGuidance() {
    if (_route == null || _position == null) return;
    setState(() { _guiding = true; _progressIndex = nearestPointIndex(_route!.points, MapPoint(_position!.latitude, _position!.longitude)); });
    _offRouteDetector.update(_route!.points, MapPoint(_position!.latitude, _position!.longitude));
    _voice.reset();
  }

  double get _remainingDistance {
    final route = _route; if (route == null) return 0;
    var remaining = 0.0;
    for (var i = _progressIndex; i < route.points.length - 1; i++) remaining += distanceMeters(route.points[i], route.points[i + 1]);
    return remaining;
  }

  RouteStep? get _nextStep {
    final route = _route;
    return route == null ? null : nextRouteStep(route, _progressIndex);
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    return Scaffold(appBar: AppBar(title: const Text('Maps')),
      body: Stack(children: [
        if (widget.showMap) MapLibreMap(styleString: _layer.styleUrl, initialCameraPosition: CameraPosition(target: LatLng(_position?.latitude ?? 9.992299, _position?.longitude ?? -84.1248515), zoom: 12), myLocationEnabled: true, myLocationTrackingMode: _guiding ? MyLocationTrackingMode.tracking : MyLocationTrackingMode.none, onMapCreated: (map) { _map = map; if (route != null) _drawRoute(route); }, onStyleLoadedCallback: () { final current = _route; if (current != null) _drawRoute(current); }, compassEnabled: true) else const ColoredBox(color: Color(0xFF101018)),
        Positioned(top: _guiding ? 100 : 96, right: 12, child: MapsControls(
          layer: _layer,
          onZoomIn: () => _zoom(1),
          onZoomOut: () => _zoom(-1),
          onLocate: _recenter,
          onLayerChanged: _changeLayer,
        )),
        if (!_guiding) Positioned(top: 10, left: 12, right: 12, child: _searchPanel()),
        if (_guiding && route != null) Positioned(top: 12, left: 12, right: 12, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [const Icon(Icons.turn_right, size: 32), const SizedBox(width: 12), Expanded(child: Text(_nextStep?.instruction ?? 'Sigue la ruta', style: Theme.of(context).textTheme.titleMedium))])))),
        if (route != null) Positioned(left: 12, right: 12, bottom: 16, child: _routePanel(route)),
        if (_loading || _rerouting) const Positioned(top: 90, left: 0, right: 0, child: Center(child: CircularProgressIndicator())),
        if (_error != null) Positioned(left: 12, right: 12, bottom: route == null ? 16 : 140, child: Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)))),
      ]));
  }

  void _zoom(double amount) {
    final map = _map;
    if (map == null) return;
    map.animateCamera(CameraUpdate.zoomBy(amount));
  }

  void _recenter() {
    final position = _position;
    if (position == null) {
      if (mounted) setState(() => _error = 'Esperando una ubicación GPS válida para centrar el mapa.');
      return;
    }
    _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(position.latitude, position.longitude), 16));
  }

  Future<void> _changeLayer(MapBaseLayer layer) async {
    final previous = _layer;
    setState(() { _layer = layer; _error = null; });
    final map = _map;
    if (map == null) return;
    try {
      await map.setStyle(layer.styleUrl);
    } catch (_) {
      if (mounted) setState(() { _layer = previous; _error = 'No se pudo cargar esa capa. Revisa tu conexión e inténtalo de nuevo.'; });
    }
  }

  Widget _searchPanel() => Card(elevation: 6, child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Row(children: [const Icon(Icons.my_location), const SizedBox(width: 8), Expanded(child: Text(_originAddress ?? (_position == null ? 'Obteniendo ubicación…' : 'Tu ubicación actual'), maxLines: 1, overflow: TextOverflow.ellipsis))]),
    const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: _destinationController, textInputAction: TextInputAction.search, onSubmitted: _search, decoration: const InputDecoration(hintText: 'Buscar destino', prefixIcon: Icon(Icons.search), isDense: true))), IconButton(onPressed: () => _search(_destinationController.text), icon: const Icon(Icons.search))]),
    if (_suggestions.isNotEmpty) ..._suggestions.map((place) => ListTile(dense: true, leading: const Icon(Icons.place), title: Text(place.label, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () { setState(() { _destination = place; _destinationController.text = place.label; _suggestions = []; }); _makeRoute(); })),
    Row(children: [const Text('Ruta:'), const SizedBox(width: 8), Expanded(child: DropdownButton<String>(isExpanded: true, value: _profile, items: _profiles.entries.map((e) => DropdownMenuItem(value: e.value, child: Text(e.key))).toList(), onChanged: (value) { if (value != null) setState(() { _profile = value; _route = null; }); }))]),
  ])));

  Widget _routePanel(NavigationRoute route) {
    final remaining = _guiding ? _remainingDistance : route.distanceMeters;
    final seconds = _guiding ? route.durationSeconds * (remaining / (route.distanceMeters == 0 ? 1 : route.distanceMeters)) : route.durationSeconds;
    final arrived = _guiding && remaining < 35;
    return Card(elevation: 8, child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(arrived ? 'Llegaste a tu destino' : _guiding ? (_nextStep?.instruction ?? 'Continúa por la ruta') : (_destination?.label ?? 'Ruta'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Text(_formatDistance(remaining)), Text(_formatDuration(seconds)), Text(_arrival(seconds))]),
      if (_guiding) Row(children: [
        const Icon(Icons.volume_up_outlined),
        const SizedBox(width: 8),
        const Expanded(child: Text('Indicaciones por voz')),
        Semantics(
          label: 'Indicaciones por voz',
          value: _voiceEnabled ? 'Activadas' : 'Desactivadas',
          toggled: _voiceEnabled,
          child: Switch.adaptive(
            value: _voiceEnabled,
            onChanged: _setVoiceEnabled,
          ),
        ),
      ]),
      if (_rerouting) const Align(alignment: Alignment.centerLeft, child: Text('Recalculando ruta…')),
      if (_guiding && !_voiceEnabled) const Align(alignment: Alignment.centerLeft, child: Text('Indicaciones por voz desactivadas')),
      if (_guiding && _voiceEnabled) const Align(alignment: Alignment.centerLeft, child: Text('Indicaciones por voz activadas')), 
      const SizedBox(height: 10), if (!_guiding) SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _startGuidance, icon: const Icon(Icons.navigation), label: const Text('Iniciar navegación'))) else TextButton.icon(onPressed: () { setState(() { _guiding = false; _rerouting = false; }); _voice.reset(); _tts.stop(); }, icon: const Icon(Icons.stop), label: const Text('Finalizar navegación')),
    ])));
  }

  String _formatDistance(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
  String _formatDuration(double s) { final min = (s / 60).ceil(); return min >= 60 ? '${min ~/ 60} h ${min % 60} min' : '$min min'; }
  String _arrival(double s) { final time = DateTime.now().add(Duration(seconds: s.round())); final h = time.hour.toString().padLeft(2, '0'); final m = time.minute.toString().padLeft(2, '0'); return 'Llegada $h:$m'; }
}
