import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

/// Snippet card widget
/// Syntax highlighted preview (first 5 lines), title, tags, source badge
class SnippetCardWidget extends StatelessWidget {
  final String title;
  final String code;
  final String language;
  final List<String> tags;
  final String source;
  final DateTime createdAt;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;

  const SnippetCardWidget({
    super.key,
    required this.title,
    required this.code,
    required this.language,
    required this.tags,
    required this.source,
    required this.createdAt,
    this.isFavorite = false,
    this.onTap,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.surfaceCard.withOpacity(0.8),
              AppTheme.surfaceDark.withOpacity(0.5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.border.withOpacity(0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onFavoriteToggle != null)
                    GestureDetector(
                      onTap: onFavoriteToggle,
                      child: Icon(
                        isFavorite ? Icons.star : Icons.star_border,
                        size: 18,
                        color: isFavorite
                            ? AppTheme.warning
                            : AppTheme.textTertiary.withOpacity(0.3),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // Code preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.deepSpace,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.border.withOpacity(0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Code preview (first 5 lines)
                    Text(
                      _codePreview,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: AppTheme.fontCode,
                        color: AppTheme.textSecondary.withOpacity(0.8),
                        height: 1.5,
                      ),
                    ),
                    // Line count indicator
                    if (_totalLines > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '... +${_totalLines - 5} 行',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Tags and source row
              Row(
                children: [
                  // Source badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _sourceColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _sourceIcon,
                          size: 12,
                          color: _sourceColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _sourceLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: _sourceColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Tags
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: tags.take(3).map((tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.violet.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.violetLight,
                              ),
                            ),
                          )).toList(),
                    ),
                  ),

                  // Language badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      language.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Time
              Text(
                _timeAgo,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _codePreview {
    final lines = code.split('\n');
    if (lines.length <= 5) return code;
    return lines.take(5).join('\n');
  }

  int get _totalLines => code.split('\n').length;

  IconData get _sourceIcon {
    switch (source) {
      case 'voice':
        return Icons.mic;
      case 'screenshot':
        return Icons.camera_alt;
      case 'github':
        return Icons.code;
      case 'ai':
        return Icons.auto_awesome;
      default:
        return Icons.edit;
    }
  }

  Color get _sourceColor {
    switch (source) {
      case 'voice':
        return AppTheme.cyan;
      case 'screenshot':
        return const Color(0xFF9C27B0);
      case 'github':
        return AppTheme.textSecondary;
      case 'ai':
        return AppTheme.violetLight;
      default:
        return AppTheme.textTertiary;
    }
  }

  String get _sourceLabel {
    switch (source) {
      case 'voice':
        return '语音';
      case 'screenshot':
        return '截图';
      case 'github':
        return 'GitHub';
      case 'ai':
        return 'AI';
      default:
        return '手动';
    }
  }

  String get _timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}周前';
    return '${diff.inDays ~/ 30}个月前';
  }
}
