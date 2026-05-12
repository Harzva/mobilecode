import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════════

/// The role of a team member within the organization.
///
/// Roles are hierarchical: [owner] > [admin] > [member] > [viewer].
/// Each role grants a specific set of permissions that determine
/// what actions the member can perform.
enum TeamRole {
  /// Full control of the team — billing, deletion, role assignment.
  owner,

  /// Can manage members, projects, and knowledge base.
  admin,

  /// Standard collaborator — can edit, create, and comment.
  member,

  /// Read-only access to shared resources.
  viewer,
}

/// Extension providing display metadata and permission helpers for [TeamRole].
extension TeamRoleExt on TeamRole {
  /// Human-readable label for the role.
  String get label {
    switch (this) {
      case TeamRole.owner:
        return 'Owner';
      case TeamRole.admin:
        return 'Admin';
      case TeamRole.member:
        return 'Member';
      case TeamRole.viewer:
        return 'Viewer';
    }
  }

  /// Icon data representing the role.
  IconData get icon {
    switch (this) {
      case TeamRole.owner:
        return Icons.verified_user;
      case TeamRole.admin:
        return Icons.shield;
      case TeamRole.member:
        return Icons.person;
      case TeamRole.viewer:
        return Icons.visibility;
    }
  }

  /// Theme color associated with the role.
  Color get color {
    switch (this) {
      case TeamRole.owner:
        return AppTheme.warning;
      case TeamRole.admin:
        return AppTheme.primary;
      case TeamRole.member:
        return AppTheme.accent;
      case TeamRole.viewer:
        return AppTheme.textTertiary;
    }
  }

  /// Whether this role can assign or modify other members' roles.
  bool get canManageRoles => this == TeamRole.owner || this == TeamRole.admin;

  /// Whether this role can invite new members.
  bool get canInvite => this == TeamRole.owner || this == TeamRole.admin;

  /// Whether this role can edit team projects.
  bool get canEdit => this == TeamRole.owner || this == TeamRole.admin || this == TeamRole.member;

  /// Whether this role can delete projects or knowledge articles.
  bool get canDelete => this == TeamRole.owner || this == TeamRole.admin;

  /// Whether this role can manage billing and quotas.
  bool get canManageBilling => this == TeamRole.owner;

  /// Whether this role can pin or moderate knowledge base articles.
  bool get canModerate => this == TeamRole.owner || this == TeamRole.admin;
}

/// The status of a team member's account.
///
/// Determines whether the member can actively participate
/// in team collaboration features.
enum MemberStatus {
  /// Fully active and can participate in all features.
  active,

  /// Invitation sent but not yet accepted.
  pending,

  /// Account deactivated but retains historical data.
  inactive,

  /// Temporarily suspended by an admin or owner.
  suspended,
}

/// Extension providing display metadata for [MemberStatus].
extension MemberStatusExt on MemberStatus {
  /// Human-readable label for the status.
  String get label {
    switch (this) {
      case MemberStatus.active:
        return 'Active';
      case MemberStatus.pending:
        return 'Pending';
      case MemberStatus.inactive:
        return 'Inactive';
      case MemberStatus.suspended:
        return 'Suspended';
    }
  }

  /// Theme color representing the status.
  Color get color {
    switch (this) {
      case MemberStatus.active:
        return AppTheme.success;
      case MemberStatus.pending:
        return AppTheme.warning;
      case MemberStatus.inactive:
        return AppTheme.textDisabled;
      case MemberStatus.suspended:
        return AppTheme.error;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Model
// ═══════════════════════════════════════════════════════════════════════════

/// {@template team_member}
/// Represents a member of a team in Mobile Agent.
///
/// Each team member has a [role] that determines their permissions,
/// a [status] that controls their access state, and tracking fields
/// for contribution metrics.
///
/// ## Usage
/// ```dart
/// final member = TeamMember(
///   id: 'user_123',
///   name: 'Alice Chen',
///   email: 'alice@example.com',
///   role: TeamRole.admin,
///   status: MemberStatus.active,
/// );
/// ```
/// {@endtemplate}
@immutable
class TeamMember {
  /// Unique identifier for the member (usually a UUID).
  final String id;

  /// Display name of the member.
  final String name;

  /// Email address used for invitations and notifications.
  final String email;

  /// Optional URL to the member's avatar image.
  final String? avatarUrl;

  /// Role within the team (determines permissions).
  final TeamRole role;

  /// When the member first joined or was invited to the team.
  final DateTime joinedAt;

  /// Current account status.
  final MemberStatus status;

  /// Granular permission overrides keyed by permission name.
  ///
  /// Common keys: `canEdit`, `canDelete`, `canInvite`, `canShare`.
  /// When a key is absent, the default for the member's [role] applies.
  final Map<String, bool> permissions;

  /// Optional short biography or job title.
  final String? bio;

  /// List of skills or expertise tags.
  final List<String> skills;

  /// When the member was last active in the app.
  final DateTime lastActiveAt;

  /// Total lines of code contributed across all team projects.
  final int contributedLines;

  /// Total tasks or assignments completed.
  final int completedTasks;

  /// Creates a [TeamMember] with all fields specified.
  ///
  /// Use [TeamMember.create] for creating new members with sensible defaults.
  const TeamMember({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.role,
    required this.joinedAt,
    required this.status,
    required this.permissions,
    this.bio,
    required this.skills,
    required this.lastActiveAt,
    required this.contributedLines,
    required this.completedTasks,
  });

  /// Factory for creating a new team member with sensible defaults.
  ///
  /// [id], [name], and [email] are required. [role] defaults to [TeamRole.member],
  /// [status] defaults to [MemberStatus.active].
  factory TeamMember.create({
    required String id,
    required String name,
    required String email,
    String? avatarUrl,
    TeamRole role = TeamRole.member,
    MemberStatus status = MemberStatus.active,
    String? bio,
    List<String>? skills,
  }) {
    final now = DateTime.now();
    return TeamMember(
      id: id,
      name: name,
      email: email,
      avatarUrl: avatarUrl,
      role: role,
      joinedAt: now,
      status: status,
      permissions: const {},
      bio: bio,
      skills: skills ?? const [],
      lastActiveAt: now,
      contributedLines: 0,
      completedTasks: 0,
    );
  }

  // ── JSON Serialization ────────────────────────────────────────────────

  /// Creates a [TeamMember] from a JSON map.
  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      role: TeamRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => TeamRole.member,
      ),
      joinedAt: DateTime.parse(json['joinedAt'] as String),
      status: MemberStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MemberStatus.active,
      ),
      permissions: (json['permissions'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as bool)) ??
          const {},
      bio: json['bio'] as String?,
      skills: (json['skills'] as List<dynamic>?)?.cast<String>() ?? const [],
      lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
      contributedLines: json['contributedLines'] as int? ?? 0,
      completedTasks: json['completedTasks'] as int? ?? 0,
    );
  }

  /// Converts this member to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'role': role.name,
      'joinedAt': joinedAt.toIso8601String(),
      'status': status.name,
      'permissions': permissions,
      if (bio != null) 'bio': bio,
      'skills': skills,
      'lastActiveAt': lastActiveAt.toIso8601String(),
      'contributedLines': contributedLines,
      'completedTasks': completedTasks,
    };
  }

  // ── Copy & Update ─────────────────────────────────────────────────────

  /// Creates a copy with specified fields replaced.
  TeamMember copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarUrl,
    TeamRole? role,
    DateTime? joinedAt,
    MemberStatus? status,
    Map<String, bool>? permissions,
    String? bio,
    List<String>? skills,
    DateTime? lastActiveAt,
    int? contributedLines,
    int? completedTasks,
  }) {
    return TeamMember(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      status: status ?? this.status,
      permissions: permissions ?? this.permissions,
      bio: bio ?? this.bio,
      skills: skills ?? this.skills,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      contributedLines: contributedLines ?? this.contributedLines,
      completedTasks: completedTasks ?? this.completedTasks,
    );
  }

  // ── Computed Properties ───────────────────────────────────────────────

  /// Returns the initials from the member's name (up to 2 characters).
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
  }

  /// Whether this member is currently active and can participate.
  bool get isActive => status == MemberStatus.active;

  /// Whether this member has a pending invitation.
  bool get isPending => status == MemberStatus.pending;

  /// Whether this member can perform the given action based on role.
  ///
  /// [action] should be one of: `'edit'`, `'delete'`, `'invite'`, `'manageRoles'`,
  /// `'billing'`, or a custom key from [permissions].
  bool can(String action) {
    // Check explicit permission override first.
    if (permissions.containsKey('can${action[0].toUpperCase()}${action.substring(1)}')) {
      return permissions['can${action[0].toUpperCase()}${action.substring(1)}']!;
    }
    // Fall back to role-based defaults.
    switch (action.toLowerCase()) {
      case 'edit':
        return role.canEdit;
      case 'delete':
        return role.canDelete;
      case 'invite':
        return role.canInvite;
      case 'manageroles':
        return role.canManageRoles;
      case 'billing':
        return role.canManageBilling;
      case 'moderate':
        return role.canModerate;
      default:
        return false;
    }
  }

  // ── Object overrides ──────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TeamMember &&
        other.id == id &&
        other.name == name &&
        other.email == email &&
        other.avatarUrl == avatarUrl &&
        other.role == role &&
        other.joinedAt == joinedAt &&
        other.status == status &&
        mapEquals(other.permissions, permissions) &&
        other.bio == bio &&
        listEquals(other.skills, skills) &&
        other.lastActiveAt == lastActiveAt &&
        other.contributedLines == contributedLines &&
        other.completedTasks == completedTasks;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        email,
        avatarUrl,
        role,
        joinedAt,
        status,
        Object.hashAll(permissions.entries),
        bio,
        Object.hashAll(skills),
        lastActiveAt,
        contributedLines,
        completedTasks,
      );

  @override
  String toString() {
    return 'TeamMember(id: $id, name: $name, email: $email, role: ${role.name}, '
        'status: ${status.name})';
  }
}
