import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

/// Collapsible sidebar widget
/// Navigation items with icons, collapse/expand animation
/// Active state highlighting, mini mode (icons only)
class SidebarWidget extends StatefulWidget {
  final List<SidebarItem> items;
  final int selectedIndex;
  final Function(int)? onItemSelected;
  final bool initiallyExpanded;
  final double expandedWidth;
  final double collapsedWidth;

  const SidebarWidget({
    super.key,
    required this.items,
    this.selectedIndex = 0,
    this.onItemSelected,
    this.initiallyExpanded = true,
    this.expandedWidth = 220,
    this.collapsedWidth = 64,
  });

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _animationController = AnimationController(
      vsync: this,
      duration: AppTheme.animNormal,
      value: _isExpanded ? 1.0 : 0.0,
    );
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final width = Tween<double>(
          begin: widget.collapsedWidth,
          end: widget.expandedWidth,
        ).evaluate(_animationController);

        return Container(
          width: width,
          decoration: const BoxDecoration(
            color: AppTheme.surfaceDark,
            border: Border(
              right: BorderSide(color: AppTheme.divider),
            ),
          ),
          child: Column(
            children: [
              // Toggle button
              _buildToggleButton(),

              const Divider(color: AppTheme.divider, height: 1),

              // Navigation items
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    return _buildNavItem(index);
                  },
                ),
              ),

              // Bottom section
              const Divider(color: AppTheme.divider, height: 1),
              _buildBottomItems(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToggleButton() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisAlignment: _isExpanded
              ? MainAxisAlignment.end
              : MainAxisAlignment.center,
          children: [
            AnimatedRotation(
              turns: _isExpanded ? 0 : 0.5,
              duration: AppTheme.animNormal,
              child: const Icon(
                Icons.chevron_left,
                size: 20,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final item = widget.items[index];
    final isSelected = index == widget.selectedIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => widget.onItemSelected?.call(index),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              gradient: isSelected ? AppTheme.violetGradient : null,
              color: isSelected ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? item.selectedIcon ?? item.icon : item.icon,
                  size: 20,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
                if (_isExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.2)
                            : AppTheme.error.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${item.badge}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.white,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomItems() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBottomItem(
          icon: Icons.settings,
          label: '设置',
          onTap: () {},
        ),
        _buildBottomItem(
          icon: Icons.help_outline,
          label: '帮助',
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildBottomItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: AppTheme.textTertiary,
                ),
                if (_isExpanded) ...[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

/// Sidebar item data model
class SidebarItem {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final int? badge;

  const SidebarItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.badge,
  });
}

/// Mini sidebar (icons only, always collapsed)
class MiniSidebar extends StatelessWidget {
  final List<SidebarItem> items;
  final int selectedIndex;
  final Function(int)? onItemSelected;

  const MiniSidebar({
    super.key,
    required this.items,
    this.selectedIndex = 0,
    this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(
          right: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isSelected = index == selectedIndex;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Tooltip(
                message: item.label,
                preferBelow: false,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => onItemSelected?.call(index),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 48,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: isSelected ? AppTheme.violetGradient : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            isSelected
                                ? item.selectedIcon ?? item.icon
                                : item.icon,
                            size: 22,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                          if (item.badge != null)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: const BoxDecoration(
                                  color: AppTheme.error,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${item.badge}',
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
