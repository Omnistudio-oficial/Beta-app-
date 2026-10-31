import 'package:beta_app/maps/maps_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('base layers stay on free OpenFreeMap styles', () {
    expect(MapBaseLayer.options.map((layer) => layer.id), ['liberty', 'bright', 'positron']);
    expect(MapBaseLayer.options.every((layer) => layer.styleUrl.startsWith('https://tiles.openfreemap.org/styles/')), isTrue);
  });

  testWidgets('zoom, locate, and layer controls expose accessible actions', (tester) async {
    var zoomIn = 0;
    var zoomOut = 0;
    var locate = 0;
    MapBaseLayer? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapsControls(
      layer: MapBaseLayer.options.first,
      onZoomIn: () => zoomIn++,
      onZoomOut: () => zoomOut++,
      onLocate: () => locate++,
      onLayerChanged: (layer) => selected = layer,
    ))));
    await tester.tap(find.byTooltip('Acercar mapa'));
    await tester.tap(find.byTooltip('Alejar mapa'));
    await tester.tap(find.byTooltip('Ir a mi ubicación'));
    expect((zoomIn, zoomOut, locate), (1, 1, 1));
    await tester.tap(find.byTooltip('Cambiar capa del mapa'));
    await tester.pumpAndSettle();
    expect(find.text('Claro'), findsOneWidget);
    await tester.tap(find.text('Claro'));
    expect(selected?.id, 'bright');
  });
}
