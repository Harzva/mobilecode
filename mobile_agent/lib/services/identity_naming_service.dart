import 'package:shared_preferences/shared_preferences.dart';

class IdentityNamingPreferences {
  const IdentityNamingPreferences({
    this.userDisplayName = '',
    this.mobileCodeNickname = 'MobileCode',
    this.assistantPersonaLabel = 'Codex',
  });

  final String userDisplayName;
  final String mobileCodeNickname;
  final String assistantPersonaLabel;

  bool get hasUserDisplayName => userDisplayName.trim().isNotEmpty;

  IdentityNamingPreferences copyWith({
    String? userDisplayName,
    String? mobileCodeNickname,
    String? assistantPersonaLabel,
  }) {
    return IdentityNamingPreferences(
      userDisplayName: _clean(userDisplayName ?? this.userDisplayName),
      mobileCodeNickname: _clean(
        mobileCodeNickname ?? this.mobileCodeNickname,
        fallback: 'MobileCode',
      ),
      assistantPersonaLabel: _clean(
        assistantPersonaLabel ?? this.assistantPersonaLabel,
        fallback: 'Codex',
      ),
    );
  }

  Map<String, String> toJson() => {
        'userDisplayName': userDisplayName,
        'mobileCodeNickname': mobileCodeNickname,
        'assistantPersonaLabel': assistantPersonaLabel,
      };

  factory IdentityNamingPreferences.fromJson(Map<String, Object?> json) {
    return IdentityNamingPreferences(
      userDisplayName: _clean(json['userDisplayName']?.toString() ?? ''),
      mobileCodeNickname: _clean(
        json['mobileCodeNickname']?.toString() ?? '',
        fallback: 'MobileCode',
      ),
      assistantPersonaLabel: _clean(
        json['assistantPersonaLabel']?.toString() ?? '',
        fallback: 'Codex',
      ),
    );
  }

  String compactContextBlock() {
    final lines = <String>[
      '[Identity]',
      'mobileCodeNickname: $mobileCodeNickname',
      'assistantPersonaLabel: $assistantPersonaLabel',
      if (hasUserDisplayName) 'userDisplayName: $userDisplayName',
      'privacy: localOnly; doNotPublishToLogsOrTelemetry',
    ];
    return lines.join('\n');
  }

  static String _clean(String value, {String fallback = ''}) {
    final trimmed = value.trim().replaceAll(RegExp(r'[\r\n\t]'), ' ');
    final compact = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) return fallback;
    return compact.length <= 48 ? compact : compact.substring(0, 48);
  }
}

class IdentityNamingService {
  IdentityNamingService({SharedPreferences? prefs}) : _prefs = prefs;

  static const _userDisplayNameKey = 'identity.userDisplayName';
  static const _mobileCodeNicknameKey = 'identity.mobileCodeNickname';
  static const _assistantPersonaLabelKey = 'identity.assistantPersonaLabel';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _preferences() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<IdentityNamingPreferences> load() async {
    final prefs = await _preferences();
    return IdentityNamingPreferences(
      userDisplayName: prefs.getString(_userDisplayNameKey) ?? '',
      mobileCodeNickname: prefs.getString(_mobileCodeNicknameKey) ?? 'MobileCode',
      assistantPersonaLabel:
          prefs.getString(_assistantPersonaLabelKey) ?? 'Codex',
    );
  }

  Future<void> save(IdentityNamingPreferences preferences) async {
    final prefs = await _preferences();
    final clean = preferences.copyWith();
    await prefs.setString(_userDisplayNameKey, clean.userDisplayName);
    await prefs.setString(_mobileCodeNicknameKey, clean.mobileCodeNickname);
    await prefs.setString(
      _assistantPersonaLabelKey,
      clean.assistantPersonaLabel,
    );
  }

  Future<String> compactContextBlock() async {
    final preferences = await load();
    return preferences.compactContextBlock();
  }
}
