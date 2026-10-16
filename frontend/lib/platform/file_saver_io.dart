import 'dart:io';

import 'package:frontend/services/api_service.dart';
import 'package:path_provider/path_provider.dart';

/// Writes [pdf] to the app documents directory and returns its path.
Future<String?> saveReportPdf(ReportPdf pdf) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/${pdf.filename}');
  await file.writeAsBytes(pdf.bytes);
  return file.path;
}
