import 'package:easy_tab/services/mime_utils.dart';
import 'package:easy_tab/utils/filename_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mimeTypeFromFilename', () {
    test('returns correct MIME type for known image extensions', () {
      expect(mimeTypeFromFilename('photo.jpg'), 'image/jpeg');
      expect(mimeTypeFromFilename('photo.jpeg'), 'image/jpeg');
      expect(mimeTypeFromFilename('image.png'), 'image/png');
      expect(mimeTypeFromFilename('pic.webp'), 'image/webp');
    });

    test('returns correct MIME type for video extensions', () {
      expect(mimeTypeFromFilename('clip.mp4'), 'video/mp4');
      expect(mimeTypeFromFilename('clip.mov'), 'video/quicktime');
    });

    test('returns default MIME type for unknown or missing extension', () {
      expect(mimeTypeFromFilename('unknown'), 'application/octet-stream');
      expect(
        mimeTypeFromFilename('file.unknownext'),
        'application/octet-stream',
      );
      expect(mimeTypeFromFilename(''), 'application/octet-stream');
    });
  });

  group('filename_utils', () {
    test('sanitizeFileName removes dangerous characters', () {
      expect(sanitizeFileName('report ../secret.txt'), 'report_secrettxt');
      expect(sanitizeFileName('my report 2026!'), 'my_report_2026');
    });

    test('buildShareZipName combines report name and token suffix', () {
      expect(
        buildShareZipName('Annual Report', 'abc123def'),
        'Annual_Report_abc123de.zip',
      );
      expect(buildShareZipName('', 'abc123def'), 'report_abc123de.zip');
    });
  });
}
