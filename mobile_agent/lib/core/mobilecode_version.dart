class MobileCodeVersion {
  const MobileCodeVersion._();

  static const String semantic = '0.1.78';
  static const int buildNumber = 68;
  static const String tag = 'v$semantic';
  static const String display = tag;
  static const String githubRepoUrl = 'https://github.com/Harzva/mobilecode';
  static const String releaseUrl = '$githubRepoUrl/releases/tag/$tag';
  static const String androidDownloadUrl =
      '$githubRepoUrl/releases/download/$tag/mobilecode-$tag.apk';
}
