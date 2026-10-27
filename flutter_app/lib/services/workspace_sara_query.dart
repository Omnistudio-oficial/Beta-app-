enum WorkspaceQueryService { gmail, calendar, drive }

class WorkspaceQueryIntent {
  const WorkspaceQueryIntent({required this.service, required this.query});

  final WorkspaceQueryService service;
  final String query;

  static WorkspaceQueryIntent? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final normalized = text.toLowerCase();
    final service = normalized.contains('gmail') || normalized.contains('correo') || normalized.contains('email') || normalized.contains('mail')
        ? WorkspaceQueryService.gmail
        : normalized.contains('calendar') || normalized.contains('calendario') || normalized.contains('agenda') || normalized.contains('evento') || normalized.contains('reunión') || normalized.contains('cita')
            ? WorkspaceQueryService.calendar
            : normalized.contains('drive') || normalized.contains('archivo') || normalized.contains('documento') || normalized.contains('pdf')
                ? WorkspaceQueryService.drive
                : null;
    if (service == null) return null;
    final query = text.replaceAll(RegExp(r'\b(sara|busca|buscar|encuentra|encontrar|revisa|revisar|consulta|consultar|muestra|mostrar|dime|decime|en|de|del|mi|mis|google|gmail|correo|correos|email|emails|mail|calendar|calendario|agenda|drive|archivo|archivos|documento|documentos|pdf|evento|eventos|reunion|reunión|reuniones|cita|citas|proximos|próximos|proximas|próximas|tengo|hay|que|qué|sobre|acerca)\b', caseSensitive: false), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return WorkspaceQueryIntent(service: service, query: query);
  }
}

String formatWorkspaceAnswer(WorkspaceQueryService service, List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) {
    return switch (service) {
      WorkspaceQueryService.gmail => 'No encontré correos que coincidan en tu bandeja de entrada.',
      WorkspaceQueryService.calendar => 'No encontré eventos próximos en tu calendario para los próximos 7 días.',
      WorkspaceQueryService.drive => 'No encontré archivos que coincidan en Drive.',
    };
  }
  final lines = rows.take(5).map((row) {
    return switch (service) {
      WorkspaceQueryService.gmail => '• ${(row['subject'] ?? '(sin asunto)')} — ${(row['from'] ?? 'remitente desconocido')}\n  ${(row['snippet'] ?? '')}',
      WorkspaceQueryService.calendar => '• ${(row['summary'] ?? 'Evento sin título')} — ${_eventStart(row)}',
      WorkspaceQueryService.drive => '• ${(row['name'] ?? 'Archivo sin nombre')} (${(row['mimeType'] ?? 'tipo desconocido')})',
    };
  }).join('\n');
  return 'Encontré ${rows.length} resultado(s):\n$lines';
}

String _eventStart(Map<String, dynamic> row) {
  final start = row['start'];
  if (start is Map<String, dynamic>) return (start['dateTime'] ?? start['date'] ?? 'hora no disponible').toString();
  return 'hora no disponible';
}
