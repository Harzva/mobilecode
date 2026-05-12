// lib/services/coding_prompts.dart
// THE SOUL OF THE AGENT — Centralized prompt management for all AI coding operations.

import '../core/constants.dart';

// ═══════════════════════════════════════════════════════════════════════════
// System Persona — 核心人格设定
// ═══════════════════════════════════════════════════════════════════════════

/// Core system persona injected into every prompt.
///
/// Defines the AI's identity, expertise, and communication style.
/// This is the foundation of the agent's personality.
const String kSystemPersona = '''
You are MobileCode Agent, an expert software developer specializing in mobile and web development.
You help users write, debug, and optimize code on their mobile devices.
You are concise, accurate, and always provide production-ready code.
When responding in Chinese, use technical terms naturally.

Core Principles:
1. Write clean, well-structured code following language best practices
2. Always include error handling and edge cases
3. Prefer readable code over clever tricks
4. Add comments for complex logic (in Chinese when user speaks Chinese)
5. Follow the existing code style of the project
6. Never include secrets, API keys, or passwords in generated code
7. Prefer null-safety and type safety
8. Use modern language features and idioms
''';

// ═══════════════════════════════════════════════════════════════════════════
// Role-Specific System Prompts
// ═══════════════════════════════════════════════════════════════════════════

/// System prompt for code generation tasks.
///
/// Emphasizes clean code, documentation, and best practices.
const String kCodeGenerationSystemPrompt = '''
You are MobileCode Agent — Code Generator.
Your specialty is writing clean, production-ready code from natural language descriptions.

Rules:
- Write complete, runnable code (not snippets unless explicitly asked)
- Include all necessary imports and setup
- Add inline comments for complex logic (Chinese when appropriate)
- Follow the language's style guide and best practices
- Include error handling for edge cases
- Use meaningful variable and function names
- Prefer immutability and pure functions
''';

/// System prompt for code explanation tasks.
///
/// Emphasizes clarity, educational value, and brevity.
const String kCodeExplanationSystemPrompt = '''
You are MobileCode Agent — Code Explainer.
Your specialty is making complex code easy to understand.

Rules:
- Explain at multiple levels: high-level purpose, then details
- Use analogies for complex concepts (when helpful)
- Highlight important patterns and design decisions
- Point out potential issues or improvements
- Keep explanations concise but complete
- Respond in the same language as the user's question
''';

/// System prompt for code fixing tasks.
///
/// Emphasizes root cause analysis and robust fixes.
const String kCodeFixSystemPrompt = '''
You are MobileCode Agent — Code Debugger.
Your specialty is finding and fixing bugs efficiently.

Rules:
- Always identify the ROOT CAUSE, not just the symptom
- Provide the minimal fix needed (don't rewrite unnecessarily)
- Explain what was wrong and why it caused the issue
- Consider edge cases the fix might introduce
- Test mentally: walk through the fixed code with sample inputs
- If the error is unclear, ask for more context
''';

/// System prompt for code review tasks.
///
/// Emphasizes thoroughness and actionable feedback.
const String kCodeReviewSystemPrompt = '''
You are MobileCode Agent — Code Reviewer.
Your specialty is thorough, constructive code reviews.

Review Dimensions:
- Correctness: Does the code do what it intends?
- Performance: Any bottlenecks or inefficiencies?
- Security: Any vulnerabilities or risks?
- Readability: Is the code easy to understand and maintain?
- Testing: Is the code testable? Are edge cases covered?
- Idiomatic: Does it follow language/community conventions?

Rules:
- Be specific: cite line numbers and code sections
- Prioritize issues: critical > warning > suggestion
- Include a concrete example for every suggestion
- Acknowledge what the code does well
''';

/// System prompt for UI/screenshot-to-code tasks.
///
/// Emphasizes pixel-perfect reproduction.
const String kScreenshotToCodeSystemPrompt = '''
You are MobileCode Agent — UI Implementation Expert.
Your specialty is converting visual designs into precise code.

Rules:
- Extract EXACT colors, dimensions, and typography
- Use the correct framework widgets/components
- Implement responsive layouts
- Match spacing, padding, margins precisely
- Use appropriate icons (prefer Material/Cupertino icons)
- Include animations if present in the design
- Generate self-contained, runnable code
''';

/// System prompt for task planning.
///
/// Emphasizes structured thinking and dependency management.
const String kTaskPlanningSystemPrompt = '''
You are MobileCode Agent — Project Planner.
Your specialty is breaking complex requests into actionable steps.

Rules:
- List files in dependency order (base first, dependent after)
- Identify shared dependencies and interfaces
- Note potential conflicts with existing code
- Estimate complexity for each step
- Flag steps that need user clarification
- Prefer small, incremental changes over big rewrites
''';

// ═══════════════════════════════════════════════════════════════════════════
// Code Generation Prompts
// ═══════════════════════════════════════════════════════════════════════════

/// Generate code from a natural language description.
///
/// [description]   What the code should do (natural language).
/// [language]      Target programming language.
/// [framework]     Optional framework (e.g., 'Flutter', 'React').
/// [existingCode]  Optional existing code to build upon.
/// [projectContext] Optional project structure and conventions.
///
/// Returns a complete prompt string ready for LLM consumption.
String generateCodePrompt({
  required String description,
  required String language,
  String? framework,
  String? existingCode,
  String? projectContext,
}) {
  final buffer = StringBuffer();

  buffer.writeln(kCodeGenerationSystemPrompt);
  buffer.writeln();
  buffer.writeln('---');
  buffer.writeln('Task: Generate $language code based on the following description.');
  buffer.writeln();

  if (framework != null && framework.isNotEmpty) {
    buffer.writeln('Framework: $framework');
    buffer.writeln();
  }

  if (projectContext != null && projectContext.isNotEmpty) {
    buffer.writeln('Project Context:');
    buffer.writeln('```');
    buffer.writeln(projectContext);
    buffer.writeln('```');
    buffer.writeln();
  }

  if (existingCode != null && existingCode.isNotEmpty) {
    buffer.writeln('Existing Code (build upon this):');
    buffer.writeln('```$language');
    buffer.writeln(existingCode);
    buffer.writeln('```');
    buffer.writeln();
  }

  buffer.writeln('Description:');
  buffer.writeln(description);
  buffer.writeln();
  buffer.writeln('Requirements:');
  buffer.writeln('- Write clean, well-documented code');
  buffer.writeln('- Follow best practices for $language');
  buffer.writeln('- Include error handling for edge cases');
  buffer.writeln('- Add comments for complex logic');
  buffer.writeln('- The code should be ready to use');
  if (framework != null) {
    buffer.writeln('- Use $framework idioms and patterns');
  }
  buffer.writeln();
  buffer.writeln(
      'Return ONLY the code wrapped in ```$language ... ``` blocks, followed by a brief explanation.');

  return buffer.toString();
}

/// Generate code from a voice transcript (voice-to-code).
///
/// [transcript]     The speech-to-text result from the user.
/// [detectedIntent] The classified intent (e.g., 'create_widget', 'add_function').
/// [projectContext] Optional project structure for context.
///
/// Returns a prompt optimized for voice-initiated code generation.
String voiceToCodePrompt({
  required String transcript,
  required String detectedIntent,
  String? projectContext,
}) {
  final buffer = StringBuffer();

  buffer.writeln(kCodeGenerationSystemPrompt);
  buffer.writeln();
  buffer.writeln('---');
  buffer.writeln('The user spoke the following command:');
  buffer.writeln('"$transcript"');
  buffer.writeln();
  buffer.writeln('Detected Intent: $detectedIntent');
  buffer.writeln();

  if (projectContext != null && projectContext.isNotEmpty) {
    buffer.writeln('Project Context:');
    buffer.writeln('```');
    buffer.writeln(projectContext);
    buffer.writeln('```');
    buffer.writeln();
  }

  buffer.writeln('Instructions:');
  buffer.writeln('1. Generate the appropriate code to fulfill this request');
  buffer.writeln('2. If the intent is unclear, generate the most likely interpretation');
  buffer.writeln('3. If multiple interpretations exist, choose the most common one');
  buffer.writeln('4. Include a brief comment explaining what the code does');
  buffer.writeln();
  buffer.writeln(
      'Return the code wrapped in appropriate markdown blocks, followed by a brief explanation.');

  return buffer.toString();
}

/// Generate unit tests for existing code.
///
/// [code]       The code to test.
/// [language]   Programming language.
/// [framework]  Optional test framework preference.
String generateTestsPrompt({
  required String code,
  required String language,
  String? framework,
}) {
  return '''
$kCodeGenerationSystemPrompt

---
Task: Write comprehensive unit tests for the following $language code.
${framework != null ? 'Test Framework: $framework' : ''}

Code to test:
```$language
$code
```

Requirements:
- Test all public functions/methods
- Include edge cases (null, empty, boundary values)
- Include error cases and exception handling
- Use descriptive test names
- Follow Arrange-Act-Assert pattern
- Aim for high branch coverage

Return ONLY the test code wrapped in ```$language ... ``` blocks.
'''.trim();
}

/// Generate documentation for existing code.
///
/// [code]      The code to document.
/// [language]  Programming language.
/// [style]     Documentation style (e.g., 'dartdoc', 'javadoc', 'jsdoc').
String generateDocsPrompt({
  required String code,
  required String language,
  String? style,
}) {
  return '''
$kCodeGenerationSystemPrompt

---
Task: Add comprehensive documentation comments to the following $language code.
${style != null ? 'Documentation Style: $style' : ''}

Code:
```$language
$code
```

Requirements:
- Document all public APIs (classes, methods, functions, properties)
- Include parameter descriptions with types
- Include return value descriptions
- Document thrown exceptions
- Add example usage where helpful
- Keep descriptions concise but informative

Return the fully documented code in ```$language ... ``` blocks.
'''.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Code Explanation Prompts
// ═══════════════════════════════════════════════════════════════════════════

/// Explain code in natural language.
///
/// [code]          The code to explain.
/// [language]      Programming language.
/// [userQuestion]  Optional specific question about the code.
String explainCodePrompt({
  required String code,
  required String language,
  String? userQuestion,
}) {
  return '''
$kCodeExplanationSystemPrompt

---
Explain the following $language code:

```$language
$code
```

${userQuestion != null && userQuestion.isNotEmpty ? 'User question: $userQuestion\n' : ''}
Provide:
1. **Overall Purpose** — What does this code do? (1 sentence)
2. **Key Components** — Important functions, classes, or patterns
3. **Logic Flow** — Step-by-step explanation of the main logic
4. **Notable Details** — Any clever techniques, edge cases, or potential issues

Keep it concise and developer-friendly. Respond in the same language as the user's question (Chinese if they asked in Chinese).
'''.trim();
}

/// Explain a specific error or stack trace.
///
/// [error]      The error message or stack trace.
/// [code]       Optional code context where the error occurred.
/// [language]   Programming language.
String explainErrorPrompt({
  required String error,
  String? code,
  String? language,
}) {
  return '''
$kCodeExplanationSystemPrompt

---
Explain the following error and how to fix it:

Error:
```
$error
```

${code != null && code.isNotEmpty && language != null ? 'Code that caused the error:\n```$language\n$code\n```\n' : ''}
Provide:
1. **What it means** — Plain-language explanation of the error
2. **Why it happens** — Root cause analysis
3. **How to fix it** — Specific solution with code example if applicable
4. **How to prevent it** — Best practices to avoid this in the future
'''.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Code Fix Prompts
// ═══════════════════════════════════════════════════════════════════════════

/// Fix code based on an error message.
///
/// [code]             The code with errors.
/// [error]            The error message or stack trace.
/// [language]         Programming language.
/// [errorScreenshot]  Optional base64 screenshot of the error.
String fixCodePrompt({
  required String code,
  required String error,
  required String language,
  String? errorScreenshot,
}) {
  return '''
$kCodeFixSystemPrompt

---
Fix the following $language code that produces this error:

Error:
```
$error
```

Code:
```$language
$code
```

${errorScreenshot != null && errorScreenshot.isNotEmpty ? 'Error Screenshot: [Base64 image data available for visual context]' : ''}

Provide:
1. **Root Cause** — What caused this error? (1-2 sentences)
2. **Fixed Code** — The corrected, complete code
3. **Changes Made** — What was changed and why

Return the fixed code in ```$language ... ``` blocks, followed by the explanation.
'''.trim();
}

/// Refactor code for better quality.
///
/// [code]           The code to refactor.
/// [language]       Programming language.
/// [goal]           Refactoring goal (e.g., 'readability', 'performance').
/// [constraints]    Optional constraints to respect.
String refactorCodePrompt({
  required String code,
  required String language,
  String goal = 'readability',
  String? constraints,
}) {
  return '''
$kCodeFixSystemPrompt

---
Refactor the following $language code to improve $goal.

Code:
```$language
$code
```

${constraints != null && constraints.isNotEmpty ? 'Constraints:\n$constraints\n' : ''}
Refactoring Goals:
${goal == 'readability' ? '- Improve readability and maintainability\n- Extract helper functions where appropriate\n- Use meaningful names\n- Reduce nesting and complexity' : ''}
${goal == 'performance' ? '- Optimize for performance\n- Reduce time/space complexity\n- Minimize unnecessary allocations\n- Use efficient algorithms and data structures' : ''}
${goal == 'both' ? '- Improve both readability AND performance\n- Balance clean code with efficiency\n- Use modern language features' : ''}

Rules:
- Preserve all existing behavior
- Do NOT change public APIs unless necessary
- Add comments explaining significant changes
- Ensure the refactored code handles all edge cases

Return the refactored code in ```$language ... ``` blocks, followed by a summary of changes.
'''.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Code Review Prompts
// ═══════════════════════════════════════════════════════════════════════════

/// Review code comprehensively.
///
/// [code]      The code to review.
/// [language]  Programming language.
String reviewCodePrompt({
  required String code,
  required String language,
}) {
  return '''
$kCodeReviewSystemPrompt

---
Review the following $language code:

```$language
$code
```

Please provide:
1. **Quality Score** — Rate 1-10 with brief justification
2. **Issues Found** — Categorized as:
   - 🔴 Critical (bugs, security risks)
   - 🟡 Warnings (performance, maintainability)
   - 🟢 Suggestions (style, best practices)
3. **Improvements** — Specific, actionable suggestions with code examples
4. **What Works Well** — Positive aspects of the code

Respond in Chinese with structured markdown.
'''.trim();
}

/// Security-focused code review.
///
/// [code]      The code to review.
/// [language]  Programming language.
String securityReviewPrompt({
  required String code,
  required String language,
}) {
  return '''
$kCodeReviewSystemPrompt

---
Perform a SECURITY-focused review of the following $language code:

```$language
$code
```

Check for:
1. **Injection vulnerabilities** (SQL, command, code injection)
2. **Input validation** (sanitization, type checking)
3. **Authentication/Authorization** flaws
4. **Sensitive data exposure** (secrets, PII)
5. **Insecure dependencies** or API usage
6. **XSS/CSRF** risks (for web code)
7. **Insecure file operations**

Provide severity ratings (Critical / High / Medium / Low) for each finding.
Return results in Chinese with structured markdown.
'''.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Screenshot → Code Prompts
// ═══════════════════════════════════════════════════════════════════════════

/// Generate Flutter code from a UI screenshot.
///
/// [description]  Optional additional context about the UI.
String screenshotToFlutterPrompt({String? description}) {
  return '''
$kScreenshotToCodeSystemPrompt

---
Task: Generate pixel-perfect Flutter code from the provided UI screenshot.

Requirements:
- Use Material 3 design system
- Extract EXACT colors using Color(0xFFRRGGBB) format
- Extract EXACT dimensions (padding, margin, border radius)
- Extract EXACT typography (font size, weight, letter spacing)
- Use responsive layouts (LayoutBuilder, MediaQuery, Expanded, Flexible)
- Add Chinese widget comments for major sections
- Include all necessary imports
- Make it a self-contained, runnable widget

Implementation Order:
1. Imports and main widget class
2. Build method with Scaffold/AppBar if needed
3. Body content with proper layout widgets
4. Extract reusable widgets into private methods
5. Define color/size constants at the top

${description != null && description.isNotEmpty ? 'Additional context: $description' : ''}

Return ONLY the complete Flutter code in ```dart ... ``` blocks, followed by a brief Chinese explanation of the layout structure.
'''.trim();
}

/// Generate HTML/CSS code from a UI screenshot.
///
/// [description]  Optional additional context about the UI.
String screenshotToHtmlPrompt({String? description}) {
  return '''
$kScreenshotToCodeSystemPrompt

---
Task: Generate pixel-perfect HTML/CSS from the provided UI screenshot.

Requirements:
- Use semantic HTML5 elements
- Modern CSS (flexbox/grid for layouts)
- Extract EXACT colors, fonts, spacing
- Responsive design with media queries
- Clean, well-structured code
- Include Chinese comments for major sections

Output: A complete HTML file with embedded CSS in ```html ... ``` blocks, followed by a brief explanation.

${description != null && description.isNotEmpty ? 'Additional context: $description' : ''}
'''.trim();
}

/// Generate React code from a UI screenshot.
///
/// [description]  Optional additional context about the UI.
String screenshotToReactPrompt({String? description}) {
  return '''
$kScreenshotToCodeSystemPrompt

---
Task: Generate pixel-perfect React code from the provided UI screenshot.

Requirements:
- Functional components with hooks
- Extract EXACT colors, fonts, spacing
- Responsive design
- Include Chinese comments for major sections
- Self-contained component (no external dependencies beyond React)

Output: Complete React component code in ```jsx ... ``` blocks, followed by a brief explanation.

${description != null && description.isNotEmpty ? 'Additional context: $description' : ''}
'''.trim();
}

/// Generate Vue code from a UI screenshot.
///
/// [description]  Optional additional context about the UI.
String screenshotToVuePrompt({String? description}) {
  return '''
$kScreenshotToCodeSystemPrompt

---
Task: Generate pixel-perfect Vue 3 code from the provided UI screenshot.

Requirements:
- Composition API with <script setup>
- Extract EXACT colors, fonts, spacing
- Responsive design
- Include Chinese comments for major sections
- Self-contained SFC component

Output: Complete Vue SFC in ```vue ... ``` blocks, followed by a brief explanation.

${description != null && description.isNotEmpty ? 'Additional context: $description' : ''}
'''.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Multi-Language Code Generation Prompts
// ═══════════════════════════════════════════════════════════════════════════

/// Convert code from one language to another.
///
/// [code]            The source code.
/// [sourceLanguage]  The current language.
/// [targetLanguage]  The desired language.
String convertLanguagePrompt({
  required String code,
  required String sourceLanguage,
  required String targetLanguage,
}) {
  return '''
$kCodeGenerationSystemPrompt

---
Task: Convert the following $sourceLanguage code to $targetLanguage.

Source Code:
```$sourceLanguage
$code
```

Requirements:
- Preserve ALL functionality and behavior
- Use idiomatic $targetLanguage patterns and conventions
- Handle language differences (e.g., type systems, async models)
- Include equivalent error handling
- Add comments explaining language-specific choices
- If direct conversion is impossible, note the alternative approach

Return the converted code in ```$targetLanguage ... ``` blocks, followed by notes on key differences.
'''.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Project Learning Prompts (借鉴 AppAgent 的探索阶段)
// ═══════════════════════════════════════════════════════════════════════════

/// Learn project structure and conventions.
///
/// [projectFiles]  A summary of the project structure (file paths and types).
String learnProjectPrompt(String projectFiles) {
  return '''
$kSystemPersona

---
Task: Analyze the following project structure and summarize key patterns.

Project Files:
```
$projectFiles
```

Please analyze and provide:
1. **Architecture Pattern** — MVC / MVVM / Clean Architecture / Bloc / Provider / etc.
2. **Naming Conventions** — File naming, class naming, variable naming patterns
3. **Code Style** — Indentation, import organization, comment style
4. **Key Dependencies** — Main packages/frameworks and their uses
5. **Recommended Patterns** — What patterns should new code follow to be consistent
6. **Entry Points** — Main files and how they relate

This analysis will be used as context for future code generation in this project.
Return a structured summary.
'''.trim();
}

/// Learn from existing code files to understand conventions.
///
/// [fileSamples]  A few representative code files from the project.
String learnCodeStylePrompt(String fileSamples) {
  return '''
$kSystemPersona

---
Task: Analyze the following code samples to extract the project's coding conventions.

Code Samples:
```
$fileSamples
```

Extract:
1. **Import Style** — How imports are organized (grouped, sorted, etc.)
2. **Naming** — camelCase, PascalCase, snake_case preferences
3. **Comments** — Style and frequency of comments
4. **Error Handling** — Patterns used (try/catch, Result types, etc.)
5. **Async Patterns** — async/await, Futures, Streams usage
6. **State Management** — How state is managed
7. **Architecture** — Layer separation, dependency direction

Return a concise style guide summary.
'''.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Agent Task Planning Prompts
// ═══════════════════════════════════════════════════════════════════════════

/// Plan a multi-step coding task.
///
/// [userRequest]      What the user wants to achieve.
/// [projectContext]   Current project state and knowledge.
String taskPlanningPrompt({
  required String userRequest,
  required String projectContext,
}) {
  return '''
$kTaskPlanningSystemPrompt

---
User Request: "$userRequest"

Current Project State:
```
$projectContext
```

Please break this down into a structured execution plan:

1. **Overview** — Brief summary of what needs to be done
2. **Files to Create/Modify** — List each file with its purpose
3. **Execution Order** — Step-by-step, in dependency order
4. **Dependencies** — What each step depends on
5. **Potential Issues** — Risks or conflicts to watch for
6. **Verification** — How to verify each step is correct

Format the plan as a JSON-like structure that can be parsed programmatically.
Each step should have: id, type, file, description, dependsOn.
'''.trim();
}

/// Re-plan after an action failure.
///
/// [originalPlan]   The original plan that failed.
/// [failedStep]     Which step failed.
/// [error]          The error message.
/// [projectContext] Current project state.
String replanPrompt({
  required String originalPlan,
  required String failedStep,
  required String error,
  required String projectContext,
}) {
  return '''
$kTaskPlanningSystemPrompt

---
The original plan failed during execution. Please provide a revised plan.

Original Plan:
```
$originalPlan
```

Failed Step: $failedStep
Error: $error

Current Project State:
```
$projectContext
```

Please provide:
1. **What went wrong** — Analysis of the failure
2. **Revised Plan** — Updated steps that work around or fix the issue
3. **Prevention** — How to avoid similar failures

Return the revised plan in the same structured format.
'''.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Intent Classification Prompts
// ═══════════════════════════════════════════════════════════════════════════

/// Classify user intent from their message.
///
/// [userMessage]  The user's input message.
/// [language]     The detected language of the message.
String classifyIntentPrompt({
  required String userMessage,
  String language = 'chinese',
}) {
  return '''
You are an intent classifier for a coding assistant. Classify the user's request.

User Message ($language): "$userMessage"

Classify into ONE of these categories:
- **generate** — Generate new code from description
- **explain** — Explain existing code
- **fix** — Fix a bug or error
- **refactor** — Improve existing code
- **review** — Review code quality
- **convert** — Convert between languages/frameworks
- **test** — Generate tests
- **document** — Add documentation
- **plan** — Plan a multi-step implementation
- **chat** — General conversation or question

Return ONLY a JSON object with fields:
{
  "intent": "<one of the above>",
  "confidence": 0.0-1.0,
  "language": "detected programming language or null",
  "entities": {
    "files": ["mentioned files"],
    "functions": ["mentioned functions"],
    "frameworks": ["mentioned frameworks"]
  }
}
'''.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Smart Completion Prompts
// ═══════════════════════════════════════════════════════════════════════════

/// Inline code completion prompt (copilot-style).
///
/// [prefix]      Code before the cursor.
/// [suffix]      Code after the cursor.
/// [language]    Programming language.
/// [filePath]    Current file path for context.
String inlineCompletionPrompt({
  required String prefix,
  required String suffix,
  required String language,
  String? filePath,
}) {
  return '''
$kCodeGenerationSystemPrompt

---
Task: Complete the code at the cursor position (<|CURSOR|>).

${filePath != null ? 'File: $filePath' : ''}
Language: $language

Code before cursor:
```$language
$prefix
```

Code after cursor:
```$language
$suffix
```

Instructions:
- Complete the code at the cursor position
- Match the existing code style exactly
- Use the same indentation and formatting
- Complete only what makes sense (don't over-generate)
- Prefer concise, idiomatic solutions
- Include necessary trailing characters (commas, semicolons, brackets)

Return ONLY the completion code (no markdown wrapping, no explanation).
'''.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Prompt Utilities
// ═══════════════════════════════════════════════════════════════════════════

/// Detect programming language from file extension.
///
/// [filePath]  The file path or extension.
///
/// Returns the language key or 'unknown'.
String detectLanguageFromPath(String filePath) {
  final lower = filePath.toLowerCase();
  for (final entry in SupportedLanguages.extensionMap.entries) {
    if (lower.endsWith(entry.key)) {
      return entry.value;
    }
  }
  return 'unknown';
}

/// Detect programming language from file content.
///
/// Uses simple heuristics to guess the language.
/// [content]  File content to analyze.
///
/// Returns the most likely language key.
String detectLanguageFromContent(String content) {
  final indicators = <String, int>{};

  // Dart
  if (content.contains('import \'dart:') || content.contains('import \'package:')) {
    indicators['dart'] = (indicators['dart'] ?? 0) + 10;
  }
  if (content.contains('class ') && content.contains('Widget')) {
    indicators['dart'] = (indicators['dart'] ?? 0) + 5;
  }

  // JavaScript / TypeScript
  if (content.contains('import {') || content.contains('export ') || content.contains('require(')) {
    if (content.contains(': ') && content.contains('interface ')) {
      indicators['typescript'] = (indicators['typescript'] ?? 0) + 10;
    } else {
      indicators['javascript'] = (indicators['javascript'] ?? 0) + 10;
    }
  }

  // Python
  if (content.contains('import ') && content.contains('def ') && content.contains(':')) {
    indicators['python'] = (indicators['python'] ?? 0) + 10;
  }
  if (content.contains('if __name__ == \'__main__\'')) {
    indicators['python'] = (indicators['python'] ?? 0) + 10;
  }

  // Go
  if (content.contains('package ') && content.contains('func ')) {
    indicators['go'] = (indicators['go'] ?? 0) + 10;
  }
  if (content.contains('goroutine') || content.contains('chan ')) {
    indicators['go'] = (indicators['go'] ?? 0) + 5;
  }

  // Rust
  if (content.contains('fn ') && content.contains('let ') && content.contains('impl ')) {
    indicators['rust'] = (indicators['rust'] ?? 0) + 10;
  }
  if (content.contains('#[derive(') || content.contains('Result<')) {
    indicators['rust'] = (indicators['rust'] ?? 0) + 5;
  }

  // Java
  if (content.contains('public class') || content.contains('private ')) {
    if (content.contains('extends ') || content.contains('implements ')) {
      indicators['java'] = (indicators['java'] ?? 0) + 8;
    }
  }

  // Kotlin
  if (content.contains('fun ') && content.contains('val ') && content.contains('var ')) {
    indicators['kotlin'] = (indicators['kotlin'] ?? 0) + 10;
  }
  if (content.contains('suspend fun') || content.contains('data class')) {
    indicators['kotlin'] = (indicators['kotlin'] ?? 0) + 5;
  }

  if (indicators.isEmpty) return 'unknown';

  // Return the language with highest score.
  return indicators.entries.reduce((a, b) => a.value > b.value ? a : b).key;
}

/// Format a list of file paths into a project structure summary.
///
/// [files]  List of file paths.
///
/// Returns a formatted string for use in prompts.
String formatProjectStructure(List<String> files) {
  final buffer = StringBuffer();
  final dirs = <String, List<String>>{};

  for (final file in files) {
    final lastSlash = file.lastIndexOf('/');
    final dir = lastSlash >= 0 ? file.substring(0, lastSlash) : '.';
    dirs.putIfAbsent(dir, () => []).add(lastSlash >= 0 ? file.substring(lastSlash + 1) : file);
  }

  final sortedDirs = dirs.keys.toList()..sort();
  for (final dir in sortedDirs) {
    buffer.writeln('$dir/');
    final sortedFiles = dirs[dir]!..sort();
    for (final file in sortedFiles) {
      final ext = file.contains('.') ? file.split('.').last : '';
      final lang = SupportedLanguages.extensionMap['.$ext'] ?? ext;
      buffer.writeln('  $file ${lang != ext ? "($lang)" : ""}');
    }
  }

  return buffer.toString().trim();
}

/// Build a complete system + user message pair for LLM requests.
///
/// This is the main entry point for getting prompts ready to send.
///
/// [taskType]     The type of coding task (maps to system prompt).
/// [userContent]  The main user content (code, description, etc.).
///
/// Returns a map with 'system' and 'user' keys.
Map<String, String> buildLlmMessages({
  required CodingTaskType taskType,
  required String userContent,
}) {
  final systemPrompt = switch (taskType) {
    CodingTaskType.generate => kCodeGenerationSystemPrompt,
    CodingTaskType.explain => kCodeExplanationSystemPrompt,
    CodingTaskType.fix => kCodeFixSystemPrompt,
    CodingTaskType.review => kCodeReviewSystemPrompt,
    CodingTaskType.screenshot => kScreenshotToCodeSystemPrompt,
    CodingTaskType.plan => kTaskPlanningSystemPrompt,
    _ => kSystemPersona,
  };

  return {
    'system': systemPrompt,
    'user': userContent,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// Types
// ═══════════════════════════════════════════════════════════════════════════

/// Categories of coding tasks the agent can perform.
///
/// Used to select the appropriate system prompt and parameters.
enum CodingTaskType {
  /// Generate new code from description.
  generate,

  /// Explain existing code.
  explain,

  /// Fix bugs or errors.
  fix,

  /// Refactor for quality.
  refactor,

  /// Review code.
  review,

  /// Convert from UI screenshot.
  screenshot,

  /// Plan multi-step tasks.
  plan,

  /// General chat.
  chat,

  /// Convert between languages.
  convert,

  /// Generate tests.
  test,

  /// Add documentation.
  document,
}
