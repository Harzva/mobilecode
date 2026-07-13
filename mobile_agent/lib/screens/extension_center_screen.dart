import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cli_hub_catalog_service.dart';
import '../services/cli_hub_runtime_events.dart';
import '../services/linux_sandbox_provider.dart';
import '../services/mobilecode_build_profile.dart';
import '../themes/app_theme.dart';

class ExtensionCenterScreen extends StatefulWidget {
  ExtensionCenterScreen({
    super.key,
    LinuxSandboxRuntimeProvider? provider,
    CliHubCatalogService? catalogService,
    this.localExtensionStore,
    this.trustedKeyStore,
    this.remoteManifestDownloader,
    this.includePreviewCliCatalog =
        MobileCodeBuildProfile.includePreviewCliCatalog,
    this.bundledAlpineRuntime = MobileCodeBuildProfile.bundledAlpineRuntime,
  })  : provider = provider ?? LinuxSandboxRuntimeProvider(),
        catalogService = catalogService ?? const CliHubCatalogService();

  final LinuxSandboxRuntimeProvider provider;
  final CliHubCatalogService catalogService;
  final CliHubLocalExtensionStore? localExtensionStore;
  final CliHubTrustedKeyStore? trustedKeyStore;
  final CliHubRemoteManifestDownloader? remoteManifestDownloader;
  final bool includePreviewCliCatalog;
  final bool bundledAlpineRuntime;

  @override
  State<ExtensionCenterScreen> createState() => _ExtensionCenterScreenState();
}

class _ExtensionCenterScreenState extends State<ExtensionCenterScreen> {
  final Map<String, _ExtensionOperation> _operations = {};
  CliHubCatalog? _catalog;
  String? _catalogError;
  CliHubLocalExtensionStore? _localExtensionStore;
  CliHubTrustedKeyStore? _trustedKeyStore;
  Set<String> _localExtensionIds = const {};
  List<CliHubTrustedKey> _trustedKeys = const [];
  bool _autoBundledInstallStarted = false;
  bool _alpineUserUninstalled = false;
  StreamSubscription<CliHubRuntimeEvent>? _cliHubRuntimeEvents;

  LinuxSandboxRuntimeProvider get provider => widget.provider;

  @override
  void initState() {
    super.initState();
    _cliHubRuntimeEvents = CliHubRuntimeEvents.stream.listen((event) {
      if (!mounted || !event.changesInstallOrAuthState) return;
      unawaited(_refresh());
    });
    _refresh();
  }

  @override
  void dispose() {
    _cliHubRuntimeEvents?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await provider.initialize();
      final bundledCatalog = await widget.catalogService.loadBundledCatalog();
      final profileCatalog = widget.catalogService.catalogForBuildProfile(
        bundledCatalog,
        includePreviewAndPlanned: widget.includePreviewCliCatalog,
      );
      final localStore = await _ensureLocalExtensionStore();
      final localCatalogs = await localStore.loadCatalogs();
      final trustedKeyStore = await _ensureTrustedKeyStore();
      _trustedKeys = await trustedKeyStore.loadKeys();
      _catalog = await widget.catalogService.mergeCatalogs(
        profileCatalog,
        localCatalogs,
      );
      _localExtensionIds = {
        for (final catalog in localCatalogs)
          for (final entry in catalog.entries) entry.id,
      };
      _catalogError = null;
    } on Object catch (error) {
      _catalogError = error.toString();
    } finally {
      if (mounted) setState(() {});
    }
    if (mounted) _maybeInstallBundledAlpine();
  }

  Future<CliHubLocalExtensionStore> _ensureLocalExtensionStore() async {
    final injected = widget.localExtensionStore;
    if (injected != null) return injected;
    final existing = _localExtensionStore;
    if (existing != null) return existing;
    final preferences = await SharedPreferences.getInstance();
    final store = CliHubLocalExtensionStore(
      preferences: preferences,
      catalogService: widget.catalogService,
    );
    _localExtensionStore = store;
    return store;
  }

  Future<CliHubTrustedKeyStore> _ensureTrustedKeyStore() async {
    final injected = widget.trustedKeyStore;
    if (injected != null) return injected;
    final existing = _trustedKeyStore;
    if (existing != null) return existing;
    final preferences = await SharedPreferences.getInstance();
    final store = CliHubTrustedKeyStore(preferences: preferences);
    _trustedKeyStore = store;
    return store;
  }

  @override
  Widget build(BuildContext context) {
    final state = provider.state;
    final installedIds = {
      for (final profile in state.packageProfiles)
        if (profile.installed) profile.id,
    };
    final extensions = [
      _RuntimeExtension.rootfs(
        installed: state.installed,
        bundledAlpineRuntime: widget.bundledAlpineRuntime,
      ),
      for (final entry in _catalog?.entries ?? const <CliHubEntry>[])
        _RuntimeExtension.fromCatalogEntry(
          entry,
          installed: entry.install.profileId != null &&
              installedIds.contains(entry.install.profileId),
          alpineInstalled: state.installed,
        ),
    ];
    final busy = _operations.values.any((operation) => operation.busy);

    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      appBar: AppBar(
        title: const Text('扩展中心'),
        backgroundColor: AppTheme.deepSpace,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '管理远端信任密钥',
            onPressed: busy ? null : _showTrustedKeyManagerDialog,
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
          IconButton(
            tooltip: '导入远端信任密钥',
            onPressed: busy ? null : _showImportTrustedKeyDialog,
            icon: const Icon(Icons.vpn_key_outlined),
          ),
          IconButton(
            tooltip: '导入远端 CLI Catalog',
            onPressed: busy ? null : _showImportRemoteCatalogDialog,
            icon: const Icon(Icons.cloud_download_outlined),
          ),
          IconButton(
            tooltip: '导入本地 CLI Catalog',
            onPressed: busy ? null : _showImportLocalCatalogDialog,
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _HeaderCard(
            installed: state.installed,
            status: state.status.name,
            rootfsLabel: '${state.manifest.version} · ${state.manifest.arch}',
            catalogStatus: _catalog == null
                ? 'catalog loading'
                : '${_catalog!.entries.length} CLI entries · ${MobileCodeBuildProfile.label}',
            runtimePolicy: widget.bundledAlpineRuntime
                ? 'Dev Harness · Alpine built-in · CLI 按需安装'
                : 'Pure APK · Alpine 按需下载 · CLI 按需安装',
            policy: MobileCodeBuildProfile.cliCatalogPolicy,
            trustedKeyCount: _trustedKeys.length,
          ),
          if (_catalogError != null) ...[
            const SizedBox(height: 10),
            _ResultCard(result: {
              'success': false,
              'status': 'catalog_error',
              'stderr': _catalogError,
            }),
          ],
          const SizedBox(height: 14),
          for (final extension in extensions) ...[
            _ExtensionCard(
              extension: extension,
              operation:
                  _operations[extension.id] ?? const _ExtensionOperation.idle(),
              enabled: !busy,
              alpineInstalled: state.installed,
              onInstall: () => _installExtension(extension),
              onUninstall: extension.id == 'rootfs'
                  ? () => _uninstallAlpine(extension)
                  : null,
              onRemoveLocalExtension: _localExtensionIds.contains(extension.id)
                  ? () => _removeLocalExtension(extension)
                  : null,
              onProbe: () => _probeExtension(extension),
              onTask: (task) => _runExtensionTask(extension, task),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  void _maybeInstallBundledAlpine() {
    if (!widget.bundledAlpineRuntime ||
        _autoBundledInstallStarted ||
        _alpineUserUninstalled ||
        provider.state.installed) {
      return;
    }
    _autoBundledInstallStarted = true;
    _installExtension(
      _RuntimeExtension.rootfs(
        installed: false,
        bundledAlpineRuntime: true,
      ),
      confirm: false,
      operationLabel: '正在导入 Dev Harness 内置 Alpine...',
    );
  }

  Future<void> _showImportLocalCatalogDialog() async {
    final controller = TextEditingController();
    final manifestJson = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入本地 CLI Catalog'),
        content: SizedBox(
          width: 520,
          child: TextField(
            key: const ValueKey('extensionCenter.importCatalog.input'),
            controller: controller,
            minLines: 8,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Catalog JSON',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (manifestJson == null || manifestJson.trim().isEmpty) return;
    await _importLocalCatalogJson(manifestJson);
  }

  Future<void> _showImportRemoteCatalogDialog() async {
    final controller = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入远端 CLI Catalog'),
        content: SizedBox(
          width: 520,
          child: TextField(
            key: const ValueKey('extensionCenter.importRemoteCatalog.url'),
            controller: controller,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'HTTPS Manifest URL',
              helperText: '必须通过 MobileCode 远端 manifest 签名或完整性校验',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (source == null || source.trim().isEmpty) return;
    await _importRemoteCatalog(source);
  }

  Future<void> _showImportTrustedKeyDialog() async {
    final controller = TextEditingController();
    final keyJson = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入远端信任密钥'),
        content: SizedBox(
          width: 520,
          child: TextField(
            key: const ValueKey('extensionCenter.importTrustedKey.input'),
            controller: controller,
            minLines: 8,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Trusted Key JSON',
              helperText: '仅保存 Ed25519 public key，不要粘贴任何凭据或私钥',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (keyJson == null || keyJson.trim().isEmpty) return;
    await _importTrustedKey(keyJson);
  }

  Future<void> _showTrustedKeyManagerDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('远端信任密钥'),
        content: SizedBox(
          width: 520,
          child: _trustedKeys.isEmpty
              ? const Text('还没有导入远端信任密钥。')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final key in _trustedKeys)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(key.keyId),
                        subtitle: Text(_trustedKeySummary(key)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey(
                                'extensionCenter.trustedKey.revoke.${key.keyId}',
                              ),
                              tooltip: key.revoked
                                  ? '${key.keyId} 已撤销'
                                  : '撤销 ${key.keyId}',
                              onPressed: key.revoked
                                  ? null
                                  : () => Navigator.of(context)
                                      .pop('__revoke__:${key.keyId}'),
                              icon: const Icon(Icons.block),
                            ),
                            IconButton(
                              key: ValueKey(
                                'extensionCenter.trustedKey.remove.${key.keyId}',
                              ),
                              tooltip: '移除 ${key.keyId}',
                              onPressed: () => Navigator.of(context)
                                  .pop('__remove__:${key.keyId}'),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('__import__'),
            child: const Text('导入'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    if (selected == '__import__') {
      await _showImportTrustedKeyDialog();
      return;
    }
    if (selected.startsWith('__revoke__:')) {
      await _revokeTrustedKey(selected.substring('__revoke__:'.length));
      return;
    }
    if (selected.startsWith('__remove__:')) {
      await _removeTrustedKey(selected.substring('__remove__:'.length));
    }
  }

  Future<void> _importTrustedKey(String keyJson) async {
    try {
      final store = await _ensureTrustedKeyStore();
      final key = await store.addKeyJson(keyJson);
      _trustedKeys = await store.loadKeys();
      if (!mounted) return;
      _toast('已导入远端信任密钥：${key.keyId}');
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _catalogError = error.toString());
      _toast('信任密钥导入失败：$error');
    }
  }

  Future<void> _removeTrustedKey(String keyId) async {
    try {
      final store = await _ensureTrustedKeyStore();
      await store.removeKey(keyId);
      _trustedKeys = await store.loadKeys();
      if (!mounted) return;
      _toast('已移除远端信任密钥：$keyId');
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _catalogError = error.toString());
      _toast('信任密钥移除失败：$error');
    }
  }

  Future<void> _revokeTrustedKey(String keyId) async {
    try {
      final store = await _ensureTrustedKeyStore();
      final key = await store.revokeKey(keyId);
      _trustedKeys = await store.loadKeys();
      if (!mounted) return;
      _toast('已撤销远端信任密钥：${key.keyId}');
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _catalogError = error.toString());
      _toast('信任密钥撤销失败：$error');
    }
  }

  Future<void> _importRemoteCatalog(String source) async {
    try {
      final uri = Uri.parse(source.trim());
      final remote = await widget.catalogService.fetchRemoteManifest(
        uri,
        downloader: widget.remoteManifestDownloader,
        requireVerifiedSignature: true,
        trustedKeyring: _trustedKeys,
      );
      final bundledCatalog = await widget.catalogService.loadBundledCatalog();
      final profileCatalog = widget.catalogService.catalogForBuildProfile(
        bundledCatalog,
        includePreviewAndPlanned: widget.includePreviewCliCatalog,
      );
      final store = await _ensureLocalExtensionStore();
      await store.addCatalogJson(
        jsonEncode({
          'schemaVersion': remote.manifest.catalog.schemaVersion,
          'updatedAt': remote.manifest.catalog.updatedAt.toIso8601String(),
          'entries': [
            for (final entry in remote.manifest.catalog.entries)
              _catalogEntryJson(entry),
          ],
        }),
        bundledCatalog: profileCatalog,
      );
      if (!mounted) return;
      _toast(
        '已导入远端 CLI Catalog：${remote.manifest.catalog.entries.length} 个 extension',
      );
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _catalogError = error.toString());
      _toast('远端导入失败：$error');
    }
  }

  Future<void> _importLocalCatalogJson(String manifestJson) async {
    try {
      final bundledCatalog = await widget.catalogService.loadBundledCatalog();
      final profileCatalog = widget.catalogService.catalogForBuildProfile(
        bundledCatalog,
        includePreviewAndPlanned: widget.includePreviewCliCatalog,
      );
      final store = await _ensureLocalExtensionStore();
      final catalog = await store.addCatalogJson(
        manifestJson,
        bundledCatalog: profileCatalog,
      );
      if (!mounted) return;
      _toast('已导入 ${catalog.entries.length} 个本地 CLI extension');
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _catalogError = error.toString());
      _toast('导入失败：$error');
    }
  }

  Future<void> _installExtension(
    _RuntimeExtension extension, {
    bool confirm = true,
    String? operationLabel,
  }) async {
    if (extension.installed && extension.profileId != null) return;
    if (!extension.canInstall) {
      _toast('${extension.title} 还没有接入受控安装器');
      return;
    }
    if (confirm) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${extension.primaryLabel}？'),
          content: _InstallPreviewContent(
            extension: extension,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (approved != true) return;
    }

    _setOperation(
      extension.id,
      _ExtensionOperation.running(
        label: operationLabel ??
            (extension.id == 'rootfs'
                ? '正在安装并校验 Alpine...'
                : '正在安装 ${extension.title}...'),
        progress: extension.id == 'rootfs' ? provider.state.progress : null,
      ),
    );
    try {
      if (extension.id == 'rootfs') {
        final state = await provider.installRootfs();
        if (!mounted) return;
        _alpineUserUninstalled = false;
        _setOperation(
          extension.id,
          _ExtensionOperation.fromResult({
            'success': state.installed,
            'status': state.status.name,
            'stderr': state.recoveryHint ?? '',
          }),
        );
        await _refresh();
      } else {
        if (!provider.state.installed) {
          const message = '需要先安装 Alpine Linux Runtime';
          _toast(message);
          _setOperation(
              extension.id, const _ExtensionOperation.failed(message));
          return;
        }
        final result = await provider.runTypedTask(
          taskKind: 'package_install',
          payload: {
            'profileId': extension.profileId,
            'approved': true,
          },
        );
        if (!mounted) return;
        _setOperation(extension.id, _ExtensionOperation.fromResult(result));
        _publishCliHubRuntimeEvent(extension, 'package_install', result);
        await _refresh();
      }
    } finally {
      _clearBusy(extension.id);
    }
  }

  Future<void> _uninstallAlpine(_RuntimeExtension extension) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('卸载 Alpine Runtime？'),
        content: const Text(
          '这会删除 app-owned Linux Sandbox rootfs。Git、Node 和 CLI 扩展会回到需要 Alpine 的状态。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (approved != true) return;

    _setOperation(
      extension.id,
      const _ExtensionOperation.running(label: '正在卸载 Alpine...'),
    );
    try {
      final state = await provider.deleteRootfs();
      if (!mounted) return;
      _alpineUserUninstalled = true;
      _setOperation(
        extension.id,
        _ExtensionOperation.fromResult({
          'success': !state.installed,
          'status': state.status.name,
          'stderr': state.recoveryHint ?? '',
        }),
      );
      await _refresh();
    } finally {
      _clearBusy(extension.id);
    }
  }

  Future<void> _removeLocalExtension(_RuntimeExtension extension) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除 ${extension.title}？'),
        content: const Text(
          '这只会移除本地导入的 CLI catalog 记录，不会删除内置 CLI，也不会执行 raw shell。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (approved != true) return;

    try {
      final store = await _ensureLocalExtensionStore();
      await store.removeCatalogContainingEntry(extension.id);
      if (!mounted) return;
      _toast('已移除 ${extension.title}');
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _catalogError = error.toString());
      _toast('移除失败：$error');
    }
  }

  Future<void> _probeExtension(_RuntimeExtension extension) async {
    final taskKind = extension.probeTaskKind;
    if (taskKind == null) {
      _toast('${extension.title} 还没有 probe typed task');
      return;
    }
    if (!provider.state.installed) {
      const message = '需要先安装 Alpine Linux Runtime';
      _toast(message);
      _setOperation(extension.id, const _ExtensionOperation.failed(message));
      return;
    }
    _setOperation(
      extension.id,
      _ExtensionOperation.running(label: '正在检测 ${extension.title}...'),
    );
    try {
      final result = await provider.runTypedTask(
        taskKind: taskKind,
        payload: const {},
      );
      if (!mounted) return;
      _setOperation(extension.id, _ExtensionOperation.fromResult(result));
      await _refresh();
    } finally {
      _clearBusy(extension.id);
    }
  }

  Future<void> _runExtensionTask(
    _RuntimeExtension extension,
    CliHubTask task,
  ) async {
    if (!provider.state.installed) {
      const message = '需要先安装 Alpine Linux Runtime';
      _toast(message);
      _setOperation(extension.id, const _ExtensionOperation.failed(message));
      return;
    }
    if (extension.profileId != null && !extension.installed) {
      _toast('请先安装 ${extension.title}');
      return;
    }
    final payload = Map<String, dynamic>.from(task.payload);
    if (task.requiresApproval) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${task.label}？'),
          content: Text(
            '${extension.title}\n\n'
            '将执行 typed task：${task.taskKind}\n'
            '参数：${payload.isEmpty ? '无' : payload}\n\n'
            '该操作不会暴露 raw shell；需要授权或外部浏览器时，请由用户手动完成。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      payload['approved'] = true;
    }

    _setOperation(
      extension.id,
      _ExtensionOperation.running(label: '正在执行 ${task.label}...'),
    );
    try {
      final result = await provider.runTypedTask(
        taskKind: task.taskKind,
        payload: payload,
      );
      if (!mounted) return;
      _setOperation(extension.id, _ExtensionOperation.fromResult(result));
      _publishCliHubRuntimeEvent(extension, task.taskKind, result);
      if (_opensOfficialAuthFlow(task.taskKind)) {
        await _openFirstHttpsUrl(result);
      }
      await _refresh();
    } finally {
      _clearBusy(extension.id);
    }
  }

  void _publishCliHubRuntimeEvent(
    _RuntimeExtension extension,
    String taskKind,
    Map<String, dynamic> result,
  ) {
    CliHubRuntimeEvents.publish(CliHubRuntimeEvent(
      cliId: extension.id,
      taskKind: taskKind,
      status: result['status']?.toString() ??
          result['failureKind']?.toString() ??
          (result['success'] == true ? 'completed' : 'failed'),
      success: result['success'] == true,
      profileId: extension.profileId,
    ));
  }

  void _setOperation(String id, _ExtensionOperation operation) {
    if (!mounted) return;
    setState(() => _operations[id] = operation);
  }

  void _clearBusy(String id) {
    if (!mounted) return;
    final current = _operations[id];
    if (current?.busy == true) {
      setState(() => _operations[id] = current!.copyWith(busy: false));
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _trustedKeySummary(CliHubTrustedKey key) {
    final scopes = <String>[
      if (key.allowedCatalogIds.isNotEmpty)
        'catalog:${key.allowedCatalogIds.join(",")}',
      if (key.allowedHosts.isNotEmpty) 'host:${key.allowedHosts.join(",")}',
      if (key.revoked) 'revoked',
    ];
    final validity = <String>[
      if (key.validFrom != null) 'from:${key.validFrom!.toIso8601String()}',
      if (key.validUntil != null) 'until:${key.validUntil!.toIso8601String()}',
    ];
    final rotation = <String>[
      if (key.replacementKeyId != null) 'rotateTo:${key.replacementKeyId}',
      if (key.rotationRequiredAfter != null)
        'rotateBy:${key.rotationRequiredAfter!.toIso8601String()}',
    ];
    return [
      key.algorithm,
      if (scopes.isNotEmpty) scopes.join(' · '),
      if (validity.isNotEmpty) validity.join(' · '),
      if (rotation.isNotEmpty) rotation.join(' · '),
    ].join(' · ');
  }

  Future<void> _openFirstHttpsUrl(Map<String, dynamic> result) async {
    final uri = _firstHttpsUri([
      result['stdout']?.toString() ?? '',
      result['stderr']?.toString() ?? '',
    ].join('\n'));
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _toast('无法打开登录链接，请从结果中复制 URL');
  }
}

Map<String, Object?> _catalogEntryJson(CliHubEntry entry) => {
      'id': entry.id,
      'title': entry.title,
      'command': entry.command,
      'category': entry.category,
      'supportLevel': entry.supportLevel.name,
      'officialSources': entry.officialSources,
      'install': {
        'strategy': entry.install.strategy.name,
        if (entry.install.profileId != null)
          'profileId': entry.install.profileId,
        'packages': entry.install.packages,
      },
      'probe': {
        if (entry.probe.taskKind != null) 'taskKind': entry.probe.taskKind,
        'safeArgs': entry.probe.safeArgs,
      },
      'auth': {
        'required': entry.auth.required,
        'storage': entry.auth.storage,
        'notes': entry.auth.notes,
      },
      'riskLevel': entry.riskLevel.name,
      'credentialPolicy': entry.credentialPolicy.name,
      'tasks': [
        for (final task in entry.tasks)
          {
            'id': task.id,
            'label': task.label,
            'taskKind': task.taskKind,
            'payload': task.payload,
            'requiresApproval': task.requiresApproval,
          },
      ],
      'readOnlyTasks': entry.readOnlyTaskIds,
      'mutationTasks': entry.mutationTaskIds,
      'safetyNotes': entry.safetyNotes,
    };

Uri? _firstHttpsUri(String text) {
  final match = RegExp(r'https://[^\s<>"）)]+').firstMatch(text);
  if (match == null) return null;
  return Uri.tryParse(match.group(0)!);
}

class _RuntimeExtension {
  const _RuntimeExtension({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.installed,
    required this.primaryLabel,
    required this.packages,
    required this.profileId,
    required this.supportLabel,
    required this.riskLevel,
    required this.credentialPolicy,
    required this.probeTaskKind,
    required this.tasks,
    required this.readOnlyTaskIds,
    required this.mutationTaskIds,
    required this.officialSources,
    this.needsAlpine = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool installed;
  final String primaryLabel;
  final List<String> packages;
  final String? profileId;
  final String supportLabel;
  final CliHubRiskLevel riskLevel;
  final CliHubCredentialPolicy credentialPolicy;
  final String? probeTaskKind;
  final List<CliHubTask> tasks;
  final List<String> readOnlyTaskIds;
  final List<String> mutationTaskIds;
  final List<String> officialSources;
  final bool needsAlpine;

  bool get canInstall => id == 'rootfs' || profileId != null;

  factory _RuntimeExtension.rootfs({
    required bool installed,
    required bool bundledAlpineRuntime,
  }) {
    return _RuntimeExtension(
      id: 'rootfs',
      title: 'Alpine Linux Runtime',
      subtitle: bundledAlpineRuntime
          ? 'Dev Harness 默认基础运行层；Git、Node、CLI 扩展仍按需安装'
          : 'Git、Node、CLI 扩展的基础运行层；Pure APK 按需下载',
      icon: Icons.terminal_outlined,
      installed: installed,
      primaryLabel: installed ? '重新校验' : '一键安装',
      packages: const ['Alpine minirootfs', 'apk-tools', 'busybox'],
      profileId: null,
      supportLabel: 'supported',
      riskLevel: CliHubRiskLevel.medium,
      credentialPolicy: CliHubCredentialPolicy.none,
      probeTaskKind: 'apk_version',
      tasks: const [],
      readOnlyTaskIds: const [],
      mutationTaskIds: const [],
      officialSources: const ['https://alpinelinux.org/'],
    );
  }

  factory _RuntimeExtension.fromCatalogEntry(
    CliHubEntry entry, {
    required bool installed,
    required bool alpineInstalled,
  }) {
    final profileId = entry.install.profileId;
    final installable = entry.canInstallInSandbox;
    return _RuntimeExtension(
      id: entry.id,
      title: entry.title,
      subtitle: _subtitleForEntry(entry),
      icon: _iconForCategory(entry.category),
      installed: installed,
      primaryLabel: installed
          ? '已安装'
          : (installable ? '安装' : _supportLabel(entry.supportLevel)),
      packages: entry.install.packages,
      profileId: profileId,
      supportLabel: _supportLabel(entry.supportLevel),
      riskLevel: entry.riskLevel,
      credentialPolicy: entry.credentialPolicy,
      probeTaskKind: entry.probe.taskKind,
      tasks: entry.tasks,
      readOnlyTaskIds: entry.readOnlyTaskIds,
      mutationTaskIds: entry.mutationTaskIds,
      officialSources: entry.officialSources,
      needsAlpine: installable && !alpineInstalled && !installed,
    );
  }
}

class _InstallPreviewContent extends StatelessWidget {
  const _InstallPreviewContent({required this.extension});

  final _RuntimeExtension extension;

  @override
  Widget build(BuildContext context) {
    final source = extension.officialSources.isEmpty
        ? '未声明'
        : extension.officialSources.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          extension.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _PreviewLine(label: '来源', value: source),
        _PreviewLine(
          label: '安装包',
          value:
              extension.packages.isEmpty ? '无' : extension.packages.join(', '),
        ),
        _PreviewLine(label: '风险等级', value: extension.riskLevel.name),
        _PreviewLine(
          label: '凭据策略',
          value: extension.credentialPolicy.name,
        ),
        _PreviewLine(
          label: '任务范围',
          value:
              'read-only:${extension.readOnlyTaskIds.length} · mutation:${extension.mutationTaskIds.length}',
        ),
        const SizedBox(height: 12),
        const Text(
          '该操作会通过 MobileCode Linux Sandbox typed task 执行，需要用户确认，不暴露 raw shell。',
        ),
      ],
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('$label：$value'),
    );
  }
}

class _ExtensionOperation {
  const _ExtensionOperation({
    required this.busy,
    required this.label,
    required this.progress,
    required this.result,
  });

  const _ExtensionOperation.idle()
      : busy = false,
        label = '',
        progress = null,
        result = null;

  const _ExtensionOperation.running({
    required this.label,
    this.progress,
  })  : busy = true,
        result = null;

  const _ExtensionOperation.failed(String message)
      : busy = false,
        label = message,
        progress = null,
        result = const {
          'success': false,
          'status': 'blocked',
        };

  factory _ExtensionOperation.fromResult(Map<String, dynamic> result) {
    final success = result['success'] == true;
    final hasWarnings = result['warning'] == true ||
        (result['warnings'] is List && (result['warnings'] as List).isNotEmpty);
    final status = result['status']?.toString() ??
        result['failureKind']?.toString() ??
        (success ? 'completed' : 'failed');
    return _ExtensionOperation(
      busy: false,
      label: success
          ? (hasWarnings ? '完成但有警告 · $status' : '完成 · $status')
          : '未完成 · $status',
      progress: success ? 1 : null,
      result: result,
    );
  }

  final bool busy;
  final String label;
  final double? progress;
  final Map<String, dynamic>? result;

  _ExtensionOperation copyWith({
    bool? busy,
    String? label,
    double? progress,
    Map<String, dynamic>? result,
  }) {
    return _ExtensionOperation(
      busy: busy ?? this.busy,
      label: label ?? this.label,
      progress: progress ?? this.progress,
      result: result ?? this.result,
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.installed,
    required this.status,
    required this.rootfsLabel,
    required this.catalogStatus,
    required this.runtimePolicy,
    required this.policy,
    required this.trustedKeyCount,
  });

  final bool installed;
  final String status;
  final String rootfsLabel;
  final String catalogStatus;
  final String runtimePolicy;
  final String policy;
  final int trustedKeyCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.72)),
      ),
      child: Row(
        children: [
          Icon(
            installed ? Icons.verified_outlined : Icons.extension_outlined,
            color: installed ? AppTheme.success : AppTheme.cyan,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  runtimePolicy,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$rootfsLabel · $status · $catalogStatus · trusted keys:$trustedKeyCount',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  policy,
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtensionCard extends StatelessWidget {
  const _ExtensionCard({
    required this.extension,
    required this.operation,
    required this.enabled,
    required this.alpineInstalled,
    required this.onInstall,
    required this.onUninstall,
    required this.onRemoveLocalExtension,
    required this.onProbe,
    required this.onTask,
  });

  final _RuntimeExtension extension;
  final _ExtensionOperation operation;
  final bool enabled;
  final bool alpineInstalled;
  final VoidCallback onInstall;
  final VoidCallback? onUninstall;
  final VoidCallback? onRemoveLocalExtension;
  final VoidCallback onProbe;
  final ValueChanged<CliHubTask> onTask;

  @override
  Widget build(BuildContext context) {
    final blockedByAlpine = extension.needsAlpine;
    final color = extension.installed
        ? AppTheme.success
        : blockedByAlpine
            ? AppTheme.warning
            : AppTheme.cyan;
    final primaryLabel =
        blockedByAlpine ? '先安装 Alpine' : extension.primaryLabel;
    final canRunExtension =
        enabled && !operation.busy && !blockedByAlpine && extension.canInstall;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.64)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(extension.icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      extension.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      extension.subtitle,
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FilledButton.tonal(
                    key: ValueKey('extensionCenter.install.${extension.id}'),
                    onPressed: canRunExtension &&
                            (!extension.installed || extension.id == 'rootfs')
                        ? onInstall
                        : null,
                    child: Text(primaryLabel),
                  ),
                  if (extension.id == 'rootfs' && extension.installed) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      key: const ValueKey('extensionCenter.uninstall.rootfs'),
                      onPressed:
                          enabled && !operation.busy ? onUninstall : null,
                      child: const Text('卸载'),
                    ),
                  ],
                  if (onRemoveLocalExtension != null) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      key: ValueKey(
                        'extensionCenter.removeLocal.${extension.id}',
                      ),
                      onPressed: enabled && !operation.busy
                          ? onRemoveLocalExtension
                          : null,
                      child: const Text('移除'),
                    ),
                  ],
                  const SizedBox(height: 6),
                  OutlinedButton(
                    key: ValueKey('extensionCenter.probe.${extension.id}'),
                    onPressed: enabled &&
                            !operation.busy &&
                            !blockedByAlpine &&
                            extension.probeTaskKind != null
                        ? onProbe
                        : null,
                    child: const Text('检测'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(_installStateLabel(extension, alpineInstalled)),
              ),
              for (final package in extension.packages)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(package),
                ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(extension.supportLabel),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text('risk:${extension.riskLevel.name}'),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text('credential:${extension.credentialPolicy.name}'),
              ),
              if (extension.readOnlyTaskIds.isNotEmpty)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('read-only:${extension.readOnlyTaskIds.length}'),
                ),
              if (extension.mutationTaskIds.isNotEmpty)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('mutation:${extension.mutationTaskIds.length}'),
                ),
            ],
          ),
          if (extension.tasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final task in extension.tasks)
                  OutlinedButton(
                    key: ValueKey(
                      'extensionCenter.task.${extension.id}.${task.id}',
                    ),
                    onPressed: enabled && !operation.busy && extension.installed
                        ? () => onTask(task)
                        : null,
                    child: Text(task.label),
                  ),
              ],
            ),
          ],
          if (operation.busy || operation.label.isNotEmpty) ...[
            const SizedBox(height: 12),
            _OperationStatus(operation: operation),
          ],
        ],
      ),
    );
  }
}

class _OperationStatus extends StatelessWidget {
  const _OperationStatus({required this.operation});

  final _ExtensionOperation operation;

  @override
  Widget build(BuildContext context) {
    final result = operation.result;
    final success = result?['success'] == true;
    final hasWarnings = result?['warning'] == true ||
        (result?['warnings'] is List &&
            (result?['warnings'] as List).isNotEmpty);
    final stdout = result?['stdout']?.toString() ?? '';
    final stderr = result?['stderr']?.toString() ?? '';
    final warnings = (result?['warnings'] as List?)
            ?.map((warning) => warning.toString())
            .where((warning) => warning.trim().isNotEmpty)
            .join('\n') ??
        '';
    final detail = [
      if (warnings.trim().isNotEmpty) warnings.trim(),
      if (stdout.trim().isNotEmpty) stdout.trim(),
      if (stderr.trim().isNotEmpty) stderr.trim(),
    ].join('\n');
    final color = operation.busy
        ? AppTheme.cyan
        : hasWarnings
            ? AppTheme.warning
            : success
                ? AppTheme.success
                : AppTheme.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                operation.busy
                    ? Icons.downloading_outlined
                    : hasWarnings
                        ? Icons.warning_amber_outlined
                        : success
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  operation.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (operation.busy) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: operation.progress),
          ],
          if (!operation.busy && detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _installStateLabel(_RuntimeExtension extension, bool alpineInstalled) {
  if (extension.id == 'rootfs') {
    return extension.installed ? '已安装' : '未安装';
  }
  if (extension.installed) return '已安装';
  if (!alpineInstalled) return '需要 Alpine';
  return '未安装';
}

bool _opensOfficialAuthFlow(String taskKind) =>
    taskKind.endsWith('_auth_start') ||
    taskKind.endsWith('_auth_login') ||
    taskKind.endsWith('_auth_setup');

String _supportLabel(CliHubSupportLevel level) => switch (level) {
      CliHubSupportLevel.supported => 'supported',
      CliHubSupportLevel.preview => 'preview',
      CliHubSupportLevel.planned => 'planned',
    };

String _subtitleForEntry(CliHubEntry entry) {
  final auth = entry.auth.required ? '需要授权' : '无需授权';
  final task = entry.probe.taskKind ?? 'probe 待接入';
  return '${entry.command} · $auth · $task';
}

IconData _iconForCategory(String category) => switch (category) {
      'collaboration' => Icons.workspaces_outline,
      'deploy' => Icons.rocket_launch_outlined,
      'cloud' => Icons.cloud_outlined,
      'package' => Icons.inventory_2_outlined,
      'ai' => Icons.auto_awesome,
      _ => Icons.terminal_outlined,
    };

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final success = result['success'] == true;
    final stdout = result['stdout']?.toString() ?? '';
    final stderr = result['stderr']?.toString() ?? '';
    final detail = [
      if (stdout.trim().isNotEmpty) stdout.trim(),
      if (stderr.trim().isNotEmpty) stderr.trim(),
    ].join('\n');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.64)),
      ),
      child: Text(
        '${success ? '完成' : '未完成'} · ${result['status'] ?? result['failureKind'] ?? 'unknown'}\n$detail',
        style: const TextStyle(color: AppTheme.textSecondary, height: 1.35),
      ),
    );
  }
}
