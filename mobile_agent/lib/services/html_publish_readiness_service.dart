import 'dart:io';

enum HtmlPublishIssueSeverity {
  blocking,
  warning,
  info,
}

class HtmlPublishIssue {
  const HtmlPublishIssue({
    required this.code,
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String code;
  final String title;
  final String detail;
  final HtmlPublishIssueSeverity severity;
}

class HtmlPublishReadinessReport {
  const HtmlPublishReadinessReport({
    required this.sourcePath,
    required this.checkedAt,
    required this.issues,
    this.allowRemoteAssets = false,
  });

  final String? sourcePath;
  final DateTime checkedAt;
  final List<HtmlPublishIssue> issues;
  final bool allowRemoteAssets;

  List<HtmlPublishIssue> get blockingIssues =>
      issues.where((issue) => issue.severity == HtmlPublishIssueSeverity.blocking).toList(growable: false);

  List<HtmlPublishIssue> get warningIssues =>
      issues.where((issue) => issue.severity == HtmlPublishIssueSeverity.warning).toList(growable: false);

  bool get blocked => blockingIssues.isNotEmpty;
  bool get hasWarnings => warningIssues.isNotEmpty;
  bool get ready => !blocked;

  String get statusLabel {
    if (blocked) return 'Blocked';
    if (hasWarnings) return 'Warnings';
    return 'Ready';
  }

  String toAgentSummary({int maxIssues = 4}) {
    final buffer = StringBuffer()
      ..write('HTML publish readiness: $statusLabel')
      ..write(' (${blockingIssues.length} blockers, ${warningIssues.length} warnings)');
    if (sourcePath != null && sourcePath!.isNotEmpty) {
      buffer.write(' for $sourcePath');
    }
    final visible = issues.take(maxIssues).toList(growable: false);
    if (visible.isNotEmpty) {
      buffer.writeln();
      for (final issue in visible) {
        final label = switch (issue.severity) {
          HtmlPublishIssueSeverity.blocking => 'BLOCK',
          HtmlPublishIssueSeverity.warning => 'WARN',
          HtmlPublishIssueSeverity.info => 'INFO',
        };
        buffer.writeln('- $label ${issue.code}: ${issue.title}');
      }
    }
    if (issues.length > maxIssues) {
      buffer.writeln('- ${issues.length - maxIssues} more checks omitted from chat summary.');
    }
    return buffer.toString().trim();
  }
}

class HtmlPublishReadinessService {
  Future<HtmlPublishReadinessReport> checkFile(
    String path, {
    bool allowRemoteAssets = false,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return HtmlPublishReadinessReport(
        sourcePath: path,
        checkedAt: DateTime.now(),
        allowRemoteAssets: allowRemoteAssets,
        issues: const [
          HtmlPublishIssue(
            code: 'file_missing',
            title: 'Generated HTML file is missing',
            detail: 'MobileCode could not find the generated index.html on this phone.',
            severity: HtmlPublishIssueSeverity.blocking,
          ),
        ],
      );
    }

    final html = await file.readAsString();
    return checkHtml(
      html,
      sourcePath: path,
      allowRemoteAssets: allowRemoteAssets,
    );
  }

  HtmlPublishReadinessReport checkHtml(
    String html, {
    String? sourcePath,
    bool allowRemoteAssets = false,
  }) {
    final issues = <HtmlPublishIssue>[];
    final lower = html.toLowerCase();

    if (html.trim().isEmpty) {
      issues.add(const HtmlPublishIssue(
        code: 'empty_html',
        title: 'HTML is empty',
        detail: 'The generated artifact has no HTML content to publish.',
        severity: HtmlPublishIssueSeverity.blocking,
      ));
    }

    if (!_looksLikeHtml(lower)) {
      issues.add(const HtmlPublishIssue(
        code: 'not_html',
        title: 'Artifact does not look like HTML',
        detail: 'Publish expects a complete HTML document with recognizable html, body, or doctype markers.',
        severity: HtmlPublishIssueSeverity.blocking,
      ));
    }

    if (!_hasNonEmptyTitle(html)) {
      issues.add(const HtmlPublishIssue(
        code: 'missing_title',
        title: 'Missing document title',
        detail: 'Add a non-empty <title> so the published GitHub Pages tab has a readable name.',
        severity: HtmlPublishIssueSeverity.blocking,
      ));
    }

    if (!_hasViewportMeta(html)) {
      issues.add(const HtmlPublishIssue(
        code: 'missing_viewport',
        title: 'Missing mobile viewport',
        detail: 'Add <meta name="viewport" content="width=device-width, initial-scale=1.0"> for phone-sized screens.',
        severity: HtmlPublishIssueSeverity.blocking,
      ));
    }

    if (_containsPrivateDevicePath(html)) {
      issues.add(const HtmlPublishIssue(
        code: 'private_path_leak',
        title: 'App-private phone path leaked into HTML',
        detail: 'Remove /data/user/0, file:///data/user/0, or Android app-private paths before publishing.',
        severity: HtmlPublishIssueSeverity.blocking,
      ));
    }

    final externalRefs = _externalReferences(html);
    if (externalRefs.isNotEmpty && !allowRemoteAssets) {
      issues.add(HtmlPublishIssue(
        code: 'remote_references',
        title: 'Remote links or assets detected',
        detail:
            'Found ${externalRefs.length} external reference(s). Keep generated demos self-contained, or explicitly allow remote assets before publishing.',
        severity: HtmlPublishIssueSeverity.warning,
      ));
    }

    if (_hasImagesWithoutAlt(html)) {
      issues.add(const HtmlPublishIssue(
        code: 'missing_image_alt',
        title: 'Image alt text is missing',
        detail: 'Every <img> should include alt text so the page has basic accessibility.',
        severity: HtmlPublishIssueSeverity.warning,
      ));
    }

    if (_hasUnnamedInteractiveControls(html)) {
      issues.add(const HtmlPublishIssue(
        code: 'unnamed_controls',
        title: 'Interactive controls need labels',
        detail: 'Buttons and links should have readable text, aria-label, or title for assistive technology.',
        severity: HtmlPublishIssueSeverity.warning,
      ));
    }

    if (_hasInteractiveControls(html) && !_hasTouchTargetHints(lower)) {
      issues.add(const HtmlPublishIssue(
        code: 'touch_targets_unclear',
        title: 'Touch target sizing is unclear',
        detail: 'Add button/link padding or min-height around 44px so controls are comfortable on phones.',
        severity: HtmlPublishIssueSeverity.warning,
      ));
    }

    if (!_hasSemanticStructure(lower)) {
      issues.add(const HtmlPublishIssue(
        code: 'semantic_structure',
        title: 'Semantic page structure is thin',
        detail: 'Use main, section, header, nav, or footer to make the generated page easier to inspect and navigate.',
        severity: HtmlPublishIssueSeverity.warning,
      ));
    }

    return HtmlPublishReadinessReport(
      sourcePath: sourcePath,
      checkedAt: DateTime.now(),
      allowRemoteAssets: allowRemoteAssets,
      issues: List.unmodifiable(issues),
    );
  }

  bool _looksLikeHtml(String lower) {
    return lower.contains('<!doctype html') ||
        lower.contains('<html') ||
        lower.contains('<body') ||
        lower.contains('<main') ||
        lower.contains('<section');
  }

  bool _hasNonEmptyTitle(String html) {
    final match = RegExp(r'<title\b[^>]*>([\s\S]*?)<\/title>', caseSensitive: false).firstMatch(html);
    final value = match?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    return value != null && value.isNotEmpty;
  }

  bool _hasViewportMeta(String html) {
    return RegExp(
      r'''<meta\b(?=[^>]*\bname\s*=\s*["']viewport["'])(?=[^>]*\bcontent\s*=)[^>]*>''',
      caseSensitive: false,
    ).hasMatch(html);
  }

  bool _containsPrivateDevicePath(String html) {
    return RegExp(
      r'(file:\/\/\/data\/user\/0\/|\/data\/user\/0\/|\/storage\/emulated\/0\/Android\/data\/)',
      caseSensitive: false,
    ).hasMatch(html);
  }

  List<String> _externalReferences(String html) {
    final refs = <String>[];
    final attrRegex = RegExp(
      r'''(?:src|href)\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in attrRegex.allMatches(html)) {
      final value = match.group(1)?.trim() ?? '';
      if (value.startsWith('http://') || value.startsWith('https://') || value.startsWith('//')) {
        refs.add(value);
      }
    }
    return refs;
  }

  bool _hasImagesWithoutAlt(String html) {
    final imgRegex = RegExp(r'<img\b[^>]*>', caseSensitive: false);
    for (final match in imgRegex.allMatches(html)) {
      final tag = match.group(0) ?? '';
      if (!RegExp(r'\balt\s*=', caseSensitive: false).hasMatch(tag)) return true;
    }
    return false;
  }

  bool _hasUnnamedInteractiveControls(String html) {
    final buttonRegex = RegExp(r'<button\b([^>]*)>([\s\S]*?)<\/button>', caseSensitive: false);
    for (final match in buttonRegex.allMatches(html)) {
      final attrs = match.group(1) ?? '';
      final text = _stripTags(match.group(2) ?? '').trim();
      if (text.isEmpty && !_hasAccessibleName(attrs)) return true;
    }

    final linkRegex = RegExp(r'<a\b([^>]*)>([\s\S]*?)<\/a>', caseSensitive: false);
    for (final match in linkRegex.allMatches(html)) {
      final attrs = match.group(1) ?? '';
      final text = _stripTags(match.group(2) ?? '').trim();
      if (text.isEmpty && !_hasAccessibleName(attrs)) return true;
    }

    return false;
  }

  bool _hasAccessibleName(String attrs) {
    return RegExp(r'''\b(aria-label|title)\s*=\s*["'][^"']+["']''', caseSensitive: false).hasMatch(attrs);
  }

  bool _hasInteractiveControls(String html) {
    return RegExp(r'''<(button|a)\b|\brole\s*=\s*["']button["']''', caseSensitive: false).hasMatch(html);
  }

  bool _hasTouchTargetHints(String lower) {
    return RegExp(r'min-(height|width)\s*:\s*(4[4-9]|[5-9]\d)px').hasMatch(lower) ||
        RegExp(r'padding\s*:\s*([^;]*(1[0-9]|[2-9]\d)px)').hasMatch(lower) ||
        lower.contains('touch-action');
  }

  bool _hasSemanticStructure(String lower) {
    return RegExp(r'<(main|section|header|nav|footer|article)\b').hasMatch(lower);
  }

  String _stripTags(String value) => value.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ');
}
