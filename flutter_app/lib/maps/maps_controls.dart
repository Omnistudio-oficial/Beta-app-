import 'package:flutter/material.dart';

/// Free OpenFreeMap styles only; this intentionally has no commercial tile source.
class MapBaseLayer {
  const MapBaseLayer({required this.id, required this.label, required this.styleUrl});
  final String id;
  final String label;
  final String styleUrl;

  static const options = <MapBaseLayer>[
    MapBaseLayer(id: 'liberty', label: 'Estándar', styleUrl: 'https://tiles.openfreemap.org/styles/liberty'),
    MapBaseLayer(id: 'bright', label: 'Claro', styleUrl: 'https://tiles.openfreemap.org/styles/bright'),
    MapBaseLayer(id: 'positron', label: 'Minimalista', styleUrl: 'https://tiles.openfreemap.org/styles/positron'),
  ];
}

/// Floating map controls are kept separate so their behavior is testable offline.
class MapsControls extends StatelessWidget {
  const MapsControls({super.key, required this.layer, required this.onZoomIn, required this.onZoomOut,
    required this.onLocate, required this.onLayerChanged});

  final MapBaseLayer layer;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onLocate;
  final ValueChanged<MapBaseLayer> onLayerChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 5,
    borderRadius: BorderRadius.circular(14),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      IconButton(tooltip: 'Acercar mapa', onPressed: onZoomIn, icon: const Icon(Icons.add)),
      IconButton(tooltip: 'Alejar mapa', onPressed: onZoomOut, icon: const Icon(Icons.remove)),
      IconButton(tooltip: 'Ir a mi ubicación', onPressed: onLocate, icon: const Icon(Icons.my_location)),
      PopupMenuButton<MapBaseLayer>(
        tooltip: 'Cambiar capa del mapa',
        initialValue: layer,
        onSelected: onLayerChanged,
        itemBuilder: (context) => MapBaseLayer.options.map((item) => PopupMenuItem<MapBaseLayer>(
          value: item,
          child: Row(children: [if (item.id == layer.id) const Icon(Icons.check, size: 18),
            if (item.id == layer.id) const SizedBox(width: 8), Text(item.label)]),
        )).toList(),
        child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.layers_outlined, semanticLabel: 'Cambiar capa del mapa')),
      ),
    ]),
  );
}
