import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════════

/// Publication status of a knowledge base article.
///
/// Articles flow through the lifecycle: [draft] → [published] → [archived].
enum KnowledgeStatus {
  /// Still being written, visible only to the author and admins.
  draft,

  /// Live and visible to all team members.
  published,

  /// No longer actively displayed but retained for reference.
  archived,
}

// ═══════════════════════════════════════════════════════════════════════════
// Comment Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template knowledge_comment}
/// A comment on a knowledge base article.
///
/// Comments are simple text replies attached to an article,
/// enabling team discussion and clarification.
/// {@endtemplate}
@immutable
class KnowledgeComment {
  /// Unique identifier for the comment.
  final String id;

  /// ID of the member who wrote the comment.
  final String authorId;

  /// Display name of the comment author.
  final String authorName;

  /// Comment text content (plain text, max 2000 chars).
  final String content;

  /// When the comment was created.
  final DateTime createdAt;

  /// Creates a [KnowledgeComment] with all fields specified.
  const KnowledgeComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  /// Factory for creating a new comment with auto-generated ID and timestamp.
  factory KnowledgeComment.create({
    required String authorId,
    required String authorName,
    required String content,
  }) {
    return KnowledgeComment(
      id: const Uuid().v4(),
      authorId: authorId,
      authorName: authorName,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  // ── JSON Serialization ────────────────────────────────────────────────

  /// Creates a [KnowledgeComment] from a JSON map.
  factory KnowledgeComment.fromJson(Map<String, dynamic> json) {
    return KnowledgeComment(
      id: json['id'] as String,
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Converts this comment to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorId': authorId,
      'authorName': authorName,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // ── Copy & Update ─────────────────────────────────────────────────────

  /// Creates a copy with specified fields replaced.
  KnowledgeComment copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? content,
    DateTime? createdAt,
  }) {
    return KnowledgeComment(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ── Object overrides ──────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KnowledgeComment &&
        other.id == id &&
        other.authorId == authorId &&
        other.authorName == authorName &&
        other.content == content &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        authorId,
        authorName,
        content,
        createdAt,
      );

  @override
  String toString() {
    return 'KnowledgeComment(id: $id, author: $authorName, '
        'content: ${content.length} chars)';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Knowledge Article Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template team_knowledge}
/// A knowledge base article for team-wide sharing.
///
/// Articles are written in Markdown and organized by [category] and [tags].
/// They support engagement tracking (views, likes, comments) and can be
/// pinned for important reference material.
///
/// ## Usage
/// ```dart
/// final article = TeamKnowledge(
///   id: 'kb_001',
///   title: 'Flutter State Management Guide',
///   content: '# Overview\n\nWe use Riverpod for...',
///   category: 'Engineering',
///   authorId: 'user_123',
///   authorName: 'Alice Chen',
///   tags: const ['flutter', 'state-management'],
/// );
/// ```
/// {@endtemplate}
@immutable
class TeamKnowledge {
  /// Unique identifier for the article.
  final String id;

  /// Article title (max 200 characters).
  final String title;

  /// Article body in Markdown format.
  final String content;

  /// Category for organization (e.g., 'Engineering', 'Design', 'Process').
  final String category;

  /// ID of the member who authored the article.
  final String authorId;

  /// Display name of the author.
  final String authorName;

  /// Tags for filtering and search.
  final List<String> tags;

  /// When the article was first created.
  final DateTime createdAt;

  /// When the article was last modified.
  final DateTime updatedAt;

  /// Whether the article is pinned to the top of listings.
  final bool isPinned;

  /// Number of times the article has been viewed.
  final int views;

  /// Number of likes the article has received.
  final int likes;

  /// Comments on the article.
  final List<KnowledgeComment> comments;

  /// IDs of members who liked the article.
  final List<String> likedBy;

  /// Current publication status.
  final KnowledgeStatus status;

  /// Creates a [TeamKnowledge] with all fields specified.
  ///
  /// Use [TeamKnowledge.create] for creating new articles with auto-generated
  /// timestamps, UUID, and default values.
  const TeamKnowledge({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.authorId,
    required this.authorName,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    required this.isPinned,
    required this.views,
    required this.likes,
    required this.comments,
    required this.likedBy,
    required this.status,
  });

  /// Factory for creating a new knowledge article with sensible defaults.
  ///
  /// [title], [content], [category], [authorId], and [authorName] are required.
  factory TeamKnowledge.create({
    required String title,
    required String content,
    required String category,
    required String authorId,
    required String authorName,
    List<String>? tags,
    bool isPinned = false,
    KnowledgeStatus status = KnowledgeStatus.draft,
  }) {
    final now = DateTime.now();
    return TeamKnowledge(
      id: 'kb_${const Uuid().v4()}',
      title: title,
      content: content,
      category: category,
      authorId: authorId,
      authorName: authorName,
      tags: tags ?? const [],
      createdAt: now,
      updatedAt: now,
      isPinned: isPinned,
      views: 0,
      likes: 0,
      comments: const [],
      likedBy: const [],
      status: status,
    );
  }

  // ── JSON Serialization ────────────────────────────────────────────────

  /// Creates a [TeamKnowledge] from a JSON map.
  factory TeamKnowledge.fromJson(Map<String, dynamic> json) {
    return TeamKnowledge(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      category: json['category'] as String,
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isPinned: json['isPinned'] as bool? ?? false,
      views: json['views'] as int? ?? 0,
      likes: json['likes'] as int? ?? 0,
      comments: (json['comments'] as List<dynamic>?)
              ?.map((e) => KnowledgeComment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      likedBy: (json['likedBy'] as List<dynamic>?)?.cast<String>() ?? const [],
      status: KnowledgeStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => KnowledgeStatus.draft,
      ),
    );
  }

  /// Converts this article to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'category': category,
      'authorId': authorId,
      'authorName': authorName,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPinned': isPinned,
      'views': views,
      'likes': likes,
      'comments': comments.map((c) => c.toJson()).toList(),
      'likedBy': likedBy,
      'status': status.name,
    };
  }

  // ── Copy & Update ─────────────────────────────────────────────────────

  /// Creates a copy with specified fields replaced.
  TeamKnowledge copyWith({
    String? id,
    String? title,
    String? content,
    String? category,
    String? authorId,
    String? authorName,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    int? views,
    int? likes,
    List<KnowledgeComment>? comments,
    List<String>? likedBy,
    KnowledgeStatus? status,
  }) {
    return TeamKnowledge(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      views: views ?? this.views,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      likedBy: likedBy ?? this.likedBy,
      status: status ?? this.status,
    );
  }

  // ── Convenience Mutations ─────────────────────────────────────────────

  /// Increments the view count and returns the updated article.
  TeamKnowledge incrementViews() => copyWith(views: views + 1);

  /// Toggles a member's like on this article.
  ///
  /// If [memberId] has already liked, removes the like. Otherwise adds it.
  TeamKnowledge toggleLike(String memberId) {
    final hasLiked = likedBy.contains(memberId);
    return copyWith(
      likes: hasLiked ? likes - 1 : likes + 1,
      likedBy: hasLiked
          ? likedBy.where((id) => id != memberId).toList()
          : [...likedBy, memberId],
    );
  }

  /// Adds a comment and returns the updated article.
  TeamKnowledge addComment(KnowledgeComment comment) {
    return copyWith(
      comments: [...comments, comment],
      updatedAt: DateTime.now(),
    );
  }

  /// Removes a comment by ID and returns the updated article.
  TeamKnowledge removeComment(String commentId) {
    return copyWith(
      comments: comments.where((c) => c.id != commentId).toList(),
      updatedAt: DateTime.now(),
    );
  }

  /// Pins or unpins the article.
  TeamKnowledge setPinned(bool pinned) => copyWith(isPinned: pinned);

  /// Changes the publication status.
  TeamKnowledge setStatus(KnowledgeStatus newStatus) => copyWith(status: newStatus);

  // ── Computed Properties ───────────────────────────────────────────────

  /// Short preview of the content (first 150 characters, stripped of Markdown).
  String get preview {
    final plain = content
        .replaceAll(RegExp(r'[#*_~`>|\[\]\(\)!]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.length <= 150) return plain;
    return '${plain.substring(0, 150)}...';
  }

  /// Approximate read time in minutes (at 200 words per minute).
  int get readTimeMinutes {
    final wordCount = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return (wordCount / 200).ceil().clamp(1, 120);
  }

  // ── Object overrides ──────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TeamKnowledge &&
        other.id == id &&
        other.title == title &&
        other.content == content &&
        other.category == category &&
        other.authorId == authorId &&
        other.authorName == authorName &&
        listEquals(other.tags, tags) &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.isPinned == isPinned &&
        other.views == views &&
        other.likes == likes &&
        listEquals(other.comments, comments) &&
        listEquals(other.likedBy, likedBy) &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        content,
        category,
        authorId,
        authorName,
        Object.hashAll(tags),
        createdAt,
        updatedAt,
        isPinned,
        views,
        likes,
        Object.hashAll(comments),
        Object.hashAll(likedBy),
        status,
      );

  @override
  String toString() {
    return 'TeamKnowledge(id: $id, title: "$title", category: $category, '
        'status: ${status.name}, views: $views, likes: $likes, comments: ${comments.length})';
  }
}
