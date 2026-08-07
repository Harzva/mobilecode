enum MobileCodeBuildChannel { pure, devHarness }

class MobileCodeBuildProfile {
  const MobileCodeBuildProfile._();

  static const _rawChannel = String.fromEnvironment(
    'MOBILECODE_BUILD_CHANNEL',
    defaultValue: 'pure',
  );

  static const devExtensions = bool.fromEnvironment(
    'MOBILECODE_DEV_EXTENSIONS',
  );

  static const harnessCli = bool.fromEnvironment(
    'MOBILECODE_HARNESS_CLI',
  );

  static const channel = _rawChannel == 'devHarness' ||
          _rawChannel == 'devharness' ||
          devExtensions ||
          harnessCli
      ? MobileCodeBuildChannel.devHarness
      : MobileCodeBuildChannel.pure;

  static const isDevHarness = channel == MobileCodeBuildChannel.devHarness;

  static const includePreviewCliCatalog = isDevHarness;

  static const allowHarnessCliTasks = isDevHarness && harnessCli;

  static const bundledAlpineRuntime = isDevHarness;

  static String get label => isDevHarness ? 'Dev Harness APK' : 'Pure APK';

  static String get alpineRuntimePolicy => isDevHarness
      ? 'Dev Harness · Alpine built-in · CLI 按需安装'
      : 'Pure APK · Alpine 按需下载 · CLI 按需安装';

  static String get cliCatalogPolicy => isDevHarness
      ? '完整 CLI Hub 可见；Alpine 默认可用，CLI 仍按需安装。'
      : '纯净 APK 展示基础 profile 与 HyperFrames 兼容预览；其他预览 CLI 不随 APK 暴露。';
}
