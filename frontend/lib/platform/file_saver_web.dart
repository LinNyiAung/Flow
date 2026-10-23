import 'dart:async';
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
  web.HTMLAnchorElement? anchor;
  try {
    anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = pdf.filename
      ..style.display = 'none';
    // Older Firefox/Safari only honour click() on an anchor in the document.
    web.document.body!.append(anchor);
    anchor.click();
  } catch (_) {
    // The download never started, so nothing will fetch the URL later.
    web.URL.revokeObjectURL(url);
    rethrow;
  } finally {
    anchor?.remove();
  }
  // Safari and some Firefox versions fetch the blob URL after this turn, so
  // revoking now could cancel the download. Release it a little later.
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  return null;
}
