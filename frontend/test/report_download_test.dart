import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/api_service.dart';

void main() {
  group('reportFilenameFromContentDisposition', () {
    test('reads a quoted filename', () {
      expect(
        reportFilenameFromContentDisposition(
          'attachment; filename="report_2026-10.pdf"',
        ),
        'report_2026-10.pdf',
      );
    });

    test('reads an unquoted filename', () {
      expect(
        reportFilenameFromContentDisposition('attachment; filename=plain.pdf'),
        'plain.pdf',
      );
    });

    test('defaults when the header is missing', () {
      expect(
        reportFilenameFromContentDisposition(null),
        'financial_report.pdf',
      );
    });

    test('defaults when the header has no filename', () {
      expect(
        reportFilenameFromContentDisposition('inline'),
        'financial_report.pdf',
      );
    });
  });
}
