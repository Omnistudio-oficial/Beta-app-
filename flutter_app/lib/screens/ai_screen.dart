import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AIScreen extends StatefulWidget {
  const AIScreen({super.key});

  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _selectedPrompt;
  String? _readyPrompt;

  static const _templates = <_PromptTemplate>[
    _PromptTemplate(
      title: 'Resumir un texto',
      icon: Icons.summarize_outlined,
      prompt: 'Resume el siguiente texto en puntos claros y breves:\n\n[Pega aquí el texto]',
    ),
    _PromptTemplate(
      title: 'Crear notas de producto',
      icon: Icons.note_alt_outlined,
      prompt: 'Crea notas de producto claras a partir de esta información:\n\n[Describe el producto y sus características]',
    ),
    _PromptTemplate(
      title: 'Redactar texto de bienvenida',
      icon: Icons.edit_note_outlined,
      prompt: 'Redacta un texto de bienvenida amigable para:\n\n[Describe la aplicación, el público y el tono]',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectTemplate(_PromptTemplate template) {
    setState(() {
      _selectedPrompt = template.title;
      _readyPrompt = null;
      _controller.text = template.prompt;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  Future<void> _copyPrompt() async {
    final prompt = _readyPrompt;
    if (prompt == null) return;
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prompt copiado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Compositor de prompts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Elige una plantilla y edítala. Esta pantalla prepara el texto; todavía no genera respuestas con IA.'),
            const SizedBox(height: 18),
            const Text('Plantillas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final template in _templates)
              Card(
                child: ListTile(
                  leading: Icon(template.icon, color: Colors.deepPurple),
                  title: Text(template.title),
                  trailing: Icon(_selectedPrompt == template.title ? Icons.check_circle : Icons.arrow_forward_ios),
                  onTap: () => _selectTemplate(template),
                ),
              ),
            if (_selectedPrompt != null) ...[
              const SizedBox(height: 12),
              Text('Editar prompt: $_selectedPrompt', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                key: const Key('prompt-editor'),
                controller: _controller,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() => _readyPrompt = null),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('prepare-prompt'),
                  onPressed: _controller.text.trim().isEmpty
                      ? null
                      : () => setState(() => _readyPrompt = _controller.text.trim()),
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Preparar prompt'),
                ),
              ),
            ],
            if (_readyPrompt != null) ...[
              const SizedBox(height: 18),
              Card(
                key: const Key('prepared-prompt'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Texto listo para usar', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SelectableText(_readyPrompt!),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _copyPrompt,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copiar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromptTemplate {
  final String title;
  final IconData icon;
  final String prompt;

  const _PromptTemplate({required this.title, required this.icon, required this.prompt});
}
