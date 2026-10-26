import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  static const _storageKey = 'social_local_posts';
  final TextEditingController _postController = TextEditingController();
  List<_LocalPost> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getStringList(_storageKey) ?? const <String>[];
      final posts = <_LocalPost>[];
      for (final item in stored) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          posts.add(_LocalPost.fromJson(map));
        } on FormatException {
          // Ignore malformed individual records and keep the rest of the feed.
        } on TypeError {
          // Ignore malformed individual records and keep the rest of the feed.
        }
      }
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar las publicaciones guardadas.';
      });
    }
  }

  Future<void> _createPost() async {
    final text = _postController.text.trim();
    if (text.isEmpty) return;
    final post = _LocalPost(id: DateTime.now().microsecondsSinceEpoch.toString(), text: text);
    final updated = [post, ..._posts];
    setState(() {
      _posts = updated;
      _postController.clear();
      _error = null;
    });
    await _savePosts(updated);
  }

  Future<void> _deletePost(_LocalPost post) async {
    final updated = _posts.where((item) => item.id != post.id).toList();
    setState(() {
      _posts = updated;
      _error = null;
    });
    await _savePosts(updated);
  }

  Future<void> _savePosts(List<_LocalPost> posts) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(
        _storageKey,
        posts.map((post) => jsonEncode(post.toJson())).toList(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo guardar el cambio en este dispositivo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Social')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Publicaciones locales', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Solo se guardan en este dispositivo; todavía no se comparten ni sincronizan.'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('social-post-input'),
                      controller: _postController,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Escribe una publicación',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('social-create-post'),
                    tooltip: 'Guardar publicación',
                    icon: const Icon(Icons.send),
                    onPressed: _postController.text.trim().isEmpty || _postController.text.trim().length > 500
                        ? null
                        : _createPost,
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(_error!, key: const Key('social-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _posts.isEmpty
                      ? const Center(child: Text('Aún no tienes publicaciones locales.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post = _posts[index];
                            return Card(
                              key: Key('social-post-${post.id}'),
                              child: ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                                title: const Text('Tú'),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(post.text),
                                ),
                                trailing: IconButton(
                                  key: Key('delete-post-${post.id}'),
                                  tooltip: 'Eliminar publicación',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deletePost(post),
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

class _LocalPost {
  final String id;
  final String text;

  const _LocalPost({required this.id, required this.text});

  factory _LocalPost.fromJson(Map<String, dynamic> json) =>
      _LocalPost(id: json['id'] as String, text: json['text'] as String);

  Map<String, String> toJson() => {'id': id, 'text': text};
}
