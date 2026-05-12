import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// {@template message_type}
/// The type of content in a chat message.
///
/// - [text]: Plain text content
/// - [code]: Code block with syntax highlighting
/// - [error]: Error message from API or system
/// {@endtemplate}
enum MessageType {
  text,
  code,
  error;

  /// Converts a string to [MessageType], defaulting to [text].
  static MessageType fromString(String value) {
    return MessageType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MessageType.text,
    );
  }
}

/// {@template chat_message}
/// Represents a single message in the AI chat conversation.
///
/// Messages are immutable and created via factory constructors.
/// Each message has a type that determines how it's rendered
/// in the chat UI.
///
/// ## Usage
/// ```dart
/// // User message
/// final userMsg = ChatMessage.user('Hello, how do I use Riverpod?');
///
/// // AI text response
/// final aiMsg = ChatMessage.assistant('Riverpod is a reactive caching...');
///
/// // AI code response
/// final codeMsg = ChatMessage.code(
///   'final provider = StateProvider((ref) => 0);',
///   language: 'dart',
/// );
///
/// // Error message
/// final errMsg = ChatMessage.error('Failed to connect to API');
/// ```
/// {@endtemplate}
@immutable
class ChatMessage {
  /// Unique identifier for the message
  final String id;

  /// Message text content
  final String content;

  /// Whether this message was sent by the user (true) or AI (false)
  final bool isUser;

  /// When the message was sent/received
  final DateTime timestamp;

  /// Type of message content
  final MessageType type;

  /// Programming language for code type messages (e.g., 'dart', 'python')
  final String? language;

  /// Whether the message is still being generated (streaming)
  final bool isStreaming;

  /// Creates a [ChatMessage] with all fields specified.
  const ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    required this.type,
    this.language,
    this.isStreaming = false,
  });

  // ── Factory Constructors ──────────────────────────────────────────────

  /// Creates a user message.
  factory ChatMessage.user(
    String content, {
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: const Uuid().v4(),
      content: content,
      isUser: true,
      timestamp: timestamp ?? DateTime.now(),
      type: MessageType.text,
    );
  }

  /// Creates an AI assistant text message.
  factory ChatMessage.assistant(
    String content, {
    DateTime? timestamp,
    bool isStreaming = false,
  }) {
    return ChatMessage(
      id: const Uuid().v4(),
      content: content,
      isUser: false,
      timestamp: timestamp ?? DateTime.now(),
      type: MessageType.text,
      isStreaming: isStreaming,
    );
  }

  /// Creates an AI assistant code message.
  factory ChatMessage.code(
    String content, {
    String? language,
    DateTime? timestamp,
    bool isStreaming = false,
  }) {
    return ChatMessage(
      id: const Uuid().v4(),
      content: content,
      isUser: false,
      timestamp: timestamp ?? DateTime.now(),
      type: MessageType.code,
      language: language,
      isStreaming: isStreaming,
    );
  }

  /// Creates an error message.
  factory ChatMessage.error(
    String content, {
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: const Uuid().v4(),
      content: content,
      isUser: false,
      timestamp: timestamp ?? DateTime.now(),
      type: MessageType.error,
    );
  }

  /// Creates a streaming chunk placeholder.
  factory ChatMessage.streaming() {
    return ChatMessage(
      id: const Uuid().v4(),
      content: '',
      isUser: false,
      timestamp: DateTime.now(),
      type: MessageType.text,
      isStreaming: true,
    );
  }

  // ── JSON Serialization ────────────────────────────────────────────────

  /// Creates a [ChatMessage] from a JSON map.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      isUser: json['isUser'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: MessageType.fromString(json['type'] as String? ?? 'text'),
      language: json['language'] as String?,
      isStreaming: json['isStreaming'] as bool? ?? false,
    );
  }

  /// Converts this message to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      if (language != null) 'language': language,
      'isStreaming': isStreaming,
    };
  }

  // ── Copy & Update ─────────────────────────────────────────────────────

  /// Creates a copy with specified fields replaced.
  ChatMessage copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? timestamp,
    MessageType? type,
    String? language,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      language: language ?? this.language,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  /// Appends content (for streaming responses) and returns updated message.
  ChatMessage appendContent(String chunk) {
    return copyWith(content: content + chunk);
  }

  /// Marks the message as complete (streaming finished).
  ChatMessage finish() => copyWith(isStreaming: false);

  // ── Computed Properties ───────────────────────────────────────────────

  /// Formatted timestamp for display (e.g., '2:30 PM').
  String get formattedTime {
    final hour = timestamp.hour > 12 ? timestamp.hour - 12 : timestamp.hour;
    final period = timestamp.hour >= 12 ? 'PM' : 'AM';
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  /// Short preview of the content (first 50 chars).
  String get preview {
    if (content.length <= 50) return content;
    return '${content.substring(0, 50)}...';
  }

  /// Approximate token count (rough estimate: 4 chars ≈ 1 token).
  int get estimatedTokens => (content.length / 4).ceil();

  /// Whether this message contains code blocks (markdown format).
  bool get hasCodeBlocks {
    return content.contains('```');
  }

  /// Extracts code blocks from markdown-formatted content.
  ///
  /// Returns a list of maps with 'language' and 'code' keys.
  List<Map<String, String>> extractCodeBlocks() {
    final blocks = <Map<String, String>>[];
    final regex = RegExp(r'```(\w+)?\n([\s\S]*?)\n?```', multiLine: true);
    for (final match in regex.allMatches(content)) {
      blocks.add({
        'language': match.group(1) ?? 'text',
        'code': match.group(2) ?? '',
      });
    }
    return blocks;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage &&
        other.id == id &&
        other.content == content &&
        other.isUser == isUser &&
        other.timestamp == timestamp &&
        other.type == type &&
        other.language == language &&
        other.isStreaming == isStreaming;
  }

  @override
  int get hashCode => Object.hash(
        id,
        content,
        isUser,
        timestamp,
        type,
        language,
        isStreaming,
      );

  @override
  String toString() {
    final sender = isUser ? 'User' : 'AI';
    return 'ChatMessage($sender, type: ${type.name}, '
        'streaming: $isStreaming, length: ${content.length})';
  }
}