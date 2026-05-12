// lib/services/team_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/theme.dart';
import '../models/team_member.dart';
import 'api_service.dart';
import 'storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════════

/// Types of activities that can occur in a team.
enum ActivityType {
  /// A new member joined the team.
  memberJoined,

  /// A member left or was removed from the team.
  memberLeft,

  /// Code was committed to a shared project.
  codeCommitted,

  /// An issue or task was created.
  issueCreated,

  /// A pull request was merged.
  prMerged,

  /// A file was shared with the team.
  fileShared,

  /// A comment was added to an article or project.
  commentAdded,

  /// A new project was created.
  projectCreated,
}

/// Extension providing display metadata for [ActivityType].
extension ActivityTypeExt on ActivityType {
  /// Human-readable description of the activity type.
  String get label {
    switch (this) {
      case ActivityType.memberJoined:
        return 'Member Joined';
      case ActivityType.memberLeft:
        return 'Member Left';
      case ActivityType.codeCommitted:
        return 'Code Committed';
      case ActivityType.issueCreated:
        return 'Issue Created';
      case ActivityType.prMerged:
        return 'PR Merged';
      case ActivityType.fileShared:
        return 'File Shared';
      case ActivityType.commentAdded:
        return 'Comment Added';
      case ActivityType.projectCreated:
        return 'Project Created';
    }
  }

  /// Icon data for the activity type.
  IconData get icon {
    switch (this) {
      case ActivityType.memberJoined:
        return Icons.person_add;
      case ActivityType.memberLeft:
        return Icons.person_remove;
      case ActivityType.codeCommitted:
        return Icons.commit;
      case ActivityType.issueCreated:
        return Icons.add_circle_outline;
      case ActivityType.prMerged:
        return Icons.merge_type;
      case ActivityType.fileShared:
        return Icons.share;
      case ActivityType.commentAdded:
        return Icons.comment;
      case ActivityType.projectCreated:
        return Icons.create_new_folder;
    }
  }

  /// Theme color for the activity type.
  Color get color {
    switch (this) {
      case ActivityType.memberJoined:
        return AppTheme.success;
      case ActivityType.memberLeft:
        return AppTheme.error;
      case ActivityType.codeCommitted:
        return AppTheme.primary;
      case ActivityType.issueCreated:
        return AppTheme.warning;
      case ActivityType.prMerged:
        return AppTheme.accent;
      case ActivityType.fileShared:
        return AppTheme.info;
      case ActivityType.commentAdded:
        return AppTheme.textSecondary;
      case ActivityType.projectCreated:
        return AppTheme.primary;
    }
  }
}

/// Presence status of a team member.
enum PresenceStatus {
  /// Actively using the app.
  online,

  /// App is open but user is idle.
  away,

  /// User is in "do not disturb" mode.
  busy,

  /// User is not connected.
  offline,
}

// ═══════════════════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════════════════

/// {@template message_reaction}
/// An emoji reaction to a team chat message.
/// {@endtemplate}
@immutable
class MessageReaction {
  /// The emoji character (e.g., '👍', '🔥').
  final String emoji;

  /// IDs of members who reacted with this emoji.
  final List<String> memberIds;

  const MessageReaction({
    required this.emoji,
    required this.memberIds,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      emoji: json['emoji'] as String,
      memberIds: (json['memberIds'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'emoji': emoji,
      'memberIds': memberIds,
    };
  }

  MessageReaction copyWith({
    String? emoji,
    List<String>? memberIds,
  }) {
    return MessageReaction(
      emoji: emoji ?? this.emoji,
      memberIds: memberIds ?? this.memberIds,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageReaction &&
        other.emoji == emoji &&
        listEquals(other.memberIds, memberIds);
  }

  @override
  int get hashCode => Object.hash(emoji, Object.hashAll(memberIds));
}

/// {@template team_activity}
/// A single activity event in the team activity feed.
/// {@endtemplate}
@immutable
class TeamActivity {
  /// Unique identifier for the activity.
  final String id;

  /// ID of the member who performed the action.
  final String actorId;

  /// Display name of the acting member.
  final String actorName;

  /// Type of activity that occurred.
  final ActivityType type;

  /// Human-readable description of the activity.
  final String description;

  /// Optional ID of the affected resource.
  final String? targetId;

  /// Optional name of the affected resource.
  final String? targetName;

  /// When the activity occurred.
  final DateTime timestamp;

  const TeamActivity({
    required this.id,
    required this.actorId,
    required this.actorName,
    required this.type,
    required this.description,
    this.targetId,
    this.targetName,
    required this.timestamp,
  });

  factory TeamActivity.fromJson(Map<String, dynamic> json) {
    return TeamActivity(
      id: json['id'] as String,
      actorId: json['actorId'] as String,
      actorName: json['actorName'] as String,
      type: ActivityType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ActivityType.commentAdded,
      ),
      description: json['description'] as String,
      targetId: json['targetId'] as String?,
      targetName: json['targetName'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'actorId': actorId,
      'actorName': actorName,
      'type': type.name,
      'description': description,
      if (targetId != null) 'targetId': targetId,
      if (targetName != null) 'targetName': targetName,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  TeamActivity copyWith({
    String? id,
    String? actorId,
    String? actorName,
    ActivityType? type,
    String? description,
    String? targetId,
    String? targetName,
    DateTime? timestamp,
  }) {
    return TeamActivity(
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      actorName: actorName ?? this.actorName,
      type: type ?? this.type,
      description: description ?? this.description,
      targetId: targetId ?? this.targetId,
      targetName: targetName ?? this.targetName,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TeamActivity &&
        other.id == id &&
        other.actorId == actorId &&
        other.actorName == actorName &&
        other.type == type &&
        other.description == description &&
        other.targetId == targetId &&
        other.targetName == targetName &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(
        id,
        actorId,
        actorName,
        type,
        description,
        targetId,
        targetName,
        timestamp,
      );
}

/// {@template team_message}
/// A single message in the team chat.
/// {@endtemplate}
@immutable
class TeamMessage {
  /// Unique identifier for the message.
  final String id;

  /// ID of the member who sent the message.
  final String authorId;

  /// Display name of the message author.
  final String authorName;

  /// Optional URL to the author's avatar.
  final String? authorAvatar;

  /// Message text content.
  final String content;

  /// When the message was sent.
  final DateTime timestamp;

  /// Optional channel identifier (e.g., 'general', 'engineering').
  final String? channel;

  /// Optional ID of the message this is replying to.
  final String? replyTo;

  /// Emoji reactions to this message.
  final List<MessageReaction> reactions;

  const TeamMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    required this.content,
    required this.timestamp,
    this.channel,
    this.replyTo,
    required this.reactions,
  });

  factory TeamMessage.create({
    required String authorId,
    required String authorName,
    String? authorAvatar,
    required String content,
    String? channel,
    String? replyTo,
  }) {
    return TeamMessage(
      id: const Uuid().v4(),
      authorId: authorId,
      authorName: authorName,
      authorAvatar: authorAvatar,
      content: content,
      timestamp: DateTime.now(),
      channel: channel,
      replyTo: replyTo,
      reactions: const [],
    );
  }

  factory TeamMessage.fromJson(Map<String, dynamic> json) {
    return TeamMessage(
      id: json['id'] as String,
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String,
      authorAvatar: json['authorAvatar'] as String?,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      channel: json['channel'] as String?,
      replyTo: json['replyTo'] as String?,
      reactions: (json['reactions'] as List<dynamic>?)
              ?.map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorId': authorId,
      'authorName': authorName,
      if (authorAvatar != null) 'authorAvatar': authorAvatar,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      if (channel != null) 'channel': channel,
      if (replyTo != null) 'replyTo': replyTo,
      'reactions': reactions.map((r) => r.toJson()).toList(),
    };
  }

  TeamMessage copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? authorAvatar,
    String? content,
    DateTime? timestamp,
    String? channel,
    String? replyTo,
    List<MessageReaction>? reactions,
  }) {
    return TeamMessage(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      channel: channel ?? this.channel,
      replyTo: replyTo ?? this.replyTo,
      reactions: reactions ?? this.reactions,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TeamMessage &&
        other.id == id &&
        other.authorId == authorId &&
        other.authorName == authorName &&
        other.authorAvatar == authorAvatar &&
        other.content == content &&
        other.timestamp == timestamp &&
        other.channel == channel &&
        other.replyTo == replyTo &&
        listEquals(other.reactions, reactions);
  }

  @override
  int get hashCode => Object.hash(
        id,
        authorId,
        authorName,
        authorAvatar,
        content,
        timestamp,
        channel,
        replyTo,
        Object.hashAll(reactions),
      );
}

/// {@template team_project}
/// A project shared within the team.
/// {@endtemplate}
@immutable
class TeamProject {
  /// Unique identifier for the team project.
  final String id;

  /// Display name of the project.
  final String name;

  /// Optional description of the project.
  final String description;

  /// ID of the member who owns the project.
  final String ownerId;

  /// IDs of members who have access to the project.
  final List<String> memberIds;

  /// Number of files in the project.
  final int fileCount;

  /// When the project was last modified.
  final DateTime lastActivity;

  /// Whether the project is currently active.
  final bool isActive;

  const TeamProject({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.memberIds,
    required this.fileCount,
    required this.lastActivity,
    required this.isActive,
  });

  factory TeamProject.fromJson(Map<String, dynamic> json) {
    return TeamProject(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      ownerId: json['ownerId'] as String,
      memberIds: (json['memberIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      fileCount: json['fileCount'] as int? ?? 0,
      lastActivity: DateTime.parse(json['lastActivity'] as String),
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'fileCount': fileCount,
      'lastActivity': lastActivity.toIso8601String(),
      'isActive': isActive,
    };
  }

  TeamProject copyWith({
    String? id,
    String? name,
    String? description,
    String? ownerId,
    List<String>? memberIds,
    int? fileCount,
    DateTime? lastActivity,
    bool? isActive,
  }) {
    return TeamProject(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      memberIds: memberIds ?? this.memberIds,
      fileCount: fileCount ?? this.fileCount,
      lastActivity: lastActivity ?? this.lastActivity,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TeamProject &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.ownerId == ownerId &&
        listEquals(other.memberIds, memberIds) &&
        other.fileCount == fileCount &&
        other.lastActivity == lastActivity &&
        other.isActive == isActive;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        description,
        ownerId,
        Object.hashAll(memberIds),
        fileCount,
        lastActivity,
        isActive,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Exceptions
// ═══════════════════════════════════════════════════════════════════════════

/// Exception for team service operations.
class TeamServiceException implements Exception {
  final String message;
  final String? operation;
  final dynamic originalError;

  const TeamServiceException({
    required this.message,
    this.operation,
    this.originalError,
  });

  @override
  String toString() => 'TeamServiceException [$operation]: $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════════

/// {@template team_service}
/// Service for team collaboration features in Mobile Agent.
///
/// Provides a unified interface for managing team members, tracking
/// activity, team chat, shared projects, and presence status.
///
/// The service uses [ApiService] for server communication and
/// [StorageService] for local caching of team data.
///
/// ```dart
/// final teamService = TeamService(api: apiService, storage: storageService);
/// final members = await teamService.getTeamMembers();
/// ```
/// {@endtemplate}
class TeamService {
  /// The HTTP client for server communication.
  final ApiService _api;

  /// The local storage service for caching.
  final StorageService _storage;

  /// Stream controllers for reactive updates.
  final _messageControllers = <String, StreamController<TeamMessage>>{};
  final _presenceController = StreamController<Map<String, PresenceStatus>>.broadcast();

  /// Whether the service has been initialized.
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Storage keys for local caching.
  static const String _cacheKeyMembers = 'team_members';
  static const String _cacheKeyMessages = 'team_messages';
  static const String _cacheKeyActivity = 'team_activity';
  static const String _cacheKeyProjects = 'team_projects';
  static const String _cacheKeyPresence = 'team_presence';

  /// Creates a [TeamService].
  ///
  /// [_api] must be an initialized [ApiService] instance.
  /// [_storage] must be an initialized [StorageService] instance.
  TeamService({
    required ApiService api,
    required StorageService storage,
  })  : _api = api,
        _storage = storage;

  /// Initialize the service and load cached data.
  Future<void> init() async {
    if (_initialized) return;

    try {
      // Load cached members if available.
      final cachedMembers = await _storage.getSetting<String>(_cacheKeyMembers);
      if (cachedMembers != null) {
        debugPrint('[TeamService] Loaded ${cachedMembers.length} cached members');
      }

      _initialized = true;
      debugPrint('[TeamService] Initialized');
    } catch (e) {
      debugPrint('[TeamService] Init warning: $e');
      // Non-fatal: continue without cache.
      _initialized = true;
    }
  }

  // ── Members ───────────────────────────────────────────────────────────

  /// Get all members of the current team.
  ///
  /// Results are cached locally and refreshed from the server.
  /// Returns an empty list if the user is not part of a team.
  Future<List<TeamMember>> getTeamMembers() async {
    _ensureInitialized();
    try {
      final response = await _api.get('/team/members');
      final data = response.data as List<dynamic>;
      final members = data
          .map((json) => TeamMember.fromJson(json as Map<String, dynamic>))
          .toList();

      // Cache locally.
      await _storage.setSetting(
        _cacheKeyMembers,
        jsonEncode(members.map((m) => m.toJson()).toList()),
      );

      debugPrint('[TeamService] Fetched ${members.length} team members');
      return members;
    } on ApiException catch (e) {
      debugPrint('[TeamService] getTeamMembers API error: $e');
      // Attempt to return cached data.
      return _getCachedMembers();
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to load team members: $e',
        operation: 'getTeamMembers',
        originalError: e,
      );
    }
  }

  /// Invite a new member to the team by email.
  ///
  /// [email] must be a valid email address.
  /// [role] determines the initial permissions of the invited member.
  /// Returns the created [TeamMember] with [MemberStatus.pending].
  Future<TeamMember> inviteMember(String email, TeamRole role) async {
    _ensureInitialized();
    try {
      final response = await _api.post(
        '/team/members/invite',
        data: {
          'email': email,
          'role': role.name,
        },
      );

      final member = TeamMember.fromJson(response.data as Map<String, dynamic>);
      debugPrint('[TeamService] Invited member: ${member.email} as ${role.name}');
      return member;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to invite member "$email"',
        operation: 'inviteMember',
        originalError: e,
      );
    }
  }

  /// Remove a member from the team.
  ///
  /// Only owners and admins can remove members.
  /// Removing oneself is not allowed for the sole owner.
  Future<void> removeMember(String memberId) async {
    _ensureInitialized();
    try {
      await _api.delete('/team/members/$memberId');
      debugPrint('[TeamService] Removed member: $memberId');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to remove member "$memberId"',
        operation: 'removeMember',
        originalError: e,
      );
    }
  }

  /// Update the role of a team member.
  ///
  /// Only owners can assign the [owner] role.
  /// Admins can promote members to admin but cannot demote owners.
  Future<void> updateMemberRole(String memberId, TeamRole newRole) async {
    _ensureInitialized();
    try {
      await _api.patch(
        '/team/members/$memberId/role',
        data: {'role': newRole.name},
      );
      debugPrint('[TeamService] Updated role for $memberId to ${newRole.name}');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to update role for "$memberId"',
        operation: 'updateMemberRole',
        originalError: e,
      );
    }
  }

  /// Update granular permissions for a member.
  ///
  /// [perms] is a map of permission names to boolean values.
  /// These override the default permissions granted by the member's role.
  Future<void> updateMemberPermissions(
    String memberId,
    Map<String, bool> perms,
  ) async {
    _ensureInitialized();
    try {
      await _api.patch(
        '/team/members/$memberId/permissions',
        data: perms,
      );
      debugPrint('[TeamService] Updated permissions for $memberId: $perms');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to update permissions for "$memberId"',
        operation: 'updateMemberPermissions',
        originalError: e,
      );
    }
  }

  /// Get a single member by their ID.
  ///
  /// Returns `null` if the member is not found.
  Future<TeamMember?> getMemberById(String memberId) async {
    _ensureInitialized();
    try {
      final response = await _api.get('/team/members/$memberId');
      return TeamMember.fromJson(response.data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to get member "$memberId"',
        operation: 'getMemberById',
        originalError: e,
      );
    }
  }

  // ── Team Activity ─────────────────────────────────────────────────────

  /// Get the team activity feed.
  ///
  /// [limit] controls the maximum number of activities to return (default: 50).
  /// Results are sorted by timestamp (most recent first).
  Future<List<TeamActivity>> getTeamActivity({int limit = 50}) async {
    _ensureInitialized();
    try {
      final response = await _api.get(
        '/team/activity',
        query: {'limit': limit},
      );
      final data = response.data as List<dynamic>;
      final activities = data
          .map((json) => TeamActivity.fromJson(json as Map<String, dynamic>))
          .toList();

      // Sort by timestamp descending.
      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      debugPrint('[TeamService] Fetched ${activities.length} activities');
      return activities;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to load team activity',
        operation: 'getTeamActivity',
        originalError: e,
      );
    }
  }

  /// Get activity for a specific member.
  ///
  /// Returns activities where the given member is the actor.
  Future<List<TeamActivity>> getMemberActivity(String memberId) async {
    _ensureInitialized();
    try {
      final response = await _api.get('/team/members/$memberId/activity');
      final data = response.data as List<dynamic>;
      final activities = data
          .map((json) => TeamActivity.fromJson(json as Map<String, dynamic>))
          .toList();

      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return activities;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to load activity for "$memberId"',
        operation: 'getMemberActivity',
        originalError: e,
      );
    }
  }

  // ── Team Chat ─────────────────────────────────────────────────────────

  /// Get team chat messages.
  ///
  /// [channel] filters to a specific channel (e.g., 'general').
  /// If null, returns messages from all channels.
  /// [limit] controls the maximum number of messages (default: 100).
  Future<List<TeamMessage>> getTeamMessages({
    String? channel,
    int limit = 100,
  }) async {
    _ensureInitialized();
    try {
      final queryParams = <String, dynamic>{'limit': limit};
      if (channel != null) queryParams['channel'] = channel;

      final response = await _api.get('/team/messages', query: queryParams);
      final data = response.data as List<dynamic>;
      final messages = data
          .map((json) => TeamMessage.fromJson(json as Map<String, dynamic>))
          .toList();

      // Sort by timestamp ascending (oldest first for chat display).
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      debugPrint('[TeamService] Fetched ${messages.length} messages');
      return messages;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to load team messages',
        operation: 'getTeamMessages',
        originalError: e,
      );
    }
  }

  /// Send a message to the team chat.
  ///
  /// [content] is the message text.
  /// [channel] optionally targets a specific channel.
  /// [replyTo] optionally marks this as a reply to another message.
  Future<void> sendTeamMessage(
    String content, {
    String? channel,
    String? replyTo,
  }) async {
    _ensureInitialized();
    try {
      await _api.post('/team/messages', data: {
        'content': content,
        if (channel != null) 'channel': channel,
        if (replyTo != null) 'replyTo': replyTo,
      });
      debugPrint('[TeamService] Sent message to channel: $channel');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to send message',
        operation: 'sendTeamMessage',
        originalError: e,
      );
    }
  }

  /// Subscribe to real-time team chat messages.
  ///
  /// Returns a [Stream] that emits new [TeamMessage] objects as they arrive.
  /// [channel] filters to a specific channel; if null, listens to all channels.
  ///
  /// Callers must cancel the subscription when done to avoid memory leaks.
  Stream<TeamMessage> subscribeToMessages({String? channel}) {
    final channelKey = channel ?? '__all__';

    if (_messageControllers.containsKey(channelKey)) {
      return _messageControllers[channelKey]!.stream;
    }

    final controller = StreamController<TeamMessage>.broadcast();
    _messageControllers[channelKey] = controller;

    // In a real implementation, this would connect to a WebSocket
    // or SSE endpoint for real-time updates.
    _connectMessageStream(controller, channel);

    // Clean up when no more listeners.
    controller.onCancel = () {
      _messageControllers.remove(channelKey);
      controller.close();
    };

    return controller.stream;
  }

  /// Connect to the real-time message stream backend.
  void _connectMessageStream(StreamController<TeamMessage> controller, String? channel) {
    try {
      final sseEndpoint = channel != null
          ? '/team/messages/stream?channel=$channel'
          : '/team/messages/stream';

      final stream = _api.sseStream(sseEndpoint, data: const {});

      stream.listen(
        (line) {
          if (line.startsWith('data: ')) {
            try {
              final jsonData = jsonDecode(line.substring(6)) as Map<String, dynamic>;
              final message = TeamMessage.fromJson(jsonData);
              if (!controller.isClosed) {
                controller.add(message);
              }
            } catch (e) {
              debugPrint('[TeamService] Failed to parse SSE message: $e');
            }
          }
        },
        onError: (dynamic e) {
          debugPrint('[TeamService] Message stream error: $e');
          if (!controller.isClosed) {
            controller.addError(e);
          }
        },
        onDone: () {
          debugPrint('[TeamService] Message stream closed');
        },
      );
    } catch (e) {
      debugPrint('[TeamService] Failed to connect message stream: $e');
    }
  }

  // ── Team Projects ─────────────────────────────────────────────────────

  /// Get all projects shared within the team.
  ///
  /// Returns projects sorted by last activity (most recent first).
  Future<List<TeamProject>> getTeamProjects() async {
    _ensureInitialized();
    try {
      final response = await _api.get('/team/projects');
      final data = response.data as List<dynamic>;
      final projects = data
          .map((json) => TeamProject.fromJson(json as Map<String, dynamic>))
          .toList();

      projects.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

      // Cache locally.
      await _storage.setSetting(
        _cacheKeyProjects,
        jsonEncode(projects.map((p) => p.toJson()).toList()),
      );

      debugPrint('[TeamService] Fetched ${projects.length} team projects');
      return projects;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to load team projects',
        operation: 'getTeamProjects',
        originalError: e,
      );
    }
  }

  /// Create a new team project.
  ///
  /// [name] is the project display name.
  /// [description] is an optional description.
  /// [memberIds] are the IDs of members to share the project with initially.
  /// Returns the created [TeamProject].
  Future<TeamProject> createTeamProject(
    String name,
    String description,
    List<String> memberIds,
  ) async {
    _ensureInitialized();
    try {
      final response = await _api.post('/team/projects', data: {
        'name': name,
        'description': description,
        'memberIds': memberIds,
      });

      final project = TeamProject.fromJson(response.data as Map<String, dynamic>);
      debugPrint('[TeamService] Created team project: ${project.name}');
      return project;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to create team project "$name"',
        operation: 'createTeamProject',
        originalError: e,
      );
    }
  }

  /// Share an existing team project with a member.
  ///
  /// [projectId] is the ID of the project to share.
  /// [memberId] is the ID of the member to grant access to.
  /// [canEdit] determines whether the member can edit the project.
  Future<void> shareProjectWithMember(
    String projectId,
    String memberId, {
    bool canEdit = true,
  }) async {
    _ensureInitialized();
    try {
      await _api.post(
        '/team/projects/$projectId/share',
        data: {
          'memberId': memberId,
          'canEdit': canEdit,
        },
      );
      debugPrint('[TeamService] Shared project $projectId with $memberId (edit: $canEdit)');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to share project "$projectId"',
        operation: 'shareProjectWithMember',
        originalError: e,
      );
    }
  }

  /// Remove a member's access to a team project.
  ///
  /// [projectId] is the ID of the project.
  /// [memberId] is the ID of the member to revoke access from.
  Future<void> removeProjectAccess(String projectId, String memberId) async {
    _ensureInitialized();
    try {
      await _api.delete('/team/projects/$projectId/members/$memberId');
      debugPrint('[TeamService] Removed access for $memberId from project $projectId');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to remove access for "$memberId"',
        operation: 'removeProjectAccess',
        originalError: e,
      );
    }
  }

  // ── Presence ──────────────────────────────────────────────────────────

  /// Update the current user's presence status.
  ///
  /// [status] should reflect the user's current availability.
  Future<void> updatePresence(PresenceStatus status) async {
    _ensureInitialized();
    try {
      await _api.post('/team/presence', data: {
        'status': status.name,
      });
      debugPrint('[TeamService] Updated presence to ${status.name}');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw TeamServiceException(
        message: 'Failed to update presence',
        operation: 'updatePresence',
        originalError: e,
      );
    }
  }

  /// Subscribe to real-time presence updates for all team members.
  ///
  /// Returns a [Stream] that emits a map of member ID to [PresenceStatus]
  /// whenever any member's presence changes.
  ///
  /// Callers must cancel the subscription when done.
  Stream<Map<String, PresenceStatus>> subscribeToPresence() {
    return _presenceController.stream;
  }

  /// Start polling for presence updates.
  ///
  /// In a real implementation this would connect to a WebSocket.
  /// For now, it polls every 30 seconds.
  void startPresencePolling() {
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        final response = await _api.get('/team/presence');
        final data = response.data as Map<String, dynamic>;
        final presenceMap = data.map((key, value) {
          return MapEntry(
            key,
            PresenceStatus.values.firstWhere(
              (e) => e.name == value,
              orElse: () => PresenceStatus.offline,
            ),
          );
        });

        if (!_presenceController.isClosed) {
          _presenceController.add(presenceMap);
        }
      } catch (e) {
        debugPrint('[TeamService] Presence polling error: $e');
      }
    });
  }

  // ── Private Helpers ───────────────────────────────────────────────────

  void _ensureInitialized() {
    if (!_initialized) {
      throw const TeamServiceException(
        message: 'TeamService not initialized. Call init() first.',
        operation: '_ensureInitialized',
      );
    }
  }

  /// Load team members from local cache.
  Future<List<TeamMember>> _getCachedMembers() async {
    try {
      final cached = await _storage.getSetting<String>(_cacheKeyMembers);
      if (cached == null || cached.isEmpty) return [];

      final decoded = jsonDecode(cached) as List<dynamic>;
      return decoded
          .map((json) => TeamMember.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[TeamService] Failed to load cached members: $e');
      return [];
    }
  }

  /// Dispose all stream controllers and release resources.
  void dispose() {
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    _messageControllers.clear();
    _presenceController.close();
    _initialized = false;
    debugPrint('[TeamService] Disposed');
  }
}
