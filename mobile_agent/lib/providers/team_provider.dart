// lib/providers/team_provider.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/team_member.dart';
import '../models/team_activity.dart';
import '../models/team_message.dart';
import '../models/team_project.dart';
import '../models/presence_status.dart';
import '../services/team_service.dart';

// ─── Team Service DI ───────────────────────────────────────────────────

/// Provider for the [TeamService] singleton.
///
/// Injected into all team-related notifiers for data operations.
/// Replace with a mock in tests:
/// ```dart
/// final container = ProviderContainer(
///   overrides: [teamServiceProvider.overrideWithValue(mockService)],
/// );
/// ```
final teamServiceProvider = Provider<TeamService>((ref) {
  return TeamService();
});

// ─── Members ───────────────────────────────────────────────────────────

/// Manages the team member list with CRUD operations.
///
/// Automatically loads members on creation. Supports inviting,
/// removing, and updating member roles/permissions.
///
/// ```dart
/// final members = ref.watch(teamMembersProvider);
/// await ref.read(teamMembersProvider.notifier).inviteMember('a@b.com', TeamRole.developer);
/// ```
class TeamMembersNotifier extends StateNotifier<AsyncValue<List<TeamMember>>> {
  final TeamService _service;

  TeamMembersNotifier(this._service) : super(const AsyncValue.loading()) {
    loadMembers();
  }

  /// Load all team members from the service.
  Future<void> loadMembers() async {
    state = const AsyncValue.loading();
    try {
      final members = await _service.getMembers();
      state = AsyncValue.data(members);
    } catch (e, stack) {
      debugPrint('[TeamMembersNotifier] Failed to load members: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// Refresh the member list (preserves previous data during load).
  Future<void> refresh() async {
    try {
      final members = await _service.getMembers();
      state = AsyncValue.data(members);
    } catch (e, stack) {
      debugPrint('[TeamMembersNotifier] Failed to refresh members: $e');
      // Don't overwrite with error; keep stale data.
      if (state is! AsyncData) {
        state = AsyncValue.error(e, stack);
      }
    }
  }

  /// Invite a new member by email.
  ///
  /// Sends an invitation email and adds a pending member entry.
  /// Automatically refreshes the list on success.
  Future<void> inviteMember(String email, TeamRole role) async {
    if (email.isEmpty) return;
    try {
      await _service.inviteMember(email, role);
      await loadMembers();
    } catch (e, stack) {
      debugPrint('[TeamMembersNotifier] Failed to invite member: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// Remove a member from the team.
  ///
  /// Immediately removes the member from local state, then
  /// syncs with the server. Rolls back on failure.
  Future<void> removeMember(String memberId) async {
    final previous = state.valueOrNull ?? [];
    final updated = previous.where((m) => m.id != memberId).toList();
    state = AsyncValue.data(updated);

    try {
      await _service.removeMember(memberId);
    } catch (e, stack) {
      debugPrint('[TeamMembersNotifier] Failed to remove member: $e');
      state = AsyncValue.data(previous);
      state = AsyncValue.error(e, stack);
    }
  }

  /// Update a member's role.
  Future<void> updateRole(String memberId, TeamRole role) async {
    final previous = state.valueOrNull ?? [];
    final updated = previous.map((m) {
      return m.id == memberId ? m.copyWith(role: role) : m;
    }).toList();
    state = AsyncValue.data(updated);

    try {
      await _service.updateMemberRole(memberId, role);
    } catch (e, stack) {
      debugPrint('[TeamMembersNotifier] Failed to update role: $e');
      state = AsyncValue.data(previous);
    }
  }

  /// Update granular permissions for a member.
  Future<void> updatePermissions(
    String memberId,
    Map<String, bool> permissions,
  ) async {
    final previous = state.valueOrNull ?? [];
    final updated = previous.map((m) {
      return m.id == memberId
          ? m.copyWith(permissions: {...m.permissions, ...permissions})
          : m;
    }).toList();
    state = AsyncValue.data(updated);

    try {
      await _service.updateMemberPermissions(memberId, permissions);
    } catch (e, stack) {
      debugPrint('[TeamMembersNotifier] Failed to update permissions: $e');
      state = AsyncValue.data(previous);
    }
  }
}

/// Provider for the team member list.
///
/// ```dart
/// final membersAsync = ref.watch(teamMembersProvider);
/// membersAsync.when(
///   data: (members) => MemberListView(members),
///   loading: () => const CircularProgressIndicator(),
///   error: (e, _) => ErrorWidget(e),
/// );
/// ```
final teamMembersProvider =
    StateNotifierProvider<TeamMembersNotifier, AsyncValue<List<TeamMember>>>(
  (ref) => TeamMembersNotifier(ref.read(teamServiceProvider)),
);

// ─── Team Activity ─────────────────────────────────────────────────────

/// Manages the team activity feed.
///
/// Tracks commits, PRs, code reviews, and other team events.
class TeamActivityNotifier extends StateNotifier<AsyncValue<List<TeamActivity>>> {
  final TeamService _service;

  TeamActivityNotifier(this._service) : super(const AsyncValue.loading()) {
    loadActivity();
  }

  /// Load recent team activity.
  Future<void> loadActivity() async {
    state = const AsyncValue.loading();
    try {
      final activity = await _service.getRecentActivity();
      state = AsyncValue.data(activity);
    } catch (e, stack) {
      debugPrint('[TeamActivityNotifier] Failed to load activity: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// Refresh activity feed (silently, without showing loading state).
  Future<void> refresh() async {
    try {
      final activity = await _service.getRecentActivity();
      state = AsyncValue.data(activity);
    } catch (e) {
      debugPrint('[TeamActivityNotifier] Failed to refresh activity: $e');
    }
  }
}

/// Provider for the team activity feed.
///
/// ```dart
/// final activityAsync = ref.watch(teamActivityProvider);
/// ```
final teamActivityProvider =
    StateNotifierProvider<TeamActivityNotifier, AsyncValue<List<TeamActivity>>>(
  (ref) => TeamActivityNotifier(ref.read(teamServiceProvider)),
);

// ─── Team Chat ─────────────────────────────────────────────────────────

/// Manages real-time team chat messages.
///
/// Supports sending messages with optional channel targeting
/// and reply threading. Automatically subscribes to message
/// updates via the underlying service stream.
class TeamChatNotifier extends StateNotifier<AsyncValue<List<TeamMessage>>> {
  final TeamService _service;
  StreamSubscription<List<TeamMessage>>? _sub;

  TeamChatNotifier(this._service) : super(const AsyncValue.data([]));

  /// Subscribe to real-time messages for a channel.
  ///
  /// Call this when entering a chat view. Cancels any existing subscription.
  void subscribeToMessages({String? channel}) {
    _sub?.cancel();
    _sub = _service.subscribeToMessages(channel: channel).listen(
      (messages) {
        state = AsyncValue.data(messages);
      },
      onError: (e, stack) {
        debugPrint('[TeamChatNotifier] Stream error: $e');
        state = AsyncValue.error(e, stack);
      },
    );
  }

  /// Send a message to the current or specified channel.
  ///
  /// [content] The message text (supports markdown).
  /// [channel] Optional channel override.
  /// [replyTo] Optional message ID to reply to.
  Future<void> sendMessage(
    String content, {
    String? channel,
    String? replyTo,
  }) async {
    if (content.trim().isEmpty) return;
    try {
      await _service.sendMessage(
        content: content.trim(),
        channel: channel,
        replyTo: replyTo,
      );
    } catch (e, stack) {
      debugPrint('[TeamChatNotifier] Failed to send message: $e');
      // Message is already optimistic in stream; error handled by listener.
      state = AsyncValue.error(e, stack);
    }
  }

  /// Load historical messages for a channel.
  Future<void> loadHistory({String? channel, int limit = 50}) async {
    state = const AsyncValue.loading();
    try {
      final messages = await _service.getMessages(
        channel: channel,
        limit: limit,
      );
      state = AsyncValue.data(messages);
    } catch (e, stack) {
      debugPrint('[TeamChatNotifier] Failed to load history: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// Cancel the real-time subscription.
  ///
  /// Call this when leaving the chat view to prevent memory leaks.
  void unsubscribe() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Provider for team chat messages.
///
/// ```dart
/// final chatAsync = ref.watch(teamChatProvider);
/// ref.read(teamChatProvider.notifier).subscribeToMessages(channel: 'general');
/// ```
final teamChatProvider =
    StateNotifierProvider<TeamChatNotifier, AsyncValue<List<TeamMessage>>>(
  (ref) => TeamChatNotifier(ref.read(teamServiceProvider)),
);

// ─── Team Projects ─────────────────────────────────────────────────────

/// Manages team-shared projects.
///
/// Tracks collaborative coding projects, shared codebases,
/// and team-level project configurations.
class TeamProjectsNotifier extends StateNotifier<AsyncValue<List<TeamProject>>> {
  final TeamService _service;

  TeamProjectsNotifier(this._service) : super(const AsyncValue.loading()) {
    loadProjects();
  }

  /// Load all team projects.
  Future<void> loadProjects() async {
    state = const AsyncValue.loading();
    try {
      final projects = await _service.getProjects();
      state = AsyncValue.data(projects);
    } catch (e, stack) {
      debugPrint('[TeamProjectsNotifier] Failed to load projects: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// Create a new team project.
  Future<void> createProject(String name, {String? description}) async {
    try {
      await _service.createProject(name, description: description);
      await loadProjects();
    } catch (e, stack) {
      debugPrint('[TeamProjectsNotifier] Failed to create project: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// Update project details.
  Future<void> updateProject(
    String projectId, {
    String? name,
    String? description,
    Map<String, dynamic>? settings,
  }) async {
    final previous = state.valueOrNull ?? [];
    final updated = previous.map((p) {
      if (p.id != projectId) return p;
      return p.copyWith(
        name: name ?? p.name,
        description: description ?? p.description,
        settings: settings ?? p.settings,
        updatedAt: DateTime.now(),
      );
    }).toList();
    state = AsyncValue.data(updated);

    try {
      await _service.updateProject(projectId,
          name: name, description: description, settings: settings);
    } catch (e) {
      debugPrint('[TeamProjectsNotifier] Failed to update project: $e');
      state = AsyncValue.data(previous);
    }
  }

  /// Archive (soft-delete) a project.
  Future<void> archiveProject(String projectId) async {
    final previous = state.valueOrNull ?? [];
    final updated = previous.where((p) => p.id != projectId).toList();
    state = AsyncValue.data(updated);

    try {
      await _service.archiveProject(projectId);
    } catch (e) {
      debugPrint('[TeamProjectsNotifier] Failed to archive project: $e');
      state = AsyncValue.data(previous);
    }
  }

  /// Refresh the project list.
  Future<void> refresh() async {
    try {
      final projects = await _service.getProjects();
      state = AsyncValue.data(projects);
    } catch (e) {
      debugPrint('[TeamProjectsNotifier] Failed to refresh projects: $e');
    }
  }
}

/// Provider for team projects.
///
/// ```dart
/// final projectsAsync = ref.watch(teamProjectsProvider);
/// ```
final teamProjectsProvider =
    StateNotifierProvider<TeamProjectsNotifier, AsyncValue<List<TeamProject>>>(
  (ref) => TeamProjectsNotifier(ref.read(teamServiceProvider)),
);

// ─── Presence ──────────────────────────────────────────────────────────

/// Real-time provider for team member presence status.
///
/// Emits a map of member ID to presence status (online, away, busy, offline).
/// Updates automatically when members come online or go offline.
///
/// ```dart
/// final presenceAsync = ref.watch(teamPresenceProvider);
/// presenceAsync.whenData((map) {
///   final status = map['userId'];
///   if (status == PresenceStatus.online) { ... }
/// });
/// ```
final teamPresenceProvider = StreamProvider<Map<String, PresenceStatus>>((ref) {
  return ref.read(teamServiceProvider).subscribeToPresence();
});

// ─── Selected Member ───────────────────────────────────────────────────

/// Currently selected team member for detail views.
///
/// Used in conjunction with navigation to show member profiles,
/// activity history, and permission management.
///
/// ```dart
/// final selected = ref.watch(selectedTeamMemberProvider);
/// ref.read(selectedTeamMemberProvider.notifier).state = member;
/// ```
final selectedTeamMemberProvider = StateProvider<TeamMember?>((ref) => null);

// ─── Team Chat Channel ─────────────────────────────────────────────────

/// Currently active chat channel.
///
/// Default is 'general'. Changing this should trigger a
/// re-subscription in the consuming widget.
///
/// ```dart
/// final channel = ref.watch(teamChatChannelProvider);
/// ref.read(teamChatChannelProvider.notifier).state = 'engineering';
/// ```
final teamChatChannelProvider = StateProvider<String>((ref) => 'general');

// ─── Team Stats ────────────────────────────────────────────────────────

/// Computed provider that aggregates team statistics.
///
/// Derives from [teamMembersProvider] and [teamActivityProvider]
/// to compute: total members, online count, active this week count,
/// and total commits.
///
/// ```dart
/// final stats = ref.watch(teamStatsProvider);
/// final totalMembers = stats['totalMembers'] as int;
/// ```
final teamStatsProvider = Provider<Map<String, dynamic>>((ref) {
  final membersAsync = ref.watch(teamMembersProvider);
  final activityAsync = ref.watch(teamActivityProvider);

  final members = membersAsync.valueOrNull ?? [];
  final activity = activityAsync.valueOrNull ?? [];

  // Count online members
  final onlineCount = members.where((m) => m.isOnline).length;

  // Members active within the last 7 days
  final now = DateTime.now();
  final weekAgo = now.subtract(const Duration(days: 7));
  final activeThisWeek = members
      .where((m) => m.lastActiveAt != null && m.lastActiveAt!.isAfter(weekAgo))
      .length;

  // Total commits from activity feed
  final totalCommits = activity
      .where((a) => a.type == ActivityType.commit)
      .fold<int>(0, (sum, a) => sum + (a.metadata?['commitCount'] as int? ?? 1));

  // PRs merged this week
  final prsMerged = activity
      .where((a) =>
          a.type == ActivityType.pullRequest &&
          a.action == 'merged' &&
          a.timestamp.isAfter(weekAgo))
      .length;

  // Code reviews this week
  final codeReviews = activity
      .where((a) =>
          a.type == ActivityType.codeReview &&
          a.timestamp.isAfter(weekAgo))
      .length;

  return {
    'totalMembers': members.length,
    'onlineCount': onlineCount,
    'offlineCount': members.length - onlineCount,
    'activeThisWeek': activeThisWeek,
    'inactiveCount': members.length - activeThisWeek,
    'totalCommits': totalCommits,
    'prsMergedThisWeek': prsMerged,
    'codeReviewsThisWeek': codeReviews,
    'recentActivityCount': activity.length,
    'isLoading': membersAsync is AsyncLoading || activityAsync is AsyncLoading,
    'hasError': membersAsync is AsyncError || activityAsync is AsyncError,
  };
});

// ─── Team Member Search ────────────────────────────────────────────────

/// Search query for filtering team members.
final teamMemberSearchProvider = StateProvider<String>((ref) => '');

/// Filtered team members based on search query.
///
/// Filters by name, email, and role.
final filteredTeamMembersProvider = Provider<AsyncValue<List<TeamMember>>>((ref) {
  final membersAsync = ref.watch(teamMembersProvider);
  final query = ref.watch(teamMemberSearchProvider).toLowerCase().trim();

  if (query.isEmpty) return membersAsync;

  return membersAsync.when(
    data: (members) {
      final filtered = members.where((m) {
        return m.name.toLowerCase().contains(query) ||
            m.email.toLowerCase().contains(query) ||
            m.role.name.toLowerCase().contains(query);
      }).toList();
      return AsyncValue.data(filtered);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, s) => AsyncValue.error(e, s),
  );
});

// ─── Team Hub Tab Index ────────────────────────────────────────────────

/// Current tab index in the team hub screen.
///
/// 0: Overview, 1: Chat, 2: Activity, 3: Projects, 4: Members
final teamHubTabProvider = StateProvider<int>((ref) => 0);
