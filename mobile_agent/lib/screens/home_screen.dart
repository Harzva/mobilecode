import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _HealthState { unknown, checking, healthy, failed }

class _ProbeResult {
  const _ProbeResult({
    required this.uri,
    required this.statusCode,
    required this.latencyMs,
    required this.message,
  });

  final Uri uri;
  final int? statusCode;
  final int latencyMs;
  final String message;

  bool get isHealthy => statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

/// MobileCode home screen.
///
/// The first screen must be useful on a phone: configure the API endpoint,
/// verify service health, and then open the core mobile coding actions.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _baseUrlKey = 'mobilecode.baseUrl';
  static const _apiKeyKey = 'mobilecode.apiKey';
  static const _modelKey = 'mobilecode.model';

  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController(text: 'gpt-4o-mini');

  _HealthState _healthState = _HealthState.unknown;
  String _healthMessage = 'Not checked';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _baseUrlController.text = prefs.getString(_baseUrlKey) ?? '';
      _apiKeyController.text = prefs.getString(_apiKeyKey) ?? '';
      _modelController.text = prefs.getString(_modelKey) ?? 'gpt-4o-mini';
    });
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, _baseUrlController.text.trim());
    await prefs.setString(_apiKeyKey, _apiKeyController.text.trim());
    await prefs.setString(_modelKey, _modelController.text.trim());
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API config saved')),
    );
  }

  Future<void> _checkHealth() async {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty) {
      _showMessage('Set Base URL first');
      return;
    }

    List<Uri> probes;
    try {
      probes = _healthUris(baseUrl);
    } catch (_) {
      _showMessage('Base URL is not valid');
      return;
    }

    setState(() {
      _healthState = _HealthState.checking;
      _healthMessage = 'Checking ${probes.first}';
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final apiKey = _apiKeyController.text.trim();
      _ProbeResult? lastResult;

      for (final probe in probes) {
        final result = await _probe(client, probe, apiKey);
        lastResult = result;
        if (result.isHealthy) break;
      }

      if (!mounted) return;
      setState(() {
        _healthState = lastResult?.isHealthy ?? false
            ? _HealthState.healthy
            : _HealthState.failed;
        _healthMessage = lastResult?.message ?? 'No health response';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _healthState = _HealthState.failed;
        _healthMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<_ProbeResult> _probe(HttpClient client, Uri uri, String apiKey) async {
    final started = DateTime.now();
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
    if (apiKey.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }
    final response = await request.close().timeout(const Duration(seconds: 12));
    await response.drain();
    final ms = DateTime.now().difference(started).inMilliseconds;
    return _ProbeResult(
      uri: uri,
      statusCode: response.statusCode,
      latencyMs: ms,
      message: '${uri.path} HTTP ${response.statusCode} - ${ms}ms',
    );
  }

  List<Uri> _healthUris(String baseUrl) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse(normalized);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Invalid URL');
    }
    return [
      Uri.parse('$normalized/health'),
      Uri.parse('$normalized/models'),
    ];
  }

  bool get _hasConfig => _baseUrlController.text.trim().isNotEmpty;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openAction(_ActionKind kind) {
    if (kind == _ActionKind.chat && !_hasConfig) {
      _showMessage('Configure Base URL and API key before using AI Chat');
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ActionSheet(
        kind: kind,
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text('MobileCode', style: textTheme.displaySmall),
            const SizedBox(height: 8),
            Text('Code. Anywhere. With AI.', style: textTheme.bodyMedium),
            const SizedBox(height: 24),
            _ApiConfigCard(
              baseUrlController: _baseUrlController,
              apiKeyController: _apiKeyController,
              modelController: _modelController,
              saving: _saving,
              onSave: _saveConfig,
            ),
            const SizedBox(height: 16),
            _HealthCard(
              state: _healthState,
              message: _healthMessage,
              onCheck: _checkHealth,
            ),
            const SizedBox(height: 24),
            _QuickActionsGrid(onAction: _openAction),
            const SizedBox(height: 32),
            const _SectionTitle(title: 'Workspace'),
            const SizedBox(height: 16),
            const _WorkspaceSummary(),
            const SizedBox(height: 32),
            const _SectionTitle(title: 'Recent Snippets'),
            const SizedBox(height: 16),
            const _RecentSnippetsPlaceholder(),
          ],
        ),
      ),
    );
  }
}

class _ApiConfigCard extends StatelessWidget {
  const _ApiConfigCard({
    required this.baseUrlController,
    required this.apiKeyController,
    required this.modelController,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 10),
              Text('API Configuration', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: baseUrlController,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.example.com/v1',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: apiKeyController,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              prefixIcon: Icon(Icons.key),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: modelController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: 'gpt-4o-mini',
              prefixIcon: Icon(Icons.memory),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(saving ? 'Saving...' : 'Save API Config'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.state,
    required this.message,
    required this.onCheck,
  });

  final _HealthState state;
  final String message;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _HealthState.healthy => Colors.greenAccent,
      _HealthState.failed => Theme.of(context).colorScheme.error,
      _HealthState.checking => Theme.of(context).colorScheme.secondary,
      _HealthState.unknown => Theme.of(context).disabledColor,
    };
    final label = switch (state) {
      _HealthState.healthy => 'Healthy',
      _HealthState.failed => 'Unhealthy',
      _HealthState.checking => 'Checking',
      _HealthState.unknown => 'Unknown',
    };

    return _Panel(
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Health: $label', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: state == _HealthState.checking ? null : onCheck,
            icon: const Icon(Icons.monitor_heart_outlined),
            label: const Text('Check'),
          ),
        ],
      ),
    );
  }
}

enum _ActionKind { file, projects, chat, snippet }

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({required this.onAction});

  final ValueChanged<_ActionKind> onAction;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionItemData(Icons.code, 'New File', _ActionKind.file),
      _ActionItemData(Icons.folder_outlined, 'Projects', _ActionKind.projects),
      _ActionItemData(Icons.chat_bubble_outline, 'AI Chat', _ActionKind.chat),
      _ActionItemData(Icons.add_box_outlined, 'Snippet', _ActionKind.snippet),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        for (final action in actions)
          _ActionItem(
            icon: action.icon,
            label: action.label,
            onTap: () => onAction(action.kind),
          ),
      ],
    );
  }
}

class _ActionItemData {
  const _ActionItemData(this.icon, this.label, this.kind);

  final IconData icon;
  final String label;
  final _ActionKind kind;
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.kind,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final _ActionKind kind;
  final String baseUrl;
  final String apiKey;
  final String model;

  @override
  Widget build(BuildContext context) {
    final title = switch (kind) {
      _ActionKind.file => 'New File',
      _ActionKind.projects => 'Projects',
      _ActionKind.chat => 'AI Chat',
      _ActionKind.snippet => 'New Snippet',
    };
    final icon = switch (kind) {
      _ActionKind.file => Icons.code,
      _ActionKind.projects => Icons.folder_outlined,
      _ActionKind.chat => Icons.chat_bubble_outline,
      _ActionKind.snippet => Icons.add_box_outlined,
    };

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            if (kind == _ActionKind.file) const _NewFileForm(),
            if (kind == _ActionKind.projects) const _ProjectsPanel(),
            if (kind == _ActionKind.chat)
              _ChatPanel(baseUrl: baseUrl, apiKey: apiKey, model: model),
            if (kind == _ActionKind.snippet) const _SnippetForm(),
          ],
        ),
      ),
    );
  }
}

class _NewFileForm extends StatelessWidget {
  const _NewFileForm();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const TextField(
          decoration: InputDecoration(
            labelText: 'File name',
            hintText: 'lib/screens/example_screen.dart',
            prefixIcon: Icon(Icons.insert_drive_file_outlined),
          ),
        ),
        const SizedBox(height: 12),
        const TextField(
          minLines: 5,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: 'Initial code',
            hintText: 'Paste or draft code here...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File draft created locally')),
              );
            },
            child: const Text('Create draft'),
          ),
        ),
      ],
    );
  }
}

class _ProjectsPanel extends StatelessWidget {
  const _ProjectsPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Project actions are ready. Connect a workspace or GitHub repository next.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Project picker opened')),
            );
          },
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Open project picker'),
        ),
      ],
    );
  }
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _promptController = TextEditingController();

  bool _sending = false;
  String? _answer;
  String? _error;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showMessage('Enter a prompt first');
      return;
    }

    setState(() {
      _sending = true;
      _answer = null;
      _error = null;
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .postUrl(_chatUri(widget.baseUrl))
          .timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType.json;
      if (widget.apiKey.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${widget.apiKey}');
      }
      request.write(jsonEncode({
        'model': widget.model.isEmpty ? 'gpt-4o-mini' : widget.model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'stream': false,
      }));

      final response = await request.close().timeout(const Duration(seconds: 45));
      final body = await utf8.decodeStream(response);
      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _error = 'HTTP ${response.statusCode}: ${_compact(body)}';
        });
        return;
      }

      setState(() {
        _answer = _extractAssistantText(body);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      client.close(force: true);
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Uri _chatUri(String baseUrl) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse(normalized);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Invalid URL');
    }
    if (normalized.endsWith('/chat/completions')) {
      return uri;
    }
    return Uri.parse('$normalized/chat/completions');
  }

  String _extractAssistantText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map<String, dynamic>) {
            final message = first['message'];
            if (message is Map<String, dynamic>) {
              final content = message['content'];
              if (content is String && content.trim().isNotEmpty) {
                return content.trim();
              }
            }
            final text = first['text'];
            if (text is String && text.trim().isNotEmpty) {
              return text.trim();
            }
          }
        }
      }
    } catch (_) {
      // Fall through and show the raw body.
    }
    return _compact(body);
  }

  String _compact(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 800) return trimmed;
    return '${trimmed.substring(0, 800)}...';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _promptController,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: 'Prompt',
            hintText: 'Ask MobileCode to explain, edit, or generate code...',
            helperText:
                'Endpoint: ${widget.baseUrl}/chat/completions - Model: ${widget.model.isEmpty ? 'gpt-4o-mini' : widget.model}',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(_sending ? 'Sending...' : 'Send to AI'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
        if (_answer != null) ...[
          const SizedBox(height: 16),
          _Panel(
            child: SelectableText(
              _answer!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}

class _SnippetForm extends StatelessWidget {
  const _SnippetForm();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const TextField(
          decoration: InputDecoration(
            labelText: 'Snippet title',
            hintText: 'API client helper',
            prefixIcon: Icon(Icons.label_outline),
          ),
        ),
        const SizedBox(height: 12),
        const TextField(
          minLines: 5,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: 'Code snippet',
            hintText: 'Save reusable code here...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Snippet saved locally')),
              );
            },
            child: const Text('Save snippet'),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _WorkspaceSummary extends StatelessWidget {
  const _WorkspaceSummary();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Icon(Icons.folder_open_outlined, size: 42, color: Theme.of(context).disabledColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No project selected', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  'Use Projects to connect a repository or local workspace.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSnippetsPlaceholder extends StatelessWidget {
  const _RecentSnippetsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Icon(Icons.code_off_outlined, size: 42, color: Theme.of(context).disabledColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No snippets yet', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  'Tap Snippet to save reusable code.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }
}
