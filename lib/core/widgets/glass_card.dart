import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:medicoscope/core/theme/app_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? color;
  final Border? border;

  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = AppTheme.radiusLarge,
    this.blur = 10.0,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ??
            Border.all(
              // Slightly brighter hairline border reads as polished glass.
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.35),
              width: 1,
            ),
        boxShadow: AppTheme.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              // Base fill kept as before, with a faint top-to-bottom sheen
              // gradient layered over it for a premium frosted-glass depth.
              color: color ??
                  (isDark
                      ? AppTheme.darkCard.withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.7)),
              gradient: color != null
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              Colors.white.withValues(alpha: 0.06),
                              Colors.white.withValues(alpha: 0.01),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.55),
                              Colors.white.withValues(alpha: 0.22),
                            ],
                    ),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            padding: padding ?? const EdgeInsets.all(AppTheme.spacingLarge),
            child: child,
          ),
        ),
      ),
    );
  }
}
