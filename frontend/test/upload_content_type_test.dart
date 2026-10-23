import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/api_service.dart';

void main() {
  group('uploadContentType', () {
    const expected = <String, String>{
      'recording.wav': 'audio/wav',
      'recording.webm': 'audio/webm',
      'voice.m4a': 'audio/mp4',
      'receipt.png': 'image/png',
      'receipt.jpg': 'image/jpeg',
      'receipt.jpeg': 'image/jpeg',
      'receipt.webp': 'image/webp',
      'receipt.heic': 'image/heic',
      'notes.txt': 'application/octet-stream',
      'noextension': 'application/octet-stream',
    };

    expected.forEach((filename, mime) {
      test('$filename -> $mime', () {
        expect(uploadContentType(filename).mimeType, mime);
      });
    });

    test('is case-insensitive', () {
      expect(uploadContentType('RECEIPT.PNG').mimeType, 'image/png');
    });
  });
}
