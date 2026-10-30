import 'package:flutter/material.dart';

/// User-visible, accessible switch for spoken turn-by-turn guidance.
class VoiceGuidanceToggle extends StatelessWidget {
  const VoiceGuidanceToggle({super.key, required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
    const Icon(Icons.volume_up_outlined),
    const SizedBox(width: 8),
    const Expanded(child: Text('Indicaciones por voz')),
    Semantics(
      label: 'Indicaciones por voz',
      value: enabled ? 'Activadas' : 'Desactivadas',
      toggled: enabled,
      child: Switch.adaptive(value: enabled, onChanged: onChanged),
    ),
  ]);
}
