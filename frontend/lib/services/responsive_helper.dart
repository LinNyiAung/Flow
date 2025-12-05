import 'package:flutter/material.dart';

class ResponsiveHelper {
  final BuildContext context;
  
  ResponsiveHelper(this.context);
  
  // Get screen width
  double get screenWidth => MediaQuery.of(context).size.width;
  
  // Get screen height
  double get screenHeight => MediaQuery.of(context).size.height;
  
  // Check if device is small (width < 360)
  bool get isSmallDevice => screenWidth < 360;
  
  // Check if device is medium (360 <= width < 400)
  bool get isMediumDevice => screenWidth >= 360 && screenWidth < 400;
  
  // Check if device is large (width >= 400)
  bool get isLargeDevice => screenWidth >= 400;
  
  // Responsive font sizes
  double fontSize({
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    if (screenWidth < 360) {
      return mobile * 0.5; // 10% smaller for very small devices
    } else if (screenWidth < 400) {
      return mobile * 0.85;
    } else if (screenWidth < 600) {
      return tablet ?? mobile * 1.1;
    } else {
      return desktop ?? tablet ?? mobile * 1.2;
    }
  }
  
  // Quick font size getters (optimized for mobile 360-400px)
  double get fs10 => fontSize(mobile: 10);
  double get fs11 => fontSize(mobile: 11);
  double get fs12 => fontSize(mobile: 12);
  double get fs13 => fontSize(mobile: 13);
  double get fs14 => fontSize(mobile: 14);
  double get fs16 => fontSize(mobile: 16);
  double get fs18 => fontSize(mobile: 18);
  double get fs20 => fontSize(mobile: 20);
  double get fs24 => fontSize(mobile: 24);
  double get fs28 => fontSize(mobile: 28);
  double get fs32 => fontSize(mobile: 32);
  
  // Responsive spacing
  double spacing({
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    if (screenWidth < 360) {
      return mobile * 0.85;
    } else if (screenWidth < 400) {
      return mobile;
    } else if (screenWidth < 600) {
      return tablet ?? mobile * 1.1;
    } else {
      return desktop ?? tablet ?? mobile * 1.2;
    }
  }
  
  // Quick spacing getters
  double get sp4 => spacing(mobile: 4);
  double get sp8 => spacing(mobile: 8);
  double get sp12 => spacing(mobile: 12);
  double get sp16 => spacing(mobile: 16);
  double get sp20 => spacing(mobile: 20);
  double get sp24 => spacing(mobile: 24);
  double get sp30 => spacing(mobile: 30);
  double get sp32 => spacing(mobile: 32);
  
  // Responsive icon sizes
  double iconSize({
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    if (screenWidth < 360) {
      return mobile * 0.9;
    } else if (screenWidth < 400) {
      return mobile;
    } else if (screenWidth < 600) {
      return tablet ?? mobile * 1.1;
    } else {
      return desktop ?? tablet ?? mobile * 1.2;
    }
  }
  
  // Quick icon size getters
  double get icon16 => iconSize(mobile: 16);
  double get icon18 => iconSize(mobile: 18);
  double get icon20 => iconSize(mobile: 20);
  double get icon24 => iconSize(mobile: 24);
  double get icon28 => iconSize(mobile: 28);
  double get icon48 => iconSize(mobile: 48);
  double get icon50 => iconSize(mobile: 50);
  double get icon64 => iconSize(mobile: 64);
  
  // Responsive padding
  EdgeInsets padding({
    double? all,
    double? horizontal,
    double? vertical,
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    final multiplier = screenWidth < 360 ? 0.85 : 1.0;
    
    if (all != null) {
      return EdgeInsets.all(all * multiplier);
    }
    
    return EdgeInsets.only(
      left: (left ?? horizontal ?? 0) * multiplier,
      top: (top ?? vertical ?? 0) * multiplier,
      right: (right ?? horizontal ?? 0) * multiplier,
      bottom: (bottom ?? vertical ?? 0) * multiplier,
    );
  }
  
  // Responsive border radius
  double borderRadius(double mobile) {
    if (screenWidth < 360) {
      return mobile * 0.9;
    }
    return mobile;
  }
  
  // Card height based on content
  double cardHeight({required double baseHeight}) {
    if (screenWidth < 360) {
      return baseHeight * 0.9;
    }
    return baseHeight;
  }
  
  // Safe horizontal padding (prevents edge overflow)
  double get safeHorizontalPadding {
    if (screenWidth < 360) {
      return 12;
    } else if (screenWidth < 400) {
      return 16;
    } else {
      return 20;
    }
  }
  
  // Container width percentage
  double widthPercent(double percent) {
    return screenWidth * (percent / 100);
  }
  
  // Container height percentage
  double heightPercent(double percent) {
    return screenHeight * (percent / 100);
  }
}

// Extension for easy access
extension ResponsiveExtension on BuildContext {
  ResponsiveHelper get responsive => ResponsiveHelper(this);
}