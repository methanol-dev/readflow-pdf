import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/models/book.dart';
import 'package:readflow/models/reader_settings.dart';

void main() {
  test('Book model serialization and copyWith', () {
    final book = Book(
      id: 1,
      title: 'Đắc Nhân Tâm',
      filePath: '/path/to/dac-nhan-tam.pdf',
      pageCount: 120,
      lastReadPage: 15,
      lastReadTime: 1700000000,
    );

    expect(book.title, 'Đắc Nhân Tâm');
    expect(book.pageCount, 120);
    expect(book.lastReadPage, 15);

    final map = book.toMap();
    expect(map['title'], 'Đắc Nhân Tâm');
    expect(map['page_count'], 120);

    final fromMap = Book.fromMap(map);
    expect(fromMap.title, book.title);
    expect(fromMap.lastReadPage, 15);

    final updated = book.copyWith(lastReadPage: 16);
    expect(updated.lastReadPage, 16);
  });

  test('ReaderSettings color theme and font mappings', () {
    const settings = ReaderSettings(themePreset: ReaderThemePreset.sepia);
    expect(settings.backgroundColor.toARGB32(), 0xFFFBF0D9);
    expect(settings.textColor.toARGB32(), 0xFF5F4B32);

    final dark = settings.copyWith(themePreset: ReaderThemePreset.darkNight);
    expect(dark.backgroundColor.toARGB32(), 0xFF1E1E1E);
  });
}
