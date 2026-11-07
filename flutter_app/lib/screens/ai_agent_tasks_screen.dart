import 'package:flutter/material.dart';
import 'package:beta_app/services/ai_agent_tasks_service.dart';

class AiAgentTasksScreen extends StatefulWidget {
  const AiAgentTasksScreen({super.key});

  @override
  State<AiAgentTasksScreen> createState() => _AiAgentTasksScreenState();
}

class _AiAgentTasksScreenState extends State<AiAgentTasksScreen> {
  final _service = AiAgentTasksService();
  final _promptController = TextEditingController();
  final Map<String, AiAgentTask> _tasks = {};
  final Map<String, List<AiAgentTaskStep>> _steps = {};
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _service.close();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _busy = true);
    try {
      final ids = await _service.getSavedTaskIds();
      for (final id in ids) {
        try {
          final task = await _service.getTask(id);
          final steps = await _service.getSteps(id);
          if (!mounted) return;
          setState(() {
            _tasks[id] = task;
            _steps[id] = steps;
          });
        } catch (_) {
          // A deleted or inaccessible task is skipped without exposing details.
        }
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTask() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final created = await _service.createTask(prompt);
      _promptController.clear();
      final task = AiAgentTask(id: created.taskId, status: created.status);
      if (!mounted) return;
      setState(() {
        _tasks[created.taskId] = task;
        _steps[created.taskId] = const [];
        _message = created.status == 'waiting_approval'
            ? 'La tarea quedó pendiente de tu aprobación.'
            : 'Tarea enviada a Sara.';
      });
      await _refreshTask(created.taskId);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshTask(String id) async {
    try {
      final task = await _service.getTask(id);
      final steps = await _service.getSteps(id);
      if (!mounted) return;
      setState(() {
        _tasks[id] = task;
        _steps[id] = steps;
      });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _decide(String id, bool approve) async {
    setState(() => _busy = true);
    try {
      await _service.decide(id, approve: approve);
      await _refreshTask(id);
      if (mounted) {
        setState(() => _message = approve
            ? 'Aprobación enviada. Sara iniciará la tarea.'
            : 'Tarea rechazada y cancelada.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(String status) => switch (status) {
        'queued' => 'En cola',
        'running' => 'En ejecución',
        'waiting_approval' => 'Requiere aprobación',
        'completed' => 'Completada',
        'failed' => 'Falló',
        'cancelled' => 'Cancelada',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks.values.toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tareas autónomas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar tareas',
            onPressed: _busy ? null : _loadHistory,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('¿Qué debe hacer Sara?',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text('Sara dividirá la solicitud en pasos de investigación, conocimiento, análisis y síntesis. Las acciones sensibles requieren tu aprobación.'),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('agent-task-prompt'),
                    controller: _promptController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 20000,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Describe la tarea que quieres que realice…',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('agent-task-create'),
                      onPressed: _busy ? null : _createTask,
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow),
                      label: const Text('Crear tarea'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_message!),
            ),
          const SizedBox(height: 8),
          const Text('Historial de tareas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Todavía no hay tareas guardadas en este dispositivo.'),
            ),
          for (final task in tasks)
            Card(
              key: Key('agent-task-${task.id}'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(_statusLabel(task.status),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          tooltip: 'Actualizar',
                          onPressed: _busy ? null : () => _refreshTask(task.id),
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    Text('ID: ${task.id}', style: Theme.of(context).textTheme.bodySmall),
                    if (task.status == 'waiting_approval') ...[
                      const SizedBox(height: 8),
                      const Text('Esta solicitud está pausada hasta que decidas.'),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _busy ? null : () => _decide(task.id, true),
                            child: const Text('Aprobar'),
                          ),
                          OutlinedButton(
                            onPressed: _busy ? null : () => _decide(task.id, false),
                            child: const Text('Rechazar'),
                          ),
                        ],
                      ),
                    ],
                    if (task.result?['answer'] is String) ...[
                      const Divider(),
                      SelectableText(task.result!['answer'] as String),
                    ],
                    if (task.errorCode != null)
                      Text('Código de error: ${task.errorCode}'),
                    for (final step in (_steps[task.id] ?? const <AiAgentTaskStep>[]))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('${step.number}'),
                        ),
                        title: Text(step.name),
                        subtitle: Text(_statusLabel(step.status)),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
