import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/mascot.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
  await tester.pumpAndSettle();
}

void main() {
  group('assets', () {
    test('every pose has its SVG in assets/mascot/, listed in pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/mascot/'));
      for (final pose in MascotPose.values) {
        expect(pose.asset, startsWith('assets/mascot/'));
        expect(File(pose.asset).existsSync(), isTrue, reason: pose.asset);
      }
    });

    test('no pose carries text (no extra fonts needed)', () {
      for (final pose in MascotPose.values) {
        final svg = File(pose.asset).readAsStringSync();
        expect(svg.contains('<text'), isFalse, reason: pose.asset);
      }
    });

    testWidgets('every pose parses with flutter_svg', (tester) async {
      for (final pose in MascotPose.values) {
        final info = await tester.runAsync(() => vg.loadPicture(SvgAssetLoader(pose.asset), null));
        expect(info, isNotNull, reason: pose.asset);
        expect(info!.size.width, greaterThan(0), reason: pose.asset);
        info.picture.dispose();
      }
    });

    test('only the listed poses are bundled', () {
      final files = Directory('assets/mascot')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      expect(files, MascotPose.values.map((p) => p.asset.split('/').last).toSet());
    });
  });

  group('Mascot', () {
    testWidgets('a full-body pose is drawn at the given height, 4:5', (tester) async {
      await _pump(tester, const Mascot(MascotPose.waveHappy, size: 120));
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.getSize(find.byType(Mascot)), const Size(96, 120));
    });

    testWidgets('the face is square', (tester) async {
      await _pump(tester, const Mascot.face(size: 28));
      expect(tester.getSize(find.byType(Mascot)), const Size(28, 28));
    });

    testWidgets('decorative by default: screen readers skip it', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const Mascot(MascotPose.ideaHappy));
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.excludeFromSemantics, isTrue);
      expect(find.bySemanticsLabel(RegExp('Ko Toe Pwar')), findsNothing);
      handle.dispose();
    });

    testWidgets('with a label it is announced once', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const Mascot.face(semanticLabel: 'Ko Toe Pwar'));
      expect(find.bySemanticsLabel('Ko Toe Pwar'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('renders on the dark surface without errors', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(body: Center(child: Mascot(MascotPose.oopsSad))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SvgPicture), findsOneWidget);
    });
  });

  group('error pose', () {
    for (final lang in ['en', 'my']) {
      final l = AppLocalizations(Locale(lang));
      test('$lang: network and timeout messages get offline_sad', () {
        expect(MascotPose.forError(l.errorNetworkUnreachable), MascotPose.offlineSad);
        expect(MascotPose.forError('${l.errorNetworkUnreachable} (Connection refused)'), MascotPose.offlineSad);
        expect(MascotPose.forError('Exception: ${l.errorRequestTimedOut}'), MascotPose.offlineSad);
      });
    }

    test('raw socket / browser fetch failures get offline_sad', () {
      expect(MascotPose.forError('SocketException: Failed host lookup: api'), MascotPose.offlineSad);
      expect(MascotPose.forError('ClientException: XMLHttpRequest error.'), MascotPose.offlineSad);
    });

    test('anything else gets oops_sad', () {
      expect(MascotPose.forError('Failed to get insights (500)'), MascotPose.oopsSad);
      expect(MascotPose.forError(''), MascotPose.oopsSad);
      expect(MascotPose.forError(null), MascotPose.oopsSad);
    });
  });
}
