import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';

class AdminSourcesScreen extends ConsumerWidget {
  const AdminSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Sources'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: client.adminGetSources(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sources = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(apiClientProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              itemCount: sources.length,
              itemBuilder: (context, i) {
                final s = sources[i];
                final id = s['id'] as String? ?? '';
                final name = s['name'] as String? ?? 'Unnamed';
                final mode = s['mode'] as String? ?? '';
                final isEnabled = s['isEnabled'] as bool? ?? false;
                return Card(
                  margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text('$mode • ${isEnabled ? "Enabled" : "Disabled"}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _runNow(context, ref, id),
                          child: const Text('Run now'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateSource(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _runNow(BuildContext context, WidgetRef ref, String sourceId) async {
    final client = ref.read(apiClientProvider);
    try {
      await client.adminTriggerRun(sourceId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Run triggered')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showCreateSource(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _CreateSourceDialog(
        onCreated: () {
          ref.invalidate(apiClientProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Source created')));
          }
        },
        onCreate: (body) => ref.read(apiClientProvider).adminCreateSource(body),
      ),
    );
  }
}

const List<String> _sourceModes = ['feed', 'api', 'crawl', 'manual'];

class _CreateSourceDialog extends StatefulWidget {
  const _CreateSourceDialog({
    required this.onCreated,
    required this.onCreate,
  });

  final VoidCallback onCreated;
  final Future<String> Function(Map<String, dynamic> body) onCreate;

  @override
  State<_CreateSourceDialog> createState() => _CreateSourceDialogState();
}

class _CreateSourceDialogState extends State<_CreateSourceDialog> {
  final _nameController = TextEditingController();
  String _mode = 'manual';
  final _baseUrlController = TextEditingController();
  bool _isEnabled = true;
  final _rateLimitController = TextEditingController(text: '1');
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _rateLimitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _loading = true);
    try {
      final rateLimit = int.tryParse(_rateLimitController.text.trim()) ?? 1;
      await widget.onCreate({
        'name': name,
        'mode': _mode,
        'baseUrl': _baseUrlController.text.trim(),
        'isEnabled': _isEnabled,
        'rateLimitRps': rateLimit.clamp(1, 100),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New source'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Sample feed',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            DropdownButtonFormField<String>(
              value: _mode,
              decoration: const InputDecoration(labelText: 'Mode'),
              items: _sourceModes.map((m) => DropdownMenuItem<String>(value: m, child: Text(m))).toList(),
              onChanged: (v) => setState(() => _mode = v ?? 'manual'),
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://...',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            TextField(
              controller: _rateLimitController,
              decoration: const InputDecoration(
                labelText: 'Rate limit (req/s)',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            SwitchListTile(
              title: const Text('Enabled'),
              value: _isEnabled,
              onChanged: (v) => setState(() => _isEnabled = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create'),
        ),
      ],
    );
  }
}
