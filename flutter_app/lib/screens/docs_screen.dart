import 'dart:ui' show Rect;

import 'package:flutter/material.dart';

import 'docs_storage.dart';
import 'docs_txt_export.dart';

/// Local-only document workspace. It does not read or write account/backend data.
class DocsScreen extends StatefulWidget {
  const DocsScreen({super.key, this.storage, this.txtExporter});

  /// Injectable for tests; production uses app-scoped SharedPreferences storage.
  final DocumentsStorage? storage;

  /// Injectable so the export flow can be tested without opening a platform sheet.
  final DocsTxtExporter? txtExporter;

  @override
  State<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends State<DocsScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final LocalDocumentsRepository _repository;
  List<LocalDocument> _documents = [];
  int _nextId = 0;
  bool _loading = true;
  bool _saving = false;
  int? _exportingDocumentId;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _repository = LocalDocumentsRepository(
      widget.storage ?? SharedPreferencesDocumentsStorage(),
    );
    _loadDocuments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.load();
      if (!mounted) return;
      setState(() {
        _documents = result.documents;
        _nextId = _documents.fold<int>(0, (next, document) =>
            document.id >= next ? document.id + 1 : next);
        _loading = false;
        if (result.recoveredCorruption) {
          _notice = 'Se recuperaron los documentos válidos; algunos datos dañados se omitieron.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los documentos guardados en este dispositivo.';
      });
    }
  }

  List<LocalDocument> get _visibleDocuments {
    final query = _searchController.text.trim().toLowerCase();
    final results = _documents.where((doc) =>
        query.isEmpty ||
        doc.title.toLowerCase().contains(query) ||
        doc.content.toLowerCase().contains(query));
    return results.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _editDocument([LocalDocument? document]) async {
    final result = await showDialog<_DocumentDraft>(
      context: context,
      builder: (_) => _DocumentEditorDialog(document: document),
    );
    if (result == null || !mounted) return;

    final previous = List<LocalDocument>.of(_documents);
    final now = DateTime.now();
    final updated = List<LocalDocument>.of(_documents);
    if (document == null) {
      updated.add(LocalDocument(
        id: _nextId,
        title: result.title,
        content: result.content,
        updatedAt: now,
      ));
    } else {
      final index = updated.indexWhere((item) => item.id == document.id);
      if (index == -1) return;
      updated[index] = document.copyWith(
        title: result.title,
        content: result.content,
        updatedAt: now,
      );
    }
    await _persist(updated, previous, created: document == null);
  }

  Future<void> _exportDocument(
    LocalDocument document,
    BuildContext buttonContext,
  ) async {
    if (_exportingDocumentId != null) return;
    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    final origin = renderBox == null
        ? null
        : renderBox.localToGlobal(Offset.zero) & renderBox.size;
    setState(() => _exportingDocumentId = document.id);
    try {
      await (widget.txtExporter ?? DocsTxtExporter()).export(
        title: document.title,
        content: document.content,
        sharePositionOrigin: origin,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige dónde compartir o guardar el archivo TXT.')),
      );
    } on ArgumentError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El documento necesita un título para exportarse.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo preparar o compartir el archivo TXT.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingDocumentId = null);
    }
  }

  Future<void> _deleteDocument(LocalDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar documento'),
        content: Text('¿Quieres eliminar «${document.title}» de este dispositivo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-delete-document'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final previous = List<LocalDocument>.of(_documents);
    final updated = previous.where((item) => item.id != document.id).toList();
    await _persist(updated, previous);
  }

  Future<void> _persist(
    List<LocalDocument> updated,
    List<LocalDocument> previous, {
    bool created = false,
  }) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await _repository.save(updated);
      if (!mounted) return;
      setState(() {
        _documents = updated;
        if (created) _nextId++;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _documents = previous;
        _saving = false;
        _error = 'No se pudo guardar el cambio en este dispositivo. Inténtalo de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final documents = _visibleDocuments;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Docs'),
        actions: [
          if (_loading || _saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-document'),
        onPressed: _loading || _saving || _error != null ? null : _editDocument,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo documento'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                key: const Key('document-search'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Buscar documentos',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            if (_error != null)
              MaterialBanner(
                key: const Key('documents-error'),
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: _loading || _saving ? null : _loadDocuments,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            if (_notice != null)
              MaterialBanner(
                key: const Key('documents-recovery-notice'),
                content: Text(_notice!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _notice = null),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(key: Key('documents-loading')),
                    )
                  : documents.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _documents.isEmpty
                                      ? Icons.description_outlined
                                      : Icons.search_off,
                                  size: 48,
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _documents.isEmpty
                                      ? 'Aún no tienes documentos'
                                      : 'No se encontraron documentos',
                                  key: const Key('documents-empty-state'),
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(_documents.isEmpty
                                    ? 'Crea un documento para empezar. Se guarda solo en este dispositivo.'
                                    : 'Prueba con otro título o una palabra del contenido.'),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          key: const Key('documents-list'),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                          itemCount: documents.length,
                          itemBuilder: (context, index) {
                            final document = documents[index];
                            return Card(
                              child: ListTile(
                                key: Key('document-${document.id}'),
                                leading: const Icon(Icons.description_outlined,
                                    color: Colors.blue),
                                title: Text(document.title),
                                subtitle: Text(
                                  document.content.isEmpty
                                      ? 'Sin contenido'
                                      : document.content.replaceAll('\n', ' '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: _saving ? null : () => _editDocument(document),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Builder(
                                      builder: (buttonContext) => IconButton(
                                        key: Key('export-document-${document.id}'),
                                        tooltip: 'Exportar ${document.title} como TXT',
                                        onPressed: _saving || _exportingDocumentId != null
                                            ? null
                                            : () => _exportDocument(document, buttonContext),
                                        icon: _exportingDocumentId == document.id
                                            ? const SizedBox.square(
                                                dimension: 20,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.ios_share),
                                      ),
                                    ),
                                    IconButton(
                                      key: Key('delete-document-${document.id}'),
                                      tooltip: 'Eliminar ${document.title}',
                                      onPressed: _saving || _exportingDocumentId != null
                                          ? null
                                          : () => _deleteDocument(document),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentDraft {
  const _DocumentDraft(this.title, this.content);
  final String title;
  final String content;
}

class _DocumentEditorDialog extends StatefulWidget {
  const _DocumentEditorDialog({this.document});
  final LocalDocument? document;

  @override
  State<_DocumentEditorDialog> createState() => _DocumentEditorDialogState();
}

class _DocumentEditorDialogState extends State<_DocumentEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.document?.title ?? '');
    _contentController = TextEditingController(text: widget.document?.content ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un título para el documento')),
      );
      return;
    }
    Navigator.pop(context, _DocumentDraft(title, _contentController.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.document == null ? 'Nuevo documento' : 'Editar documento'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('document-title-input'),
                  controller: _titleController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('document-content-input'),
                  controller: _contentController,
                  minLines: 5,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Contenido',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('save-document'),
            onPressed: _save,
            child: const Text('Guardar'),
          ),
        ],
      );
}
