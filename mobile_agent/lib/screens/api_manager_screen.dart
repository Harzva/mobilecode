// lib/screens/api_manager_screen.dart
// API Manager Screen - CCSwitch-inspired card-based UI
// API管理界面 - 灵感来自CCSwitch

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../services/api_manager_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// API Manager Screen
// ═══════════════════════════════════════════════════════════════════════════

/// API Manager Screen
///
/// CCSwitch-inspired clean card-based UI for managing API providers:
///
/// - Section 1: Official Subscriptions (ChatGPT, Gemini)
///   - Card with provider icon, name, status (connected/disconnected)
///   - Connect/Disconnect button
///   - Account info (masked)
///
/// - Section 2: Custom APIs
///   - List of custom API cards
///   - Each card: name, baseUrl (masked), model, status dot
///   - Tap to edit, long-press to delete
///   - FAB to add new
///
/// - Section 3: Provider Priority
///   - Draggable list to reorder priority
///   - "Auto-select best" toggle
///
/// Design: Dark theme, glassmorphism cards, violet/cyan accents
class ApiManagerScreen extends StatefulWidget {
  final ApiManagerService apiManager;

  const ApiManagerScreen({super.key, required this.apiManager});

  @override
  State<ApiManagerScreen> createState() => _ApiManagerScreenState();
}

class _ApiManagerScreenState extends State<ApiManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _setLoading(bool v) => setState(() => _isLoading = v);

  // ── Build ───────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withOpacity(0.8),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'API 管理',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textTertiary,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: '官方订阅'),
            Tab(text: '自定义 API'),
            Tab(text: '优先级'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildOfficialTab(),
              _buildCustomApiTab(),
              _buildPriorityTab(),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 1: Official Subscriptions
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildOfficialTab() {
    return AnimatedBuilder(
      animation: widget.apiManager,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('官方 AI 服务', '直接使用官方订阅服务'),
              const SizedBox(height: 12),
              _buildOfficialCard(
                id: 'official_chatgpt',
                name: 'ChatGPT',
                subtitle: 'OpenAI',
                description: '使用 OpenAI 官方 ChatGPT API',
                isConnected: widget.apiManager.isChatGPTOfficialConnected,
                accountHint: widget.apiManager.chatGPTAccountHint,
                icon: Icons.chat_bubble_outline,
                iconColor: const Color(0xFF10A37F),
                bgGradient: const LinearGradient(
                  colors: [Color(0xFF10A37F), Color(0xFF0D7A5F)],
                ),
                onConnect: _showChatGPTConnectDialog,
                onDisconnect: () async {
                  _setLoading(true);
                  await widget.apiManager.disconnectChatGPTOfficial();
                  _setLoading(false);
                },
                onTest: () => _testConnection('official_chatgpt'),
              ),
              const SizedBox(height: 16),
              _buildOfficialCard(
                id: 'official_gemini',
                name: 'Gemini',
                subtitle: 'Google',
                description: '使用 Google Gemini API',
                isConnected: widget.apiManager.isGeminiOfficialConnected,
                accountHint: widget.apiManager.geminiAccountHint,
                icon: Icons.auto_awesome,
                iconColor: const Color(0xFF4285F4),
                bgGradient: const LinearGradient(
                  colors: [Color(0xFF4285F4), Color(0xFF1967D2)],
                ),
                onConnect: _showGeminiConnectDialog,
                onDisconnect: () async {
                  _setLoading(true);
                  await widget.apiManager.disconnectGeminiOfficial();
                  _setLoading(false);
                },
                onTest: () => _testConnection('official_gemini'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOfficialCard({
    required String id,
    required String name,
    required String subtitle,
    required String description,
    required bool isConnected,
    required String? accountHint,
    required IconData icon,
    required Color iconColor,
    required Gradient bgGradient,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
    required VoidCallback onTest,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.surfaceGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected ? iconColor.withOpacity(0.5) : AppTheme.border,
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Header with icon and status
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: bgGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 12,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? AppTheme.success.withOpacity(0.15)
                          : AppTheme.textDisabled.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isConnected ? AppTheme.success : AppTheme.textDisabled,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isConnected ? '已连接' : '未连接',
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isConnected ? AppTheme.success : AppTheme.textDisabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Divider
            Divider(height: 1, color: AppTheme.border.withOpacity(0.5)),

            // Info and actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (isConnected && accountHint != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 14, color: AppTheme.textTertiary),
                        const SizedBox(width: 6),
                        Text(
                          accountHint,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 12,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          label: isConnected ? '断开连接' : '连接',
                          icon: isConnected ? Icons.link_off : Icons.link,
                          color: isConnected ? AppTheme.error : AppTheme.primary,
                          onPressed: isConnected ? onDisconnect : onConnect,
                        ),
                      ),
                      if (isConnected) ...[
                        const SizedBox(width: 10),
                        _buildIconButton(
                          icon: Icons.network_check,
                          tooltip: '测试连接',
                          onPressed: onTest,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 2: Custom APIs
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildCustomApiTab() {
    return AnimatedBuilder(
      animation: widget.apiManager,
      builder: (context, _) {
        final customApis = widget.apiManager.getCustomApis();

        return Stack(
          children: [
            if (customApis.isEmpty)
              _buildEmptyState(
                icon: Icons.api_outlined,
                title: '暂无自定义 API',
                subtitle: '添加 OpenRouter、Together AI 或其他兼容 OpenAI 的 API',
              )
            else
              ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: customApis.length + 1, // +1 for header
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildSectionHeader('自定义 API', '兼容 OpenAI API 格式的第三方服务'),
                    );
                  }
                  final config = customApis[index - 1];
                  return _buildCustomApiCard(config);
                },
              ),

            // FAB
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: _showAddCustomApiDialog,
                backgroundColor: AppTheme.primary,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCustomApiCard(CustomApiConfig config) {
    final health = widget.apiManager.getCachedHealth(config.id);

    return Dismissible(
      key: Key(config.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: AppTheme.error),
      ),
      onDismissed: (_) async {
        await widget.apiManager.deleteCustomApi(config.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已删除 ${config.name}'),
              backgroundColor: AppTheme.surfaceHover,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: config.isActive ? AppTheme.borderActive.withOpacity(0.3) : AppTheme.border,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showEditCustomApiDialog(config),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: config.isActive ? AppTheme.success : AppTheme.textDisabled,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        config.name,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    // Active toggle
                    Switch.adaptive(
                      value: config.isActive,
                      onChanged: (_) => widget.apiManager.toggleCustomApiActive(config.id),
                      activeColor: AppTheme.primary,
                      inactiveTrackColor: AppTheme.textDisabled.withOpacity(0.3),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildInfoRow(Icons.link, config.displayUrl, AppTheme.accent),
                const SizedBox(height: 6),
                _buildInfoRow(Icons.key, config.maskedApiKey, AppTheme.warning),
                const SizedBox(height: 6),
                _buildInfoRow(Icons.model_training, config.model, AppTheme.info),
                if (health != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        health.isHealthy ? Icons.check_circle : Icons.error,
                        size: 14,
                        color: health.isHealthy ? AppTheme.success : AppTheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        health.isHealthy
                            ? '健康 · ${health.latencyMs}ms'
                            : '异常 · ${health.error ?? '未知错误'}',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 11,
                          color: health.isHealthy ? AppTheme.success : AppTheme.error,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _testConnection(config.id),
                        icon: const Icon(Icons.network_check, size: 14),
                        label: const Text('测试', style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 3: Provider Priority
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPriorityTab() {
    return AnimatedBuilder(
      animation: widget.apiManager,
      builder: (context, _) {
        final providers = widget.apiManager.availableProviders;
        final priority = widget.apiManager.providerPriority;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('提供商优先级', '拖动调整顺序，排在前面的优先使用'),
              const SizedBox(height: 16),

              // Auto-failover toggle
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '自动故障转移',
                            style: TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '主提供商失败时自动切换到备用',
                            style: TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 12,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: widget.apiManager.autoFailoverEnabled,
                      onChanged: (v) => widget.apiManager.setAutoFailover(v),
                      activeColor: AppTheme.primary,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (providers.isEmpty)
                _buildEmptyState(
                  icon: Icons.sort,
                  title: '没有可用的提供商',
                  subtitle: '先连接官方服务或添加自定义 API',
                )
              else
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  proxyDecorator: (child, index, animation) {
                    return Material(
                      color: Colors.transparent,
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final currentOrder = priority.isNotEmpty
                        ? priority.where((id) => providers.any((p) => p.id == id)).toList()
                        : providers.map((p) => p.id).toList();
                    if (oldIndex < currentOrder.length && newIndex <= currentOrder.length) {
                      final item = currentOrder.removeAt(oldIndex);
                      currentOrder.insert(newIndex, item);
                      widget.apiManager.setProviderPriority(currentOrder);
                    }
                  },
                  children: [
                    for (var i = 0; i < providers.length; i++)
                      _buildPriorityItem(
                        key: Key(providers[i].id),
                        rank: i + 1,
                        provider: providers[i],
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPriorityItem({
    required Key key,
    required int rank,
    required ApiProvider provider,
  }) {
    final typeLabel = provider.type == 'official_chatgpt'
        ? '官方'
        : provider.type == 'official_gemini'
            ? '官方'
            : '自定义';

    final typeColor = provider.type.startsWith('official')
        ? AppTheme.accent
        : AppTheme.info;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: rank == 1 ? AppTheme.surface.withOpacity(0.8) : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: rank == 1 ? AppTheme.primary.withOpacity(0.3) : AppTheme.border,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: rank == 1 ? AppTheme.primary.withOpacity(0.2) : AppTheme.surfaceHover,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              '$rank',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: rank == 1 ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
        title: Text(
          provider.name,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          '${provider.defaultModel} · ${provider.baseUrl}',
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 11,
            color: AppTheme.textTertiary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                typeLabel,
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 10,
                  color: typeColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.drag_handle, color: AppTheme.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Dialogs
  // ═══════════════════════════════════════════════════════════════════════

  void _showChatGPTConnectDialog() {
    final tokenController = TextEditingController();
    _showConnectDialog(
      title: '连接 ChatGPT',
      subtitle: '输入 OpenAI Session Token',
      icon: Icons.chat_bubble_outline,
      iconColor: const Color(0xFF10A37F),
      hintText: 'sess-xxxxxxxxxxxxxxxxxxxxxxxx',
      controller: tokenController,
      isPassword: true,
      onConnect: () async {
        final token = tokenController.text.trim();
        if (token.isEmpty) return false;
        _setLoading(true);
        final success = await widget.apiManager.connectChatGPTOfficial(sessionToken: token);
        _setLoading(false);
        return success;
      },
    );
  }

  void _showGeminiConnectDialog() {
    final keyController = TextEditingController();
    _showConnectDialog(
      title: '连接 Gemini',
      subtitle: '输入 Google AI Studio API Key',
      icon: Icons.auto_awesome,
      iconColor: const Color(0xFF4285F4),
      hintText: 'AIzaSyxxxxxxxxxxxxxxxxxxxxxxxx',
      controller: keyController,
      isPassword: true,
      onConnect: () async {
        final key = keyController.text.trim();
        if (key.isEmpty) return false;
        _setLoading(true);
        final success = await widget.apiManager.connectGeminiOfficial(apiKey: key);
        _setLoading(false);
        return success;
      },
    );
  }

  void _showConnectDialog({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String hintText,
    required TextEditingController controller,
    required bool isPassword,
    required Future<bool> Function() onConnect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                obscureText: isPassword,
                style: const TextStyle(
                  fontFamily: AppTheme.fontCode,
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: const TextStyle(
                    fontFamily: AppTheme.fontCode,
                    fontSize: 13,
                    color: AppTheme.textTertiary,
                  ),
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
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '密钥将使用 AES-256-GCM 加密存储在设备安全区域',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 11,
                  color: AppTheme.textTertiary.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final success = await onConnect();
                    if (mounted && success) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('连接成功'),
                          backgroundColor: AppTheme.success,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('连接失败，请检查密钥'),
                          backgroundColor: AppTheme.error,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '连接',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showAddCustomApiDialog() {
    _showCustomApiFormDialog(config: null);
  }

  void _showEditCustomApiDialog(CustomApiConfig config) {
    _showCustomApiFormDialog(config: config);
  }

  void _showCustomApiFormDialog({CustomApiConfig? config}) {
    final isEdit = config != null;
    final nameController = TextEditingController(text: isEdit ? config.name : '');
    final urlController = TextEditingController(text: isEdit ? config.baseUrl : 'https://');
    final keyController = TextEditingController();
    final modelController = TextEditingController(text: isEdit ? config.model : 'gpt-4o');
    final orgController = TextEditingController(text: isEdit ? (config.organization ?? '') : '');

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.textDisabled,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isEdit ? '编辑 API' : '添加自定义 API',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '支持 OpenRouter、Together AI、LocalAI 等',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Preset buttons
                    if (!isEdit) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildPresetChip(
                            label: 'OpenRouter',
                            url: 'https://openrouter.ai/api/v1',
                            model: 'openai/gpt-4o',
                          ),
                          _buildPresetChip(
                            label: 'Together AI',
                            url: 'https://api.together.xyz/v1',
                            model: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
                          ),
                          _buildPresetChip(
                            label: 'LocalAI',
                            // SECURITY FIX: Use https:// for localhost preset.
                            // Users should configure their local server with TLS.
                            url: 'https://localhost:8080/v1',
                            model: 'ggml-gpt4all-j',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    _buildTextField('名称', nameController, 'My OpenRouter', false),
                    const SizedBox(height: 12),
                    _buildTextField('Base URL', urlController, 'https://api.example.com/v1', false),
                    const SizedBox(height: 12),
                    _buildTextField('API Key', keyController, 'sk-...', true),
                    if (isEdit)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 4),
                        child: Text(
                          '留空则保留现有密钥',
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 11,
                            color: AppTheme.textTertiary.withOpacity(0.7),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    _buildTextField('Model', modelController, 'gpt-4o', false),
                    const SizedBox(height: 12),
                    _buildTextField('组织 ID (可选)', orgController, 'org-...', false),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final name = nameController.text.trim();
                          final url = urlController.text.trim();
                          final key = keyController.text.trim();
                          final model = modelController.text.trim();
                          final org = orgController.text.trim();

                          if (name.isEmpty || url.isEmpty || (!isEdit && key.isEmpty) || model.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('请填写必填字段'),
                                backgroundColor: AppTheme.warning,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }

                          _setLoading(true);
                          try {
                            if (isEdit) {
                              await widget.apiManager.updateCustomApi(
                                config.id,
                                name: name,
                                baseUrl: url,
                                apiKey: key.isEmpty ? null : key,
                                model: model,
                                organization: org.isEmpty ? null : org,
                              );
                            } else {
                              await widget.apiManager.addCustomApi(
                                name: name,
                                baseUrl: url,
                                apiKey: key,
                                model: model,
                                organization: org.isEmpty ? null : org,
                              );
                            }
                            if (mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isEdit ? 'API 已更新' : 'API 已添加'),
                                  backgroundColor: AppTheme.success,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('操作失败: $e'),
                                  backgroundColor: AppTheme.error,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } finally {
                            _setLoading(false);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          isEdit ? '保存' : '添加',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPresetChip({
    required String label,
    required String url,
    required String model,
  }) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 12,
          color: AppTheme.textSecondary,
        ),
      ),
      backgroundColor: AppTheme.surfaceInput,
      side: const BorderSide(color: AppTheme.border),
      onPressed: () {
        // Fill in preset values - need to dismiss and re-show
        Navigator.of(context).pop();
        Future.delayed(const Duration(milliseconds: 300), () {
          _showCustomApiFormDialog();
        });
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 13,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color.withOpacity(0.7)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.surfaceHover,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint,
    bool isPassword,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: isPassword,
          style: const TextStyle(
            fontFamily: AppTheme.fontCode,
            fontSize: 13,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 13,
              color: AppTheme.textTertiary.withOpacity(0.7),
            ),
            filled: true,
            fillColor: AppTheme.surfaceInput,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: AppTheme.textDisabled.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textTertiary.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection(String apiId) async {
    _setLoading(true);
    final status = await widget.apiManager.testConnection(apiId);
    _setLoading(false);

    if (mounted) {
      final isHealthy = status.isHealthy;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isHealthy ? Icons.check_circle : Icons.error,
                color: isHealthy ? AppTheme.success : AppTheme.error,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isHealthy
                      ? '连接正常 · ${status.latencyMs}ms'
                      : '连接失败 · ${status.error ?? '未知错误'}',
                  style: const TextStyle(fontFamily: AppTheme.fontBody),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.surfaceHover,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
