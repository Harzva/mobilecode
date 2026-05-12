import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import '../widgets/glass_card_widget.dart';

/// API Usage Screen - Tracks LLM API usage with monthly quota of 5000 calls
/// Features: quota tracking, daily bar chart, provider breakdown,
/// endpoint usage, optimization tips, and configurable alerts
class ApiUsageScreen extends StatefulWidget {
  const ApiUsageScreen({super.key});

  @override
  State<ApiUsageScreen> createState() => _ApiUsageScreenState();
}

class _ApiUsageScreenState extends State<ApiUsageScreen> {
  DateTime _currentMonth = DateTime.now();
  int _usedCalls = 3247;
  final int _quota = 5000;
  int? _selectedDay;

  // Mock daily usage data (tokens per day)
  final List<Map<String, dynamic>> _dailyUsage = List.generate(30, (index) {
    final providers = ['OpenAI', 'Claude', 'Gemini'];
    final provider = providers[index % 3];
    return {
      'day': index + 1,
      'tokens': (80 + (index * 7) % 150) * 1000,
      'calls': 50 + (index * 13) % 120,
      'provider': provider,
    };
  });

  final List<Map<String, dynamic>> _providers = [
    {'name': 'OpenAI', 'icon': Icons.auto_awesome, 'tokens': 1850000, 'calls': 1450, 'color': Color(0xFF10B981)},
    {'name': 'Claude', 'icon': Icons.psychology, 'tokens': 1200000, 'calls': 980, 'color': Color(0xFF8B5CF6)},
    {'name': 'Gemini', 'icon': Icons.smart_toy, 'tokens': 890000, 'calls': 817, 'color': Color(0xFF3B82F6)},
  ];

  final List<Map<String, dynamic>> _endpoints = [
    {'name': 'Chat', 'icon': Icons.chat_bubble, 'requests': 1850, 'avgTokens': 1450},
    {'name': 'Completion', 'icon': Icons.text_fields, 'requests': 980, 'avgTokens': 890},
    {'name': 'Embedding', 'icon': Icons.data_array, 'requests': 417, 'avgTokens': 512},
  ];

  final List<Map<String, dynamic>> _tips = [
    {
      'icon': Icons.compress,
      'title': '启用响应压缩',
      'desc': '使用 gzip 压缩可减少 40% 的传输数据量',
      'savings': '约 500 次/月',
    },
    {
      'icon': Icons.cached,
      'title': '启用缓存机制',
      'desc': '缓存相似查询结果，避免重复调用',
      'savings': '约 800 次/月',
    },
    {
      'icon': Icons.tune,
      'title': '优化 Token 长度',
      'desc': '限制上下文长度，精简输入内容',
      'savings': '约 300 次/月',
    },
  ];

  final List<Map<String, dynamic>> _alerts = [
    {'threshold': 80, 'enabled': true, 'triggered': true},
    {'threshold': 95, 'enabled': true, 'triggered': false},
    {'threshold': 100, 'enabled': false, 'triggered': false},
  ];

  double get _usagePercent => _usedCalls / _quota;
  int get _remaining => _quota - _usedCalls;
  Color get _statusColor {
    final pct = _usagePercent;
    if (pct < 0.5) return AppTheme.success;
    if (pct < 0.8) return AppTheme.warning;
    return AppTheme.error;
  }

  String get _resetDate {
    final nextMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    return '${nextMonth.year}-${nextMonth.month.toString().padLeft(2, '0')}-01';
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      _usedCalls = 1500 + (_currentMonth.month * 300) % 4800;
      _selectedDay = null;
    });
  }

  void _nextMonth() {
    if (_currentMonth.year == DateTime.now().year &&
        _currentMonth.month == DateTime.now().month) return;
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      _usedCalls = 1500 + (_currentMonth.month * 300) % 4800;
      _selectedDay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      body: CustomScrollView(
        slivers: [
          // Header with month selector
          SliverToBoxAdapter(
            child: _buildHeader(),
          ),

          // Quota card with circular progress
          SliverToBoxAdapter(
            child: _buildQuotaCard(),
          ),

          // Warning banner if approaching limit
          if (_usagePercent >= 0.8)
            SliverToBoxAdapter(
              child: _buildWarningBanner(),
            ),

          // Statistics row (4 glass cards)
          SliverToBoxAdapter(
            child: _buildStatisticsRow(),
          ),

          // Daily usage bar chart
          SliverToBoxAdapter(
            child: _buildUsageChart(),
          ),

          // Provider breakdown
          SliverToBoxAdapter(
            child: _buildProviderBreakdown(),
          ),

          // Endpoint usage grid
          SliverToBoxAdapter(
            child: _buildEndpointUsage(),
          ),

          // Optimization tips
          SliverToBoxAdapter(
            child: _buildOptimizationTips(),
          ),

          // Alerts section
          SliverToBoxAdapter(
            child: _buildAlertsSection(),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final monthStr = '${_currentMonth.year}年${_currentMonth.month}月';
    final isCurrentMonth = _currentMonth.year == DateTime.now().year &&
        _currentMonth.month == DateTime.now().month;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'API 用量',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: _prevMonth,
                      icon: const Icon(Icons.chevron_left, color: AppTheme.textSecondary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    Text(
                      monthStr,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    IconButton(
                      onPressed: isCurrentMonth ? null : _nextMonth,
                      icon: Icon(
                        Icons.chevron_right,
                        color: isCurrentMonth ? AppTheme.textTertiary : AppTheme.textSecondary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppTheme.violetGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.violet.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.show_chart, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCardWidget(
        glowEffect: true,
        glowColors: [_statusColor.withOpacity(0.4), AppTheme.violet.withOpacity(0.2)],
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Circular progress
              SizedBox(
                width: 160,
                height: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle
                    SizedBox(
                      width: 160,
                      height: 160,
                      child: CircularProgressIndicator(
                        value: 1,
                        strokeWidth: 12,
                        backgroundColor: AppTheme.surfaceElevated,
                        valueColor: const AlwaysStoppedAnimation(Colors.transparent),
                      ),
                    ),
                    // Progress arc
                    SizedBox(
                      width: 160,
                      height: 160,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: _usagePercent),
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return CircularProgressIndicator(
                            value: value,
                            strokeWidth: 12,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation(_statusColor),
                            strokeCap: StrokeCap.round,
                          );
                        },
                      ),
                    ),
                    // Center text
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(_usagePercent * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: _statusColor,
                          ),
                        ),
                        const Text(
                          '已使用',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Usage text
              Text(
                '已使用 $_usedCalls / $_quota 次',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              // Remaining with color
              Text(
                '剩余 $_remaining 次',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _statusColor,
                ),
              ),
              const SizedBox(height: 12),
              // Reset date
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, size: 14, color: AppTheme.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      '额度重置于 $_resetDate',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
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

  Widget _buildWarningBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.error.withOpacity(0.3),
              AppTheme.warning.withOpacity(0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.error.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '用量警报',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warning,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '您已使用超过 80% 的月度额度，请注意控制用量或升级套餐',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard('总请求数', '3,247', Icons.request_page, AppTheme.cyanLight),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStatCard('总Token数', '3.94M', Icons.data_usage, AppTheme.violet),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStatCard('成功率', '99.2%', Icons.check_circle, AppTheme.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStatCard('预估费用', '\$48.5', Icons.attach_money, AppTheme.cyan),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return GlassCardWidget(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageChart() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GlassCardWidget(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '每日用量',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  // Legend
                  Row(
                    children: [
                      _buildLegendDot('OpenAI', const Color(0xFF10B981)),
                      const SizedBox(width: 12),
                      _buildLegendDot('Claude', const Color(0xFF8B5CF6)),
                      const SizedBox(width: 12),
                      _buildLegendDot('Gemini', const Color(0xFF3B82F6)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Bar chart
              SizedBox(
                height: 160,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _dailyUsage.map((day) {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedDay = _selectedDay == day['day'] ? null : day['day'];
                          });
                        },
                        child: _buildBar(day),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              // X axis labels (every 5 days)
              Row(
                children: List.generate(6, (i) {
                  return Expanded(
                    flex: i < 5 ? 5 : 5,
                    child: Text(
                      '${i * 5 + 1}日',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  );
                }),
              ),
              // Tooltip for selected day
              if (_selectedDay != null) ...[
                const SizedBox(height: 12),
                _buildDayTooltip(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
        ),
      ],
    );
  }

  Widget _buildBar(Map<String, dynamic> day) {
    final maxTokens = 250000;
    final barHeight = (day['tokens'] as int) / maxTokens * 140;
    final isSelected = _selectedDay == day['day'];
    final Color barColor;
    switch (day['provider']) {
      case 'Claude':
        barColor = const Color(0xFF8B5CF6);
        break;
      case 'Gemini':
        barColor = const Color(0xFF3B82F6);
        break;
      default:
        barColor = const Color(0xFF10B981);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            height: barHeight.clamp(4, 140),
            decoration: BoxDecoration(
              color: barColor.withOpacity(isSelected ? 1.0 : 0.7),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: barColor.withOpacity(0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayTooltip() {
    final day = _dailyUsage.firstWhere((d) => d['day'] == _selectedDay);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.violet.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.calendar_today, size: 16, color: AppTheme.violet),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_currentMonth.month}月${day['day']}日',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '请求: ${day['calls']} 次  |  Tokens: ${(day['tokens'] as int) ~/ 1000}K  |  提供商: ${day['provider']}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderBreakdown() {
    final totalTokens = _providers.fold<int>(0, (sum, p) => sum + (p['tokens'] as int));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GlassCardWidget(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '提供商分布',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ..._providers.map((provider) {
                final pct = (provider['tokens'] as int) / totalTokens;
                return _buildProviderRow(provider, pct);
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderRow(Map<String, dynamic> provider, double pct) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (provider['color'] as Color).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  provider['icon'] as IconData,
                  size: 18,
                  color: provider['color'] as Color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          provider['name'] as String,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '${(pct * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: provider['color'] as Color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(provider['tokens'] as int) ~/ 1000}K tokens · ${provider['calls']} 次调用',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: AppTheme.surfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(provider['color'] as Color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointUsage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '端点用量',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Row(
            children: _endpoints.map((endpoint) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _buildEndpointCard(endpoint),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointCard(Map<String, dynamic> endpoint) {
    final colors = [AppTheme.violet, AppTheme.cyan, AppTheme.cyanLight];
    final idx = _endpoints.indexOf(endpoint);
    final color = colors[idx % colors.length];

    return GlassCardWidget(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                endpoint['icon'] as IconData,
                size: 20,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              endpoint['name'] as String,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${endpoint['requests']} 次请求',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '平均 ${endpoint['avgTokens']} tokens',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptimizationTips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '优化建议',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          ..._tips.map((tip) => _buildTipCard(tip)),
        ],
      ),
    );
  }

  Widget _buildTipCard(Map<String, dynamic> tip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCardWidget(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppTheme.auroraGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  tip['icon'] as IconData,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tip['title'] as String,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tip['desc'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tip['savings'] as String,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GlassCardWidget(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '用量警报',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showAddAlertDialog,
                    icon: const Icon(Icons.add, size: 16, color: AppTheme.violet),
                    label: const Text(
                      '添加',
                      style: TextStyle(fontSize: 12, color: AppTheme.violet),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._alerts.asMap().entries.map((entry) {
                final idx = entry.key;
                final alert = entry.value;
                return _buildAlertRow(alert, idx);
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertRow(Map<String, dynamic> alert, int index) {
    final threshold = alert['threshold'] as int;
    final enabled = alert['enabled'] as bool;
    final triggered = alert['triggered'] as bool;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: triggered ? AppTheme.error.withOpacity(0.1) : AppTheme.surfaceCard.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: triggered ? AppTheme.error.withOpacity(0.3) : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              triggered ? Icons.notifications_active : Icons.notifications_none,
              size: 20,
              color: triggered ? AppTheme.error : AppTheme.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '用量达到 $threshold% 时提醒',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: triggered ? AppTheme.error : AppTheme.textPrimary,
                    ),
                  ),
                  if (triggered)
                    const Text(
                      '已触发 - 当前用量超过此阈值',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.error,
                      ),
                    ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: (v) => setState(() => _alerts[index]['enabled'] = v),
              activeColor: AppTheme.violet,
              activeTrackColor: AppTheme.violetGlow,
              inactiveTrackColor: AppTheme.border,
            ),
            if (triggered)
              IconButton(
                onPressed: () => setState(() => _alerts[index]['triggered'] = false),
                icon: const Icon(Icons.close, size: 18, color: AppTheme.textTertiary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }

  void _showAddAlertDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: const Text(
          '添加警报阈值',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: '输入百分比 (1-100)',
            hintStyle: TextStyle(color: AppTheme.textTertiary),
            suffixText: '%',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null && val > 0 && val <= 100) {
                setState(() {
                  _alerts.add({
                    'threshold': val,
                    'enabled': true,
                    'triggered': false,
                  });
                });
              }
              Navigator.pop(context);
            },
            child: const Text('添加', style: TextStyle(color: AppTheme.violet)),
          ),
        ],
      ),
    );
  }
}
