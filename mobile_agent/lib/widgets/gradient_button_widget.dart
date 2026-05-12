import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

/// Aurora gradient button widget
/// Animated gradient background (violet -> cyan)
/// Ripple effect, loading state, disabled state
class GradientButtonWidget extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final List<Color>? gradientColors;
  final TextStyle? textStyle;

  const GradientButtonWidget({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.width,
    this.height,
    this.padding,
    this.borderRadius = 12.0,
    this.gradientColors,
    this.textStyle,
  });

  @override
  State<GradientButtonWidget> createState() => _GradientButtonWidgetState();
}

class _GradientButtonWidgetState extends State<GradientButtonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  bool get _isActive =>
      !widget.isLoading && !widget.isDisabled && widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final colors = widget.gradientColors ??
        [AppTheme.violet, AppTheme.violetLight, AppTheme.cyan];

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glowOpacity = 0.15 + (_glowController.value * 0.1);

        return GestureDetector(
          onTapDown: _isActive ? (_) => setState(() => _isPressed = true) : null,
          onTapUp: _isActive
              ? (_) {
                  setState(() => _isPressed = false);
                  widget.onPressed?.call();
                }
              : null,
          onTapCancel: _isActive
              ? () => setState(() => _isPressed = false)
              : null,
          child: AnimatedContainer(
            duration: AppTheme.animFast,
            width: widget.width,
            height: widget.height,
            padding: widget.padding ??
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: widget.isDisabled
                  ? LinearGradient(
                      colors: [
                        AppTheme.textTertiary.withOpacity(0.3),
                        AppTheme.textTertiary.withOpacity(0.2),
                      ],
                    )
                  : LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const [0.0, 0.5, 1.0],
                    ),
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: _isActive && !widget.isLoading
                  ? [
                      BoxShadow(
                        color: AppTheme.violetGlow.withOpacity(glowOpacity),
                        blurRadius: 12 + (_glowController.value * 8),
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: AppTheme.cyanGlow.withOpacity(glowOpacity * 0.5),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
              transform: _isPressed
                  ? (Matrix4.identity()..scale(0.97))
                  : null,
            ),
            child: widget.isLoading
                ? _buildLoadingIndicator()
                : _buildButtonContent(),
          ),
        );
      },
    );
  }

  Widget _buildButtonContent() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(
            widget.icon,
            size: 18,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
        ],
        Text(
          widget.label,
          style: widget.textStyle ??
              const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.white.withOpacity(0.9),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }
}

/// Secondary button with outline style
class OutlineGradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double? width;
  final double? height;
  final double borderRadius;

  const OutlineGradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.width,
    this.height,
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: AppTheme.violet.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: AppTheme.violetLight,
              ),
              const SizedBox(width: 8),
            ],
            ShaderMask(
              shaderCallback: (bounds) {
                return AppTheme.auroraGradient.createShader(bounds);
              },
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon button with gradient background
class GradientIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final List<Color>? gradientColors;

  const GradientIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.iconSize = 22,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ?? [AppTheme.violet, AppTheme.cyan];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: onPressed != null
                ? [
                    BoxShadow(
                      color: AppTheme.violetGlow.withOpacity(0.2),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
