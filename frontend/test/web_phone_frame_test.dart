import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/web_phone_frame.dart';

Widget _app(Key key) => MaterialApp(
      builder: (c, child) => WebPhoneFrame(child: child!),
      home: Scaffold(key: key, body: const SizedBox.expand()),
    );

void _setSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('wide screen: content is a 440 px column', (tester) async {
    _setSurface(tester, const Size(1280, 800));
    final k = GlobalKey();
    await tester.pumpWidget(_app(k));

    expect(tester.getSize(find.byKey(k)).width, 440);
    expect(MediaQuery.of(k.currentContext!).size.width, 440);
  });

  testWidgets('narrow screen: content fills the screen', (tester) async {
    _setSurface(tester, const Size(390, 844));
    final k = GlobalKey();
    await tester.pumpWidget(_app(k));

    expect(tester.getSize(find.byKey(k)).width, 390);
  });

  testWidgets('breakpoint: exactly 520 px is full width', (tester) async {
    _setSurface(tester, const Size(520, 800));
    final k = GlobalKey();
    await tester.pumpWidget(_app(k));

    expect(tester.getSize(find.byKey(k)).width, 520);
  });

  testWidgets('breakpoint: 521 px is the 440 px column', (tester) async {
    _setSurface(tester, const Size(521, 800));
    final k = GlobalKey();
    await tester.pumpWidget(_app(k));

    expect(tester.getSize(find.byKey(k)).width, 440);
  });

  testWidgets('wide screen: dialogs stay inside the column', (tester) async {
    _setSurface(tester, const Size(1280, 800));
    final k = GlobalKey();
    await tester.pumpWidget(_app(k));

    // Wider than the column, so it only fits inside if the frame constrains it.
    showDialog<void>(
      context: k.currentContext!,
      builder: (_) => const Dialog(child: SizedBox(height: 100, width: 2000)),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(Dialog));
    final left = (1280 - 440) / 2;
    expect(rect.left, greaterThanOrEqualTo(left));
    expect(rect.right, lessThanOrEqualTo(left + 440));
  });
}
