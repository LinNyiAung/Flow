import 'dart:js_interop';

import 'package:frontend/services/api_service.dart';
import 'package:web/web.dart' as web;

/// Starts a browser download of [pdf]. There is no file path on the web, so
/// this returns null.
Future<String?> saveReportPdf(ReportPdf pdf) async {
  final blob = web.Blob(
    [pdf.bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  try {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = pdf.filename;
    anchor.click();
  } finally {
    web.URL.revokeObjectURL(url);
  }
  return null;
}
