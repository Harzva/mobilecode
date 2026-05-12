// lib/screens/ssh_hosts_screen.dart
// SSH Hosts Screen — Manage remote development servers.
//
// Features: list saved hosts, add/edit/delete hosts, quick connect,
// connection status indicator, favorite management, and host search.

import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/ssh_provider.dart';
import '../services/ssh_service.dart';
import 'ssh_terminal_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SSH Hosts Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Screen for managing SSH remote hosts.
///
/// Displays a scrollable list of saved host configurations with
/// connection status indicators, quick-connect buttons, favorite
/// management, and a bottom sheet form for adding/editing hosts.
class SshHostsScreen extends ConsumerStatefulWidget {
  const SshHostsScreen({super.key});

  @override
  ConsumerState<SshHostsScreen> createState() => _SshHostsScreenState();
}

class _SshHostsScreenState extends ConsumerState<SshHostsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SshHostConfig> _filterHosts(List<SshHostConfig> hosts) {
    if (_searchQuery.isEmpty) return hosts;

    final query = _searchQuery.toLowerCase();
    return hosts.where((h) {
      return h.name.toLowerCase().contains(query) ||
          h.host.toLowerCase().contains(query) ||
          h.username.toLowerCase().contains(query) ||
          (h.tag?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(sshHostsProvider);
    final connectionStates = ref.watch(sshConnectionStatesProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: hostsAsync.when(
        data: (hosts) {
          final filtered = _filterHosts(hosts);
          final favorites = filtered.where((h) => h.isFavorite).toList();
          final others = filtered.where((h) => !h.isFavorite).toList();

          if (hosts.isEmpty) {
            return const _EmptyHostsState();
          }

          return RefreshIndicator(
            color: AppTheme.accent,
            backgroundColor: AppTheme.surface,
            onRefresh: () async {
              ref.invalidate(sshHostsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Search bar.
                if (hosts.length > 3) _buildSearchBar(),

                // Favorites section.
                if (favorites.isNotEmpty) ...[
                  _buildSectionHeader('Favorites', Icons.star),
                  ...favorites.map((host) => _HostCard(
                        host: host,
                        isConnected:
                            connectionStates[host.id] == SshConnectionStatus.connected,
                        isConnecting:
                            connectionStates[host.id] == SshConnectionStatus.connecting,
                      )),
                  const SizedBox(height: 8),
                ],

                // Other hosts section.
                if (others.isNotEmpty) ...[
                  _buildSectionHeader('All Hosts', Icons.storage),
                  ...others.map((host) => _HostCard(
                        host: host,
                        isConnected:
                            connectionStates[host.id] == SshConnectionStatus.connected,
                        isConnecting:
                            connectionStates[host.id] == SshConnectionStatus.connecting,
                      )),
                ],

                // Bottom padding for FAB.
                const SizedBox(height: 80),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
        error: (error, _) => _ErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(sshHostsProvider),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showHostForm(context),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: AppTheme.textOnPrimary),
        label: const Text(
          'Add Host',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            color: AppTheme.textOnPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.backgroundElevated,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud, size: 20, color: AppTheme.accent),
          SizedBox(width: 10),
          Text(
            'Remote Hosts',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () {
            // Show help/info dialog.
            _showInfoDialog(context);
          },
          icon: const Icon(Icons.help_outline,
              color: AppTheme.textSecondary, size: 20),
          tooltip: 'About SSH',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 14,
          color: AppTheme.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search hosts...',
          hintStyle: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: AppTheme.textTertiary,
          ),
          prefixIcon:
              const Icon(Icons.search, color: AppTheme.textTertiary, size: 18),
          filled: true,
          fillColor: AppTheme.surfaceInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.primary),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.textTertiary),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showHostForm(BuildContext context, {SshHostConfig? existingHost}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _HostFormSheet(existingHost: existingHost),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.accent, size: 20),
            SizedBox(width: 8),
            Text(
              'SSH Remote Hosts',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        content: const Text(
          'Connect to remote servers via SSH to execute commands, '
          'transfer files, and use remote development environments.\n\n'
          'Authentication methods:\n'
          '  - Password authentication\n'
          '  - Private key (RSA/ED25519)\n\n'
          'All credentials are encrypted at rest.',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 13,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Got it',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                color: AppTheme.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Host Card
// ═══════════════════════════════════════════════════════════════════════════

/// Card widget displaying a single SSH host with actions.
class _HostCard extends ConsumerWidget {
  final SshHostConfig host;
  final bool isConnected;
  final bool isConnecting;

  const _HostCard({
    required this.host,
    this.isConnected = false,
    this.isConnecting = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isConnected ? AppTheme.accent.withOpacity(0.4) : AppTheme.border,
          width: isConnected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: isConnected
            ? () => _openTerminal(context)
            : () => _connect(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Status dot.
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected
                          ? AppTheme.success
                          : isConnecting
                              ? AppTheme.warning
                              : AppTheme.error,
                      boxShadow: isConnected
                          ? [
                              BoxShadow(
                                color: AppTheme.success.withOpacity(0.4),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Host name.
                  Expanded(
                    child: Text(
                      host.name,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Favorite button.
                  IconButton(
                    onPressed: () => _toggleFavorite(ref),
                    icon: Icon(
                      host.isFavorite ? Icons.star : Icons.star_border,
                      size: 18,
                      color: host.isFavorite
                          ? AppTheme.warning
                          : AppTheme.textTertiary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: host.isFavorite ? 'Unfavorite' : 'Favorite',
                  ),

                  // More options.
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        color: AppTheme.textTertiary, size: 18),
                    color: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    onSelected: (value) => _handleMenuAction(value, context, ref),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 16, color: AppTheme.textSecondary),
                            SizedBox(width: 8),
                            Text('Edit',
                                style: TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    color: AppTheme.textPrimary)),
                          ],
                        ),
                      ),
                      if (isConnected)
                        const PopupMenuItem(
                          value: 'disconnect',
                          child: Row(
                            children: [
                              Icon(Icons.link_off,
                                  size: 16, color: AppTheme.error),
                              SizedBox(width: 8),
                              Text('Disconnect',
                                  style: TextStyle(
                                      fontFamily: AppTheme.fontBody,
                                      color: AppTheme.error)),
                            ],
                          ),
                        )
                      else
                        const PopupMenuItem(
                          value: 'connect',
                          child: Row(
                            children: [
                              Icon(Icons.link,
                                  size: 16, color: AppTheme.accent),
                              SizedBox(width: 8),
                              Text('Connect',
                                  style: TextStyle(
                                      fontFamily: AppTheme.fontBody,
                                      color: AppTheme.textPrimary)),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                size: 16, color: AppTheme.error),
                            SizedBox(width: 8),
                            Text('Delete',
                                style: TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    color: AppTheme.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Address row.
              Row(
                children: [
                  Icon(
                    Icons.terminal,
                    size: 13,
                    color: isConnected ? AppTheme.accent : AppTheme.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    host.displayAddress,
                    style: TextStyle(
                      fontFamily: AppTheme.fontCode,
                      fontSize: 12,
                      color: isConnected ? AppTheme.accent : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (host.usesKeyAuth)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'KEY',
                        style: TextStyle(
                          fontFamily: AppTheme.fontCode,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accentMuted,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PASS',
                        style: TextStyle(
                          fontFamily: AppTheme.fontCode,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  const Spacer(),

                  // Connect / Terminal button.
                  if (!isConnected && !isConnecting)
                    _ActionButton(
                      label: 'Connect',
                      icon: Icons.link,
                      onTap: () => _connect(context, ref),
                    )
                  else if (isConnecting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.warning,
                      ),
                    )
                  else
                    _ActionButton(
                      label: 'Terminal',
                      icon: Icons.terminal,
                      onTap: () => _openTerminal(context),
                    ),
                ],
              ),

              // Last connected / tag row.
              if (host.lastConnectedAt != null || host.tag != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      if (host.tag != null)
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceHover,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Text(
                            host.tag!,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 10,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (host.lastConnectedAt != null)
                        Text(
                          'Last: ${_formatTimeAgo(host.lastConnectedAt!)}',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 10,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _connect(BuildContext context, WidgetRef ref) {
    ref.read(sshProvider.notifier).connect(host);
  }

  void _openTerminal(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SshTerminalScreen(hostConfig: host),
      ),
    );
  }

  void _toggleFavorite(WidgetRef ref) {
    final updated = host.copyWith(isFavorite: !host.isFavorite);
    ref.read(sshProvider.notifier).saveHost(updated);
  }

  void _handleMenuAction(String action, BuildContext context, WidgetRef ref) {
    switch (action) {
      case 'connect':
        _connect(context, ref);
        break;
      case 'disconnect':
        ref.read(sshProvider.notifier).disconnect(host.id);
        break;
      case 'edit':
        // Show edit form via parent.
        final parentState =
            context.findAncestorStateOfType<_SshHostsScreenState>();
        parentState?._showHostForm(context, existingHost: host);
        break;
      case 'delete':
        _showDeleteConfirm(context, ref);
        break;
    }
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Delete Host?',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Delete "${host.name}" (${host.displayAddress})?\n'
          'This cannot be undone.',
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(fontFamily: AppTheme.fontBody)),
          ),
          TextButton(
            onPressed: () {
              ref.read(sshProvider.notifier).deleteHost(host.id);
              Navigator.pop(context);
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Action Button
// ═══════════════════════════════════════════════════════════════════════════

/// Small action button used within host cards.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.primaryMuted,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: AppTheme.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Empty State
// ═══════════════════════════════════════════════════════════════════════════

/// Shown when no hosts have been configured.
class _EmptyHostsState extends StatelessWidget {
  const _EmptyHostsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off,
            size: 56,
            color: AppTheme.textDisabled.withOpacity(0.5),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Remote Hosts',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Add SSH hosts to connect to remote servers, execute commands, and transfer files.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textDisabled,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Quick hints.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _HintChip(label: 'VPS Server'),
              _HintChip(label: 'Cloud Instance'),
              _HintChip(label: 'Home Server'),
              _HintChip(label: 'Dev Container'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hint chip for empty state.
class _HintChip extends StatelessWidget {
  final String label;
  const _HintChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 11,
          color: AppTheme.textTertiary,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Error State
// ═══════════════════════════════════════════════════════════════════════════

/// Error display widget with retry action.
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 16),
          Text(
            'Failed to Load Hosts',
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Host Form Sheet (Add / Edit)
// ═══════════════════════════════════════════════════════════════════════════

/// Bottom sheet form for adding or editing SSH host configurations.
class _HostFormSheet extends ConsumerStatefulWidget {
  final SshHostConfig? existingHost;

  const _HostFormSheet({this.existingHost});

  @override
  ConsumerState<_HostFormSheet> createState() => _HostFormSheetState();
}

class _HostFormSheetState extends ConsumerState<_HostFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _workingDirController = TextEditingController();
  final _tagController = TextEditingController();

  bool _useKeyAuth = false;
  bool _obscurePassword = true;
  String? _privateKeyContent;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingHost != null) {
      final h = widget.existingHost!;
      _nameController.text = h.name;
      _hostController.text = h.host;
      _portController.text = h.port.toString();
      _usernameController.text = h.username;
      _passwordController.text = h.password ?? '';
      _passphraseController.text = h.passphrase ?? '';
      _workingDirController.text = h.workingDirectory ?? '';
      _tagController.text = h.tag ?? '';
      _useKeyAuth = h.usesKeyAuth;
      _privateKeyContent = h.privateKey;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passphraseController.dispose();
    _workingDirController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingHost != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar.
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      isEditing ? 'Edit Host' : 'Add SSH Host',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close,
                          color: AppTheme.textSecondary, size: 20),
                    ),
                  ],
                ),
              ),

              const Divider(color: AppTheme.border, height: 1),

              // Form.
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Name.
                      _buildTextField(
                        controller: _nameController,
                        label: 'Display Name',
                        hint: 'My VPS Server',
                        icon: Icons.label_outline,
                        validator: (v) =>
                            v?.isEmpty == true ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Host.
                      _buildTextField(
                        controller: _hostController,
                        label: 'Host',
                        hint: '192.168.1.100 or example.com',
                        icon: Icons.dns,
                        validator: (v) =>
                            v?.isEmpty == true ? 'Host is required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Port + Username row.
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: _buildTextField(
                              controller: _portController,
                              label: 'Port',
                              hint: '22',
                              icon: Icons.settings_ethernet,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: _buildTextField(
                              controller: _usernameController,
                              label: 'Username',
                              hint: 'root',
                              icon: Icons.person_outline,
                              validator: (v) => v?.isEmpty == true
                                  ? 'Username is required'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Auth method toggle.
                      _buildAuthToggle(),
                      const SizedBox(height: 16),

                      // Auth fields.
                      if (_useKeyAuth) ...[
                        // Private key.
                        _buildPrivateKeyField(),
                        const SizedBox(height: 12),

                        // Passphrase.
                        _buildTextField(
                          controller: _passphraseController,
                          label: 'Key Passphrase (optional)',
                          hint: 'Passphrase for encrypted key',
                          icon: Icons.vpn_key,
                          obscureText: true,
                        ),
                      ] else ...[
                        // Password.
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hint: 'SSH password',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          suffix: IconButton(
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 18,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Working directory.
                      _buildTextField(
                        controller: _workingDirController,
                        label: 'Working Directory (optional)',
                        hint: '/home/username/projects',
                        icon: Icons.folder_open,
                      ),
                      const SizedBox(height: 16),

                      // Tag.
                      _buildTextField(
                        controller: _tagController,
                        label: 'Tag (optional)',
                        hint: 'production, staging, home...',
                        icon: Icons.local_offer_outlined,
                      ),

                      const SizedBox(height: 32),

                      // Save button.
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: AppTheme.textOnPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.textOnPrimary,
                                  ),
                                )
                              : Text(
                                  isEditing ? 'Save Changes' : 'Add Host',
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(
        fontFamily: AppTheme.fontBody,
        fontSize: 14,
        color: AppTheme.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null
            ? Icon(icon, size: 18, color: AppTheme.textTertiary)
            : null,
        suffixIcon: suffix,
        filled: true,
        fillColor: AppTheme.surfaceInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        labelStyle: const TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 13,
          color: AppTheme.textSecondary,
        ),
        hintStyle: const TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 13,
          color: AppTheme.textDisabled,
        ),
      ),
    );
  }

  Widget _buildAuthToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _useKeyAuth = false),
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(10)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_useKeyAuth ? AppTheme.primaryMuted : null,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 16,
                        color: !_useKeyAuth ? AppTheme.primary : AppTheme.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      'Password',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        fontWeight: !_useKeyAuth ? FontWeight.w600 : FontWeight.normal,
                        color: !_useKeyAuth ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 24, color: AppTheme.border),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _useKeyAuth = true),
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(10)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _useKeyAuth ? AppTheme.primaryMuted : null,
                  borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.vpn_key,
                        size: 16,
                        color: _useKeyAuth ? AppTheme.primary : AppTheme.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      'Private Key',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        fontWeight: _useKeyAuth ? FontWeight.w600 : FontWeight.normal,
                        color: _useKeyAuth ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivateKeyField() {
    final hasKey = _privateKeyContent != null && _privateKeyContent!.isNotEmpty;

    return InkWell(
      onTap: _pickPrivateKey,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceInput,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasKey ? AppTheme.success.withOpacity(0.4) : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasKey ? Icons.check_circle : Icons.upload_file,
              size: 20,
              color: hasKey ? AppTheme.success : AppTheme.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasKey ? 'Private Key Loaded' : 'Tap to Load Private Key',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: hasKey ? AppTheme.success : AppTheme.textSecondary,
                    ),
                  ),
                  if (hasKey)
                    Text(
                      '${_privateKeyContent!.length} chars',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (hasKey)
              IconButton(
                onPressed: () => setState(() => _privateKeyContent = null),
                icon: const Icon(Icons.close, size: 16, color: AppTheme.error),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPrivateKey() async {
    // In production, this would use file_picker.
    // For now, show a dialog to paste the key.
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _PrivateKeyPasteDialog(),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _privateKeyContent = result);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_useKeyAuth && (_privateKeyContent == null || _privateKeyContent!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please load a private key'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final config = SshHostConfig(
        id: widget.existingHost?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text) ?? 22,
        username: _usernameController.text.trim(),
        password: _useKeyAuth ? null : _passwordController.text,
        privateKey: _useKeyAuth ? _privateKeyContent : null,
        passphrase: _useKeyAuth ? _passphraseController.text : null,
        workingDirectory: _workingDirController.text.trim().isEmpty
            ? null
            : _workingDirController.text.trim(),
        isFavorite: widget.existingHost?.isFavorite ?? false,
        tag: _tagController.text.trim().isEmpty
            ? null
            : _tagController.text.trim(),
      );

      await ref.read(sshProvider.notifier).saveHost(config);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingHost != null
                  ? 'Host "${config.name}" updated'
                  : 'Host "${config.name}" added',
              style: const TextStyle(fontFamily: AppTheme.fontBody),
            ),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Private Key Paste Dialog
// ═══════════════════════════════════════════════════════════════════════════

/// Dialog for pasting a private key.
class _PrivateKeyPasteDialog extends StatefulWidget {
  @override
  State<_PrivateKeyPasteDialog> createState() => _PrivateKeyPasteDialogState();
}

class _PrivateKeyPasteDialogState extends State<_PrivateKeyPasteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Row(
        children: [
          Icon(Icons.vpn_key, color: AppTheme.accent, size: 20),
          SizedBox(width: 8),
          Text(
            'Paste Private Key',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _controller,
          maxLines: 8,
          style: const TextStyle(
            fontFamily: AppTheme.fontCode,
            fontSize: 11,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
            hintStyle: const TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 11,
              color: AppTheme.textDisabled,
            ),
            filled: true,
            fillColor: AppTheme.surfaceInput,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(fontFamily: AppTheme.fontBody)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text(
            'Confirm',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              color: AppTheme.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
