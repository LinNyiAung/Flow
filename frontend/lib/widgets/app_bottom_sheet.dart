import 'package:flutter/material.dart';

/// Shows a bottom sheet using the app's standard spec (surface fill, top
/// radius 28, drag handle, 20dp padding + safe-area bottom inset) so manage
/// funds, category pickers, wallets and capture-source sheets all share one
/// shape. The theme's [BottomSheetThemeData] already supplies the shape,
/// drag handle and colour — this just adds the consistent content padding.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
      ),
      child: builder(context),
    ),
  );
}
