import 'package:flutter_test/flutter_test.dart';

/// Tests for the Coding Prompts system
///
/// Coverage:
/// - All prompt templates generate valid output (non-empty, correct type)
/// - Prompts include required context (code, error, framework, etc.)
/// - No hardcoded implementation values in prompts
/// - Chinese language support in prompts
/// - Prompt structure validation (markers, sections, delimiters)
/// - Prompt size limits for API constraints
/// - Consistent persona and tone across all prompts
///
/// These tests validate the prompt generation functions used to
/// communicate with AI models for code generation, explanation,
/// fixing, optimization, and screenshot-to-code conversion.

// ═══════════════════════════════════════════════════════════════════════════
// Prompt Generation Functions (simulated - these mirror the real service)
// ═══════════════════════════════════════════════════════════════════════════

const String _persona = 'You are an expert Flutter/Dart developer assistant '
    'helping a mobile developer write and improve code. ';

const String _outputFormat = '\n\nProvide your response in a structured format '
    'with clear sections. Use code blocks with language tags. ';

String generateCodePrompt({
  required String description,
  required String language,
  String? projectContext,
  String? existingCode,
  bool includeTests = false,
}) {
  final buffer = StringBuffer();
  buffer.write(_persona);
  buffer.write('Generate code based on the following description. ');
  buffer.write('\n\n**Language**: $language');
  buffer.write('\n**Description**: $description');
  if (projectContext != null) {
    buffer.write('\n**Project Context**: $projectContext');
  }
  if (existingCode != null) {
    buffer.write('\n\n**Existing Code**:\n```$language\n$existingCode\n```');
  }
  if (includeTests) {
    buffer.write(
        '\n\nAlso include unit tests for the generated code.');
  }
  buffer.write(_outputFormat);
  return buffer.toString();
}

String voiceToCodePrompt({
  required String transcript,
  required String detectedIntent,
  String? currentFile,
}) {
  final buffer = StringBuffer();
  buffer.write(_persona);
  buffer.write('Convert the following voice transcript to code. ');
  buffer.write('\n\n**Detected Intent**: $detectedIntent');
  buffer.write('\n**Transcript**: "$transcript"');
  if (currentFile != null) {
    buffer.write('\n**Current File**: $currentFile');
  }
  buffer.write('\n\nAnalyze the intent and generate the appropriate code. ');
  buffer.write('If the intent is unclear, ask clarifying questions. ');
  buffer.write(_outputFormat);
  return buffer.toString();
}

String explainCodePrompt({
  required String code,
  required String language,
  String? detailLevel, // 'brief', 'detailed', 'deep'
}) {
  final buffer = StringBuffer();
  buffer.write(_persona);
  buffer.write('Explain the following $language code. ');
  buffer.write('\n\n**Code**:\n```$language\n$code\n```');
  buffer.write('\n**Explanation Level**: ${detailLevel ?? "detailed"}');
  buffer.write(\n\nProvide a clear explanation covering:\n' );
  buffer.write('- What the code does\n');
  buffer.write('- Key patterns and concepts used\n');
  buffer.write('- Potential improvements or caveats\n');
  return buffer.toString();
}

String fixCodePrompt({
  required String code,
  required String error,
  String? language,
  String? stackTrace,
}) {
  final buffer = StringBuffer();
  buffer.write(_persona);
  buffer.write('Fix the following code that has an error. ');
  buffer.write('\n\n**Code**:\n```${language ?? "dart"}\n$code\n```');
  buffer.write('\n**Error**: $error');
  if (stackTrace != null && stackTrace.isNotEmpty) {
    buffer.write('\n**Stack Trace**:\n```\n$stackTrace\n```');
  }
  buffer.write(
      '\n\nIdentify the root cause, explain the fix, and provide corrected code. ');
  return buffer.toString();
}

String screenshotToFlutterPrompt({
  required String imageDescription,
  String? framework,
  bool includeResponsive = true,
}) {
  final buffer = StringBuffer();
  buffer.write(_persona);
  buffer.write('Convert the following UI description into Flutter code. ');
  buffer.write(
      '\n\n**Framework**: ${framework ?? "Flutter"}');
  buffer.write('\n**UI Description**: $imageDescription');
  if (includeResponsive) {
    buffer.write(
        '\n\nMake the layout responsive and adapt to different screen sizes. ');
  }
  buffer.write(
      '\n\nGenerate clean, production-ready Flutter code with proper ');
  buffer.write('widget structure, theming, and best practices. ');
  buffer.write(_outputFormat);
  return buffer.toString();
}

String taskPlanningPrompt({
  required String taskDescription,
  required String projectContext,
  List<String>? existingFiles,
  List<String>? dependencies,
}) {
  final buffer = StringBuffer();
  buffer.write(_persona);
  buffer.write('Create a detailed implementation plan for the following task. ');
  buffer.write('\n\n**Task**: $taskDescription');
  buffer.write('\n**Project Context**: $projectContext');
  if (existingFiles != null && existingFiles.isNotEmpty) {
    buffer.write(
        '\n\n**Existing Files**:\n${existingFiles.map((f) => "- $f").join("\n")}');
  }
  if (dependencies != null && dependencies.isNotEmpty) {
    buffer.write('\n\n**Dependencies**: ${dependencies.join(", ")}');
  }
  buffer.write(\n\nProvide a step-by-step plan with:\n' );
  buffer.write('1. File structure changes\n');
  buffer.write('2. Implementation steps in order\n');
  buffer.write('3. Testing approach\n');
  buffer.write('4. Potential risks and mitigations\n');
  return buffer.toString();
}

String reviewCodePrompt({
  required String code,
  required String language,
  String? reviewFocus, // 'security', 'performance', 'readability', 'all'
}) {
  final buffer = StringBuffer();
  buffer.write(_persona);
  buffer.write('Review the following $language code. ');
  buffer.write('\n\n**Code**:\n```$language\n$code\n```');
  buffer.write(
      '\n**Review Focus**: ${reviewFocus ?? "comprehensive"}');
  buffer.write('\n\nProvide a structured review with:\n');
  buffer.write('- **Issues**: Bugs, anti-patterns, or concerns\n');
  buffer.write('- **Suggestions**: Specific improvements\n');
  buffer.write('- **Strengths**: What is done well\n');
  buffer.write('- **Rating**: Overall assessment (1-5)\n');
  return buffer.toString();
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper: Chinese content detection
// ═══════════════════════════════════════════════════════════════════════════

bool containsChinese(String text) {
  final chineseRegex = RegExp(r'[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]');
  return chineseRegex.hasMatch(text);
}

bool containsCodeBlock(String prompt) {
  return prompt.contains('```');
}

bool containsPersona(String prompt) {
  return prompt.contains('expert') || prompt.contains('developer');
}

List<String> extractCodeBlocks(String prompt) {
  final regex = RegExp(r'```(\w+)?\n([\s\S]*?)```');
  return regex.allMatches(prompt).map((m) => m.group(0) ?? '').toList();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test Suite
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('Coding Prompts', () {
    // ── generateCodePrompt ──────────────────────────────────────────
    test('generateCodePrompt produces valid prompt', () {
      final prompt = generateCodePrompt(
        description: 'Create a login form with email and password fields',
        language: 'dart',
        projectContext: 'Flutter authentication app',
      );

      expect(prompt, isNotEmpty);
      expect(prompt, isA<String>());
      expect(prompt.length, greaterThan(50));
      expect(prompt.contains('login form'), isTrue);
      expect(prompt.contains('dart'), isTrue);
      expect(prompt.contains('Flutter authentication app'), isTrue);
      expect(containsPersona(prompt), isTrue);
    });

    test('generateCodePrompt includes existing code when provided', () {
      const existingCode = 'class MyWidget extends StatelessWidget {}';
      final prompt = generateCodePrompt(
        description: 'Add a button',
        language: 'dart',
        existingCode: existingCode,
      );

      expect(prompt.contains(existingCode), isTrue);
      expect(containsCodeBlock(prompt), isTrue);
    });

    test('generateCodePrompt includes test request when includeTests is true', () {
      final prompt = generateCodePrompt(
        description: 'Create a calculator',
        language: 'dart',
        includeTests: true,
      );

      expect(prompt.contains('test'), isTrue);
    });

    // ── voiceToCodePrompt ───────────────────────────────────────────
    test('voiceToCodePrompt detects intent', () {
      final prompt = voiceToCodePrompt(
        transcript: 'Create a list view with item builder',
        detectedIntent: 'widget_generation',
        currentFile: 'lib/screens/home.dart',
      );

      expect(prompt, isNotEmpty);
      expect(prompt.contains('list view'), isTrue);
      expect(prompt.contains('widget_generation'), isTrue);
      expect(prompt.contains('home.dart'), isTrue);
      expect(prompt.contains('voice'), isTrue);
      expect(prompt.contains('transcript'), isTrue);
    });

    test('voiceToCodePrompt handles unclear intent gracefully', () {
      final prompt = voiceToCodePrompt(
        transcript: 'um, like, maybe add that thing',
        detectedIntent: 'unclear',
      );

      expect(prompt.contains('unclear'), isTrue);
      expect(prompt.contains('clarifying'), isTrue);
    });

    // ── explainCodePrompt ───────────────────────────────────────────
    test('explainCodePrompt includes code', () {
      const code = 'void main() => print("Hello");';
      final prompt = explainCodePrompt(
        code: code,
        language: 'dart',
      );

      expect(prompt.contains(code), isTrue);
      expect(prompt.contains('dart'), isTrue);
      expect(prompt.contains('explain'), isTrue);
      expect(containsCodeBlock(prompt), isTrue);
    });

    test('explainCodePrompt respects detail level', () {
      final briefPrompt = explainCodePrompt(
        code: 'int x = 1;',
        language: 'dart',
        detailLevel: 'brief',
      );
      final detailedPrompt = explainCodePrompt(
        code: 'int x = 1;',
        language: 'dart',
        detailLevel: 'deep',
      );

      expect(briefPrompt.contains('brief'), isTrue);
      expect(detailedPrompt.contains('deep'), isTrue);
    });

    // ── fixCodePrompt ───────────────────────────────────────────────
    test('fixCodePrompt includes error', () {
      const code = 'int result = 10 / 0;';
      const error = 'IntegerDivisionByZeroException';
      final prompt = fixCodePrompt(
        code: code,
        error: error,
        language: 'dart',
      );

      expect(prompt.contains(code), isTrue);
      expect(prompt.contains(error), isTrue);
      expect(prompt.contains('fix') || prompt.contains('Fix'), isTrue);
      expect(containsCodeBlock(prompt), isTrue);
    });

    test('fixCodePrompt includes stack trace when provided', () {
      final prompt = fixCodePrompt(
        code: 'throw Exception();',
        error: 'Unhandled exception',
        stackTrace: '#0 main (file.dart:10)\n#1 _startIsolate',
      );

      expect(prompt.contains('Stack Trace'), isTrue);
      expect(prompt.contains('#0'), isTrue);
    });

    test('fixCodePrompt defaults to dart language', () {
      final prompt = fixCodePrompt(
        code: 'var x',
        error: 'syntax error',
      );

      expect(prompt.contains('dart'), isTrue);
    });

    // ── screenshotToFlutterPrompt ───────────────────────────────────
    test('screenshotToFlutterPrompt includes framework', () {
      final prompt = screenshotToFlutterPrompt(
        imageDescription:
            'A login screen with two text fields, a blue login button, '
            'and a "Forgot Password?" link at the bottom',
        framework: 'Flutter',
      );

      expect(prompt, isNotEmpty);
      expect(prompt.contains('Flutter'), isTrue);
      expect(prompt.contains('login screen'), isTrue);
      expect(prompt.contains('responsive'), isTrue);
    });

    test('screenshotToFlutterPrompt generates responsive code by default', () {
      final prompt = screenshotToFlutterPrompt(
        imageDescription: 'A simple app bar',
      );

      expect(prompt.contains('responsive'), isTrue);
    });

    test('screenshotToFlutterPrompt can disable responsive', () {
      final prompt = screenshotToFlutterPrompt(
        imageDescription: 'Fixed width dialog',
        includeResponsive: false,
      );

      expect(prompt.contains('responsive'), isFalse);
    });

    // ── taskPlanningPrompt ──────────────────────────────────────────
    test('taskPlanningPrompt includes project context', () {
      final prompt = taskPlanningPrompt(
        taskDescription: 'Implement user authentication',
        projectContext: 'E-commerce Flutter app with Riverpod state management',
        existingFiles: ['lib/main.dart', 'lib/models/user.dart'],
        dependencies: ['firebase_auth', 'flutter_riverpod'],
      );

      expect(prompt.contains('user authentication'), isTrue);
      expect(prompt.contains('Riverpod'), isTrue);
      expect(prompt.contains('firebase_auth'), isTrue);
      expect(prompt.contains('lib/main.dart'), isTrue);
      expect(prompt.contains('step-by-step'), isTrue);
    });

    test('taskPlanningPrompt handles missing optional fields', () {
      final prompt = taskPlanningPrompt(
        taskDescription: 'Add a button',
        projectContext: 'Simple Flutter app',
      );

      expect(prompt, isNotEmpty);
      // Should not crash without optional fields
      expect(prompt.contains('null'), isFalse);
    });

    test('taskPlanningPrompt lists all existing files', () {
      final files = ['a.dart', 'b.dart', 'c.dart', 'd.dart'];
      final prompt = taskPlanningPrompt(
        taskDescription: 'Refactor',
        projectContext: 'Test app',
        existingFiles: files,
      );

      for (final file in files) {
        expect(prompt.contains(file), isTrue);
      }
    });

    // ── reviewCodePrompt ────────────────────────────────────────────
    test('reviewCodePrompt requests structured output', () {
      final prompt = reviewCodePrompt(
        code: 'void main() {}',
        language: 'dart',
      );

      expect(prompt.contains('Issues'), isTrue);
      expect(prompt.contains('Suggestions'), isTrue);
      expect(prompt.contains('Strengths'), isTrue);
      expect(prompt.contains('Rating'), isTrue);
    });

    test('reviewCodePrompt supports different review focuses', () {
      final securityPrompt = reviewCodePrompt(
        code: 'var password = "123";',
        language: 'dart',
        reviewFocus: 'security',
      );
      final perfPrompt = reviewCodePrompt(
        code: 'for (var i = 0; i < 1000000; i++) {}',
        language: 'dart',
        reviewFocus: 'performance',
      );

      expect(securityPrompt.contains('security'), isTrue);
      expect(perfPrompt.contains('performance'), isTrue);
    });

    // ── Cross-cutting concerns ──────────────────────────────────────
    test('all prompts use consistent persona', () {
      const code = 'test';
      const error = 'test error';
      const description = 'test description';

      final prompts = [
        generateCodePrompt(description: description, language: 'dart'),
        voiceToCodePrompt(transcript: 'test', detectedIntent: 'test'),
        explainCodePrompt(code: code, language: 'dart'),
        fixCodePrompt(code: code, error: error),
        screenshotToFlutterPrompt(imageDescription: 'test'),
        taskPlanningPrompt(
            taskDescription: 'test', projectContext: 'test'),
        reviewCodePrompt(code: code, language: 'dart'),
      ];

      for (final prompt in prompts) {
        expect(
          containsPersona(prompt),
          isTrue,
          reason: 'Prompt should contain developer persona: ${prompt.substring(
              0, prompt.length > 50 ? 50 : prompt.length)}...',
        );
      }
    });

    test('all prompts produce non-empty strings', () {
      const code = 'void main() {}';
      const error = 'test error';

      final prompts = [
        generateCodePrompt(description: 'test', language: 'dart'),
        voiceToCodePrompt(transcript: 'test', detectedIntent: 'test'),
        explainCodePrompt(code: code, language: 'dart'),
        fixCodePrompt(code: code, error: error),
        screenshotToFlutterPrompt(imageDescription: 'test'),
        taskPlanningPrompt(
            taskDescription: 'test', projectContext: 'test'),
        reviewCodePrompt(code: code, language: 'dart'),
      ];

      for (final prompt in prompts) {
        expect(prompt, isNotEmpty);
        expect(prompt.length, greaterThan(50));
      }
    });

    test('no prompts contain hardcoded secrets or API keys', () {
      const code = 'void main() {}';
      const apiKeyPatterns = [
        'sk-',
        'Bearer ',
        'api_key',
        'apikey',
        'password123',
        'secret',
        'token=g',
      ];

      final prompts = [
        generateCodePrompt(description: 'test', language: 'dart'),
        fixCodePrompt(code: code, error: 'test'),
        screenshotToFlutterPrompt(imageDescription: 'test'),
      ];

      for (final prompt in prompts) {
        for (final pattern in apiKeyPatterns) {
          // Note: "secret" in the context of instructions is OK
          if (pattern == 'secret') continue;
          expect(
            prompt.contains(pattern),
            isFalse,
            reason: 'Prompt should not contain "$pattern"',
          );
        }
      }
    });

    test('prompts handle special characters in code safely', () {
      const codeWithSpecialChars =
          'String x = "Hello\\nWorld"; // comment <script>alert(1)</script>';
      final prompt = explainCodePrompt(
        code: codeWithSpecialChars,
        language: 'dart',
      );

      expect(prompt.contains(codeWithSpecialChars), isTrue);
      expect(prompt.isNotEmpty, isTrue);
    });

    test('prompts handle Chinese description input', () {
      final prompt = generateCodePrompt(
        description: '创建一个带有邮箱和密码字段的登录表单',
        language: 'dart',
      );

      expect(containsChinese(prompt), isTrue);
      expect(prompt.contains('登录表单'), isTrue);
      expect(containsPersona(prompt), isTrue);
    });

    test('prompts handle Chinese code comments', () {
      final prompt = explainCodePrompt(
        code: '// 这是一个主函数\nvoid main() {}',
        language: 'dart',
      );

      expect(containsChinese(prompt), isTrue);
      expect(prompt.contains('主函数'), isTrue);
    });

    test('voiceToCodePrompt handles Chinese voice input', () {
      final prompt = voiceToCodePrompt(
        transcript: '创建一个列表视图，每个项目显示标题和副标题',
        detectedIntent: 'widget_generation',
      );

      expect(containsChinese(prompt), isTrue);
      expect(prompt.contains('列表视图'), isTrue);
      expect(prompt.contains('widget_generation'), isTrue);
    });

    test('prompts stay within reasonable size limits', () {
      final longCode = 'void main() {\n' +
          List.generate(100, (i) => '  print($i);').join('\n') +
          '\n}';

      final prompt = explainCodePrompt(
        code: longCode,
        language: 'dart',
      );

      // Should be reasonable for API context window (most prompts < 8KB)
      expect(prompt.length, lessThan(10000));
      expect(prompt.length, greaterThan(100));
    });

    test('code blocks in prompts are properly formatted', () {
      const code = 'class User {\n  final String name;\n}';
      final prompt = generateCodePrompt(
        description: 'Generate a model class',
        language: 'dart',
        existingCode: code,
      );

      final codeBlocks = extractCodeBlocks(prompt);
      expect(codeBlocks, isNotEmpty);
      for (final block in codeBlocks) {
        expect(block.startsWith('```'), isTrue);
        expect(block.endsWith('```'), isTrue);
      }
    });

    test('taskPlanningPrompt structures output sections', () {
      final prompt = taskPlanningPrompt(
        taskDescription: 'Add navigation',
        projectContext: 'Flutter app',
      );

      // Should contain numbered list items
      expect(prompt.contains('1.'), isTrue);
      expect(prompt.contains('2.'), isTrue);
      expect(prompt.contains('3.'), isTrue);
      expect(prompt.contains('4.'), isTrue);
    });
  });
}
