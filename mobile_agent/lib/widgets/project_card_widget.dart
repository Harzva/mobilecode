import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

/// Project card widget with glassmorphism effect
/// Language icon/badge, file count, last modified time, favorite star
class ProjectCardWidget extends StatelessWidget {
  final String name;
  final String? description;
  final String language;
  final int fileCount;
  final int? lineCount;
  final bool isFavorite;
  final DateTime modifiedAt;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onLongPress;

  const ProjectCardWidget({
    super.key,
    required this.name,
    this.description,
    required this.language,
    required this.fileCount,
    this.lineCount,
    this.isFavorite = false,
    required this.modifiedAt,
    this.onTap,
    this.onFavoriteToggle,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.surfaceCard.withOpacity(0.8),
              AppTheme.surfaceDark.withOpacity(0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFavorite
                ? AppTheme.violet.withOpacity(0.4)
                : AppTheme.border.withOpacity(0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isFavorite
                  ? AppTheme.violetGlow.withOpacity(0.15)
                  : Colors.black.withOpacity(0.1),
              blurRadius: isFavorite ? 16 : 8,
              spreadRadius: isFavorite ? 1 : 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Subtle gradient glow for favorite
              if (isFavorite)
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.violet.withOpacity(0.08),
                    ),
                  ),
                ),

              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: language + favorite
                    Row(
                      children: [
                        // Language badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _languageColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _languageColor.withOpacity(0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _languageColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _languageDisplay,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: _languageColor,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Spacer(),

                        // Favorite star
                        GestureDetector(
                          onTap: onFavoriteToggle,
                          child: AnimatedScale(
                            scale: isFavorite ? 1.1 : 1.0,
                            duration: AppTheme.animFast,
                            child: Icon(
                              isFavorite ? Icons.star : Icons.star_border,
                              size: 20,
                              color: isFavorite
                                  ? AppTheme.warning
                                  : AppTheme.textTertiary.withOpacity(0.4),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Project name
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Description
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const Spacer(),

                    // Bottom row: file count + modified time
                    Row(
                      children: [
                        Icon(
                          Icons.insert_drive_file_outlined,
                          size: 13,
                          color: AppTheme.textTertiary.withOpacity(0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$fileCount 文件',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary.withOpacity(0.6),
                          ),
                        ),
                        if (lineCount != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppTheme.textTertiary.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${_formatLineCount(lineCount!)} 行',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textTertiary.withOpacity(0.6),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          _timeAgo,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _languageDisplay {
    final Map<String, String> names = {
      'dart': 'Dart',
      'python': 'Python',
      'javascript': 'JS',
      'typescript': 'TS',
      'go': 'Go',
      'rust': 'Rust',
      'swift': 'Swift',
      'kotlin': 'Kotlin',
      'java': 'Java',
      'cpp': 'C++',
      'c': 'C',
      'csharp': 'C#',
      'ruby': 'Ruby',
      'php': 'PHP',
      'html': 'HTML',
      'css': 'CSS',
    };
    return names[language.toLowerCase()] ?? language.toUpperCase();
  }

  Color get _languageColor {
    final Map<String, Color> colors = {
      'dart': const Color(0xFF00B4AB),
      'python': const Color(0xFF3776AB),
      'javascript': const Color(0xFFF7DF1E),
      'typescript': const Color(0xFF3178C6),
      'go': const Color(0xFF00ADD8),
      'rust': const Color(0xFFDEA584),
      'swift': const Color(0xFFFFAC45),
      'kotlin': const Color(0xFF7F52FF),
      'java': const Color(0xFF007396),
      'cpp': const Color(0xFF00599C),
      'c': const Color(0xFF555555),
      'csharp': const Color(0xFF68217A),
      'ruby': const Color(0xFFCC342D),
      'php': const Color(0xFF4F5D95),
      'html': const Color(0xFFE34F26),
      'css': const Color(0xFF1572B6),
    };
    return colors[language.toLowerCase()] ?? AppTheme.textSecondary;
  }

  String get _timeAgo {
    final now = DateTime.now();
    final diff = now.difference(modifiedAt);

    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}周前';
    return '${diff.inDays ~/ 30}个月前';
  }

  String _formatLineCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }
}
