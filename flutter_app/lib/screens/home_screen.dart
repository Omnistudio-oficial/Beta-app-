import 'package:flutter/material.dart';

/// Flutter landing page for the migrated OmniStudio modules.
/// Navigation stays owned by [NavigationShell], so the dashboard does not
/// create duplicate routes or alter the existing module state.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.displayName,
    required this.onNavigate,
    required this.onSignOut,
  });

  final String displayName;
  final ValueChanged<int> onNavigate;
  final VoidCallback onSignOut;

  static const _tools = <_HomeTool>[
    _HomeTool('Chat', 'Conversaciones y llamadas', Icons.chat_bubble_outline, 1),
    _HomeTool('Música', 'Tus proyectos de audio', Icons.music_note_outlined, 2),
    _HomeTool('Maps', 'Mapas y rutas', Icons.map_outlined, 3),
    _HomeTool('Asistente IA', 'Pregunta o crea con IA', Icons.smart_toy_outlined, 4),
    _HomeTool('Documentos', 'Documentos y archivos', Icons.description_outlined, 5),
    _HomeTool('Social', 'Publicaciones y comunidad', Icons.groups_outlined, 6),
    _HomeTool('Convertir', 'Convierte formatos', Icons.swap_horiz, 7),
    _HomeTool('Perfil', 'Tu cuenta y preferencias', Icons.person_outline, 9),
  ];

  @override
  Widget build(BuildContext context) {
    final name = displayName.trim();
    final greeting = name.isEmpty ? 'Bienvenido' : 'Hola, $name';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OmniStudio'),
        actions: [
          IconButton(
            key: const Key('home_sign_out'),
            tooltip: 'Cerrar sesión',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(greeting, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('¿Qué quieres hacer hoy?', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 22),
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(Icons.dashboard_customize_outlined, size: 34, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tu espacio de trabajo', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('Accede rápidamente a las herramientas de OmniStudio.', style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Accesos rápidos', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 560 ? 3 : 2;
                return GridView.builder(
                  key: const Key('home_quick_access_grid'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _tools.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 116,
                  ),
                  itemBuilder: (context, index) {
                    final tool = _tools[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: Key('home_tool_${tool.label.toLowerCase().replaceAll(' ', '_')}'),
                        onTap: () => onNavigate(tool.destination),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(tool.icon, color: theme.colorScheme.primary),
                              const SizedBox(height: 8),
                              Text(tool.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              Text(tool.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTool {
  const _HomeTool(this.label, this.description, this.icon, this.destination);
  final String label;
  final String description;
  final IconData icon;
  final int destination;
}
