import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../services/github_deep_service.dart';
import '../services/github_repo_hub_service.dart';

const _bg = Color(0xFFF7FAFF);
const _panel = Color(0xFFFFFFFF);
const _line = Color(0xFFDDE7F7);
const _text = Color(0xFF0B1020);
const _muted = Color(0xFF536079);
const _faint = Color(0xFF8B97AD);
const _blue = Color(0xFF2555FF);
const _mint = Color(0xFF0B9B7E);
const _violet = Color(0xFF7557E8);
const _rose = Color(0xFFE0526E);

class DownloadsSharedFoldersScreen extends StatefulWidget {
  const DownloadsSharedFoldersScreen({super.key});

  @override
  State<DownloadsSharedFoldersScreen> createState() => _DownloadsSharedFoldersScreenState();
}

class _DownloadsSharedFoldersScreenState extends State<DownloadsSharedFoldersScreen> {
  late final GitHubRepoHubService _hub;
  late Future<_DownloadsSharedFoldersData> _data;

  @override
  void initState() {
    super.initState();
    _hub = GitHubRepoHubService(GitHubDeepService());
    _data = _load();
  }

  Future<_DownloadsSharedFoldersData> _load() async {
    final downloads = await _hub.loadArtifactDownloads();
    final sharedFolders = await _hub.loadRuntimeWorkspaceSyncs();
    return _DownloadsSharedFoldersData(
      downloads: downloads,
      sharedFolders: sharedFolders,
    );
  }

  void _refresh() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _toast('$label copied.');
  }

  Future<void> _openPath(String path, String label) async {
    final opened = await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (opened) {
      _toast('Opened $label.');
    } else {
      await Clipboard.setData(ClipboardData(text: path));
      _toast('Could not open $label directly. Path copied.', isError: true);
    }
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _rose : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('Downloads / Shared folders'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.archive_outlined), text: 'Downloads'),
              Tab(icon: Icon(Icons.folder_shared_outlined), text: 'Shared folders'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_outlined),
            ),
          ],
        ),
        body: FutureBuilder<_DownloadsSharedFoldersData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: _LibraryPanel(
                  borderColor: _rose,
                  child: Text(_compact(snapshot.error.toString(), 180), style: const TextStyle(color: _rose, height: 1.35)),
                ),
              );
            }
            final data = snapshot.requireData;
            return TabBarView(
              children: [
                _DownloadsTab(
                  records: data.downloads,
                  onOpen: (record) => unawaited(_openPath(record.path, 'artifact')),
                  onOpenFolder: (record) => unawaited(_openPath(p.dirname(record.path), 'artifact folder')),
                  onCopy: (record) => unawaited(_copy(record.path, 'Artifact path')),
                ),
                _SharedFoldersTab(
                  records: data.sharedFolders,
                  onOpen: (record) => unawaited(_openPath(record.sharedPath, 'shared folder')),
                  onCopyShared: (record) => unawaited(_copy(record.sharedPath, 'Shared folder path')),
                  onCopyRuntime: (record) => unawaited(_copy(record.runtimePath, 'Runtime path')),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DownloadsSharedFoldersData {
  const _DownloadsSharedFoldersData({
    required this.downloads,
    required this.sharedFolders,
  });

  final List<GitHubArtifactDownloadRecord> downloads;
  final List<GitHubRuntimeWorkspaceSyncRecord> sharedFolders;
}

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab({
    required this.records,
    required this.onOpen,
    required this.onOpenFolder,
    required this.onCopy,
  });

  final List<GitHubArtifactDownloadRecord> records;
  final ValueChanged<GitHubArtifactDownloadRecord> onOpen;
  final ValueChanged<GitHubArtifactDownloadRecord> onOpenFolder;
  final ValueChanged<GitHubArtifactDownloadRecord> onCopy;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const _EmptyLibraryState(
        icon: Icons.archive_outlined,
        title: 'No downloads yet',
        detail: 'GitHub Actions artifacts downloaded from Repo Hub will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final record = records[index];
        return _LibraryPanel(
          child: _DownloadRecordTile(
            record: record,
            onOpen: () => onOpen(record),
            onOpenFolder: () => onOpenFolder(record),
            onCopy: () => onCopy(record),
          ),
        );
      },
    );
  }
}

class _SharedFoldersTab extends StatelessWidget {
  const _SharedFoldersTab({
    required this.records,
    required this.onOpen,
    required this.onCopyShared,
    required this.onCopyRuntime,
  });

  final List<GitHubRuntimeWorkspaceSyncRecord> records;
  final ValueChanged<GitHubRuntimeWorkspaceSyncRecord> onOpen;
  final ValueChanged<GitHubRuntimeWorkspaceSyncRecord> onCopyShared;
  final ValueChanged<GitHubRuntimeWorkspaceSyncRecord> onCopyRuntime;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const _EmptyLibraryState(
        icon: Icons.folder_shared_outlined,
        title: 'No shared folders yet',
        detail: 'Use Repo Hub -> Runtime 文件 -> 同步到共享目录 to create phone-file-manager friendly copies.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final record = records[index];
        return _LibraryPanel(
          child: _SharedFolderRecordTile(
            record: record,
            onOpen: () => onOpen(record),
            onCopyShared: () => onCopyShared(record),
            onCopyRuntime: () => onCopyRuntime(record),
          ),
        );
      },
    );
  }
}

class _DownloadRecordTile extends StatelessWidget {
  const _DownloadRecordTile({
    required this.record,
    required this.onOpen,
    required this.onOpenFolder,
    required this.onCopy,
  });

  final GitHubArtifactDownloadRecord record;
  final VoidCallback onOpen;
  final VoidCallback onOpenFolder;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _RecordIcon(icon: Icons.archive_outlined, color: _violet),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(record.artifactName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(record.repoFullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '${_timeAgo(record.downloadedAt)} · ${record.sizeBytes == null ? _compact(record.path, 80) : '${_bytesLabel(record.sizeBytes!)} · ${_compact(record.path, 70)}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _faint, fontSize: 11, height: 1.25),
              ),
            ],
          ),
        ),
        _PathActions(onOpen: onOpen, onOpenFolder: onOpenFolder, onCopy: onCopy),
      ],
    );
  }
}

class _SharedFolderRecordTile extends StatelessWidget {
  const _SharedFolderRecordTile({
    required this.record,
    required this.onOpen,
    required this.onCopyShared,
    required this.onCopyRuntime,
  });

  final GitHubRuntimeWorkspaceSyncRecord record;
  final VoidCallback onOpen;
  final VoidCallback onCopyShared;
  final VoidCallback onCopyRuntime;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _RecordIcon(icon: Icons.folder_shared_outlined, color: _mint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.repoFullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('${_timeAgo(record.syncedAt)} · shared copy', style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            _PathActions(onOpen: onOpen, onOpenFolder: onOpen, onCopy: onCopyShared),
          ],
        ),
        const SizedBox(height: 10),
        _PathLine(label: 'Shared', value: record.sharedPath, color: _mint),
        const SizedBox(height: 6),
        _PathLine(label: 'Runtime', value: record.runtimePath, color: _blue, onCopy: onCopyRuntime),
      ],
    );
  }
}

class _PathActions extends StatelessWidget {
  const _PathActions({
    required this.onOpen,
    required this.onOpenFolder,
    required this.onCopy,
  });

  final VoidCallback onOpen;
  final VoidCallback onOpenFolder;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      children: [
        IconButton(tooltip: 'Open', visualDensity: VisualDensity.compact, onPressed: onOpen, icon: const Icon(Icons.open_in_new_outlined, color: _blue, size: 19)),
        IconButton(tooltip: 'Open folder', visualDensity: VisualDensity.compact, onPressed: onOpenFolder, icon: const Icon(Icons.folder_open_outlined, color: _mint, size: 19)),
        IconButton(tooltip: 'Copy path', visualDensity: VisualDensity.compact, onPressed: onCopy, icon: const Icon(Icons.copy_outlined, color: _faint, size: 19)),
      ],
    );
  }
}

class _PathLine extends StatelessWidget {
  const _PathLine({
    required this.label,
    required this.value,
    required this.color,
    this.onCopy,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11))),
          if (onCopy != null)
            IconButton(tooltip: 'Copy runtime path', visualDensity: VisualDensity.compact, onPressed: onCopy, icon: const Icon(Icons.copy_outlined, size: 16)),
        ],
      ),
    );
  }
}

class _RecordIcon extends StatelessWidget {
  const _RecordIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}

class _EmptyLibraryState extends StatelessWidget {
  const _EmptyLibraryState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: _LibraryPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _faint, size: 38),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 6),
              Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryPanel extends StatelessWidget {
  const _LibraryPanel({
    required this.child,
    this.borderColor = _line,
  });

  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A2555FF),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

String _timeAgo(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inDays >= 1) return '${diff.inDays}d ago';
  if (diff.inHours >= 1) return '${diff.inHours}h ago';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
  return 'just now';
}

String _bytesLabel(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _compact(String value, int limit) {
  final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= limit) return singleLine;
  return '${singleLine.substring(0, limit - 1)}…';
}
