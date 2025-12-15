import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 18,
    this.colorOpacity = 0.08,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double colorOpacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassSurface(colorOpacity),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.glassSurface(colorOpacity + 0.04)),
      ),
      child: child,
    );
  }
}

