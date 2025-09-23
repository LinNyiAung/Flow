// widgets/typing_indicator.dart - Create this as a separate reusable widget

import 'package:flutter/material.dart';
import 'dart:math';

class TypingIndicator extends StatefulWidget {
  final Color? dotColor;
  final double dotSize;
  final Duration animationDuration;

  const TypingIndicator({
    Key? key,
    this.dotColor,
    this.dotSize = 6.0,
    this.animationDuration = const Duration(milliseconds: 1500),
  }) : super(key: key);

  @override
  _TypingIndicatorState createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final animationValue = (_animationController.value - delay).clamp(0.0, 1.0);
            final scale = (sin(animationValue * 2 * pi) * 0.5 + 0.5) * 0.5 + 0.5;
            
            return Container(
              margin: EdgeInsets.symmetric(horizontal: 1),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: widget.dotColor ?? Colors.grey[600],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}