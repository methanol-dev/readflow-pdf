import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/models/book.dart';
import 'package:readflow/models/reader_settings.dart';
import 'package:readflow/services/pdf_page_extractor.dart';
import 'package:readflow/services/pdf_safe_text_extractor.dart';
import 'package:readflow/services/pdf_service.dart';
import 'package:readflow/services/settings_service.dart';
import 'package:readflow/ui/reader/reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Builds a minimal valid PDF byte buffer from a map of `objectNumber -> body`.
Uint8List _buildPdfFromObjects(
  Map<int, List<int>> objects, {
  required int catalogObj,
}) {
  final maxObj = objects.keys.reduce((a, b) => a > b ? a : b);
  final out = BytesBuilder();
  void writeAscii(String s) => out.add(latin1.encode(s));

  writeAscii('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');

  final offsets = <int, int>{};
  for (var objNum = 1; objNum <= maxObj; objNum++) {
    final body = objects[objNum];
    if (body == null) continue;
    offsets[objNum] = out.length;
    writeAscii('$objNum 0 obj\n');
    out.add(body);
    writeAscii('\nendobj\n');
  }

  final xrefOffset = out.length;
  writeAscii('xref\n0 ${maxObj + 1}\n');
  writeAscii('0000000000 65535 f \n');
  for (var objNum = 1; objNum <= maxObj; objNum++) {
    final off = offsets[objNum];
    if (off == null) {
      writeAscii('0000000000 65535 f \n');
    } else {
      writeAscii('${off.toString().padLeft(10, '0')} 00000 n \n');
    }
  }
  writeAscii(
    'trailer\n<< /Size ${maxObj + 1} /Root $catalogObj 0 R >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );
  return out.toBytes();
}

List<int> _pdfStream(List<int> rawData, {bool compress = false, String extraDict = ''}) {
  final payload = compress ? zlib.encode(rawData) : rawData;
  final filter = compress ? '/Filter /FlateDecode ' : '';
  final header = '<< /Length ${payload.length} $filter$extraDict>>\nstream\n';
  return [
    ...latin1.encode(header),
    ...payload,
    ...latin1.encode('\nendstream'),
  ];
}

/// Builds a simple single-page or multi-page ASCII Helvetica PDF.
Uint8List _buildSimpleTextPdf(List<String> pageContents) {
  // Objects:
  // 1: Catalog, 2: Pages, 3: Font (/Helvetica), 4..: alternating Page & Contents
  final objects = <int, List<int>>{};
  objects[3] = latin1.encode(
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  );

  final kidsRefs = <String>[];
  var nextId = 4;
  for (final contentStream in pageContents) {
    final pageId = nextId++;
    final streamId = nextId++;
    kidsRefs.add('$pageId 0 R');
    objects[pageId] = latin1.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources << /Font << /F1 3 0 R >> >> /Contents $streamId 0 R >>',
    );
    objects[streamId] = _pdfStream(latin1.encode(contentStream), compress: true);
  }

  objects[2] = latin1.encode(
    '<< /Type /Pages /Kids [${kidsRefs.join(' ')}] /Count ${pageContents.length} >>',
  );
  objects[1] = latin1.encode('<< /Type /Catalog /Pages 2 0 R >>');

  return _buildPdfFromObjects(objects, catalogObj: 1);
}

/// Builds a PDF 1.5+ document with a compressed ObjStm and XRef stream.
Uint8List _buildPdf15XRefStreamPdf(String textLine) {
  final obj1 = latin1.encode('<< /Type /Catalog /Pages 2 0 R >>');
  final obj2 = latin1.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  final obj3 = latin1.encode(
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
    '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
  );
  final obj4 = latin1.encode(
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  );

  // Pack objects 1, 2, 4 into ObjStm (object 6) to exercise ObjStm parsing.
  final objStmBody = BytesBuilder();
  final headerParts = <String>[];
  void addCompressed(int num, List<int> bytes) {
    headerParts.add('$num ${objStmBody.length}');
    objStmBody.add(bytes);
    objStmBody.addByte(0x0A);
  }

  addCompressed(1, obj1);
  addCompressed(2, obj2);
  addCompressed(4, obj4);
  final headerBytes = latin1.encode('${headerParts.join(' ')} ');
  final objStmRaw = [...headerBytes, ...objStmBody.toBytes()];
  final obj6 = _pdfStream(
    objStmRaw,
    compress: true,
    extraDict: '/Type /ObjStm /N 3 /First ${headerBytes.length} ',
  );

  final obj5 = _pdfStream(
    latin1.encode('BT /F1 12 Tf 72 720 Td ($textLine) Tj ET'),
    compress: true,
  );

  final out = BytesBuilder();
  void writeAscii(String s) => out.add(latin1.encode(s));
  writeAscii('%PDF-1.5\n%\xE2\xE3\xCF\xD3\n');

  final off3 = out.length;
  writeAscii('3 0 obj\n');
  out.add(obj3);
  writeAscii('\nendobj\n');

  final off5 = out.length;
  writeAscii('5 0 obj\n');
  out.add(obj5);
  writeAscii('\nendobj\n');

  final off6 = out.length;
  writeAscii('6 0 obj\n');
  out.add(obj6);
  writeAscii('\nendobj\n');

  final xrefStreamOffset = out.length;
  // Entries 0..7 with W [1 2 1]
  final xrefBytes = BytesBuilder();
  void addEntry(int type, int f2, int f3) {
    xrefBytes.addByte(type);
    xrefBytes.addByte((f2 >> 8) & 0xFF);
    xrefBytes.addByte(f2 & 0xFF);
    xrefBytes.addByte(f3 & 0xFF);
  }

  addEntry(0, 0, 255); // 0: free
  addEntry(2, 6, 0); // 1: in ObjStm 6 index 0
  addEntry(2, 6, 1); // 2: in ObjStm 6 index 1
  addEntry(1, off3, 0); // 3: regular object
  addEntry(2, 6, 2); // 4: in ObjStm 6 index 2
  addEntry(1, off5, 0); // 5: regular object
  addEntry(1, off6, 0); // 6: ObjStm
  addEntry(1, xrefStreamOffset, 0); // 7: XRef stream itself

  final xrefRaw = xrefBytes.toBytes();
  final obj7 = _pdfStream(
    xrefRaw,
    compress: false,
    extraDict: '/Type /XRef /Size 8 /W [1 2 1] /Root 1 0 R ',
  );
  writeAscii('7 0 obj\n');
  out.add(obj7);
  writeAscii('\nendobj\nstartxref\n$xrefStreamOffset\n%%EOF\n');
  return out.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
  });

  group('pdf_safe_text_extractor', () {
    test('extracts compressed multi-page text and page count', () {
      final pdfBytes = _buildSimpleTextPdf([
        'BT /F1 12 Tf 72 720 Td (Hello Page One.) Tj ET',
        'BT /F1 12 Tf 72 720 Td (Second Page Content.) Tj ET',
      ]);

      expect(getPageCountSafe(pdfBytes), 2);
      expect(
        extractPageParagraphsSafe(pdfBytes, 0),
        equals(['Hello Page One.']),
      );
      expect(
        extractPageParagraphsSafe(pdfBytes, 1),
        equals(['Second Page Content.']),
      );
    });

    test('resolves inherited /Pages resources and Vietnamese Type0 /ToUnicode CMap', () {
      // CID 0001 -> "T", 0002 -> "i", 0003 -> "ế" (U+1EBF), 0004 -> "n", 0005 -> "g",
      // 0006 -> " ", 0007 -> "V", 0008 -> "ệ" (U+1EC7), 0009 -> "t"
      const toUnicode = '''
/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
5 beginbfchar
<0001> <0054>
<0002> <0069>
<0003> <1EBF>
<0004> <006E>
<0005> <0067>
endbfchar
2 beginbfrange
<0006> <0007> <0020>
<0008> <0009> [<0056> <1EC7>]
endbfrange
1 beginbfchar
<000A> <0074>
endbfchar
endcmap
''';
      final objects = <int, List<int>>{
        1: latin1.encode('<< /Type /Catalog /Pages 2 0 R >>'),
        // /Resources placed on parent /Pages node (inherited by child Page 3)
        2: latin1.encode(
          '<< /Type /Pages /Kids [3 0 R] /Count 1 '
          '/Resources << /Font << /F1 4 0 R >> >> >>',
        ),
        3: latin1.encode('<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>'),
        4: latin1.encode(
          '<< /Type /Font /Subtype /Type0 /Encoding /Identity-H /ToUnicode 5 0 R >>',
        ),
        5: _pdfStream(latin1.encode(toUnicode)),
        // Spell "Tiếng Việt" -> <0001 0002 0003 0004 0005 0006 0008 0002 0009 000A>
        6: _pdfStream(
          latin1.encode(
            'BT /F1 12 Tf 72 720 Td <000100020003000400050006000800020009000A> Tj ET',
          ),
        ),
      };
      final pdfBytes = _buildPdfFromObjects(objects, catalogObj: 1);

      expect(
        extractPageParagraphsSafe(pdfBytes, 0),
        equals(['Tiếng Việt']),
      );
    });

    test('handles inline images (BI..ID..EI) and cyclic Form XObject without hanging', () {
      // Inline image followed by BT (which causes Syncfusion infinite loop)
      final inlineBytes = _buildSimpleTextPdf([
        'q BI /W 1 /H 1 /CS /G /BPC 8 ID \x00 EI BT /F1 12 Tf 72 720 Td (After Inline Image) Tj ET Q',
      ]);
      expect(
        extractPageParagraphsSafe(inlineBytes, 0),
        equals(['After Inline Image']),
      );

      // Cyclic Form XObject /Resources -> Syncfusion infinite loop
      final cyclicObjects = <int, List<int>>{
        1: latin1.encode('<< /Type /Catalog /Pages 2 0 R >>'),
        2: latin1.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
        3: latin1.encode(
          '<< /Type /Page /Parent 2 0 R '
          '/Resources << /Font << /F1 4 0 R >> /XObject << /Fm0 5 0 R >> >> '
          '/Contents 6 0 R >>',
        ),
        4: latin1.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'),
        // Self-referencing XObject cycle
        5: _pdfStream(
          latin1.encode('BT /F1 12 Tf 72 700 Td (Inside Form) Tj ET /Fm0 Do'),
          extraDict:
              '/Type /XObject /Subtype /Form /BBox [0 0 100 100] '
              '/Resources << /Font << /F1 4 0 R >> /XObject << /Fm0 5 0 R >> >> ',
        ),
        6: _pdfStream(
          latin1.encode('/Fm0 Do BT /F1 12 Tf 72 680 Td (After Form) Tj ET'),
        ),
      };
      final cyclicBytes = _buildPdfFromObjects(cyclicObjects, catalogObj: 1);

      expect(
        extractPageParagraphsSafe(cyclicBytes, 0),
        equals(['Inside Form After Form']),
      );
    });

    test('recovers text when font size is 0 Tf (ZeroFontSyncfusion crash)', () {
      final zeroFontPdf = _buildSimpleTextPdf([
        'BT /F1 0 Tf 72 720 Td (Hidden Size Zero) Tj /F1 12 Tf 72 700 Td (Visible Size Twelve) Tj ET',
      ]);

      // Safe extractor handles it cleanly.
      expect(
        extractPageParagraphsSafe(zeroFontPdf, 0),
        equals(['Hidden Size Zero', 'Visible Size Twelve']),
      );

      // Primary Syncfusion extractor should also recover cleanly via try/catch fallback.
      final doc = PdfDocument(inputBytes: zeroFontPdf);
      addTearDown(doc.dispose);
      final paragraphs = extractPageParagraphs(doc, 0);
      expect(paragraphs.join(' '), contains('Visible Size Twelve'));
    });

    test('parses PDF 1.5+ XRef stream and compressed ObjStm', () {
      final pdf15 = _buildPdf15XRefStreamPdf('Compressed Object Stream Works');
      expect(getPageCountSafe(pdf15), 1);
      expect(
        extractPageParagraphsSafe(pdf15, 0),
        equals(['Compressed Object Stream Works']),
      );
    });
  });

  group('PdfService worker isolate', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('readflow_pdf_test_');
      PdfService.instance.clearMemoryCache();
    });

    tearDown(() async {
      await PdfService.instance.releaseDocument();
      PdfService.instance.clearMemoryCache();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('extracts text and outlines in worker isolate, and retries cleanly after missing file error', () async {
      final missingPath = '${tempDir.path}${Platform.pathSeparator}sample.pdf';

      // 1. Missing file produces isError: true and is NOT cached in memory.
      final errContent = await PdfService.instance.loadPageContent(
        bookId: 9001,
        filePath: missingPath,
        pageIndex: 0,
        totalPages: 1,
      );
      expect(errContent.isError, isTrue);

      // 2. Write valid PDF to the same path and reload -> now succeeds.
      final pdfBytes = _buildSimpleTextPdf([
        'BT /F1 12 Tf 72 720 Td (First Real Page) Tj ET',
      ]);
      await File(missingPath).writeAsBytes(pdfBytes, flush: true);

      expect(await PdfService.instance.getPageCount(missingPath), 1);
      final okContent = await PdfService.instance.loadPageContent(
        bookId: 9001,
        filePath: missingPath,
        pageIndex: 0,
        totalPages: 1,
      );
      expect(okContent.isError, isFalse);
      expect(okContent.paragraphs, equals(['First Real Page']));
    });

    test('recovers automatically when Syncfusion hangs on inline images', () async {
      final path = '${tempDir.path}${Platform.pathSeparator}inline_hang.pdf';
      final bytes = _buildSimpleTextPdf([
        'q BI /W 1 /H 1 /CS /G /BPC 8 ID \x00 EI BT /F1 12 Tf 72 720 Td (Page 1 Safe) Tj ET Q',
        'q BI /W 1 /H 1 /CS /G /BPC 8 ID \x00 EI BT /F1 12 Tf 72 720 Td (Page 2 Safe) Tj ET Q',
      ]);
      await File(path).writeAsBytes(bytes, flush: true);

      // First page triggers Syncfusion timeout -> kills worker -> safe fallback rescues it.
      final p1 = await PdfService.instance.loadPageContent(
        bookId: 9002,
        filePath: path,
        pageIndex: 0,
        totalPages: 2,
      );
      expect(p1.isError, isFalse);
      expect(p1.paragraphs, equals(['Page 1 Safe']));

      // Second page skips Syncfusion immediately via _preferSafeExtractor memoization.
      final sw = Stopwatch()..start();
      final p2 = await PdfService.instance.loadPageContent(
        bookId: 9002,
        filePath: path,
        pageIndex: 1,
        totalPages: 2,
      );
      sw.stop();
      expect(p2.isError, isFalse);
      expect(p2.paragraphs, equals(['Page 2 Safe']));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('ReaderScreen UI resilience', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('readflow_reader_ui_');
      PdfService.instance.clearMemoryCache();
    });

    tearDown(() async {
      SettingsService.instance.settings.value = const ReaderSettings();
      await PdfService.instance.releaseDocument();
      PdfService.instance.clearMemoryCache();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('shows retry UI on error and loads content when retrying', (tester) async {
      SettingsService.instance.settings.value = const ReaderSettings(
        viewMode: ViewMode.reflow,
        isContinuousScroll: false,
      );
      final pdfPath = '${tempDir.path}${Platform.pathSeparator}book.pdf';
      final book = Book(
        id: 9101,
        title: 'Test Book',
        filePath: pdfPath,
        pageCount: 1,
        lastReadPage: 0,
        lastReadTime: 0,
        fileSizeBytes: 100,
      );

      await tester.pumpWidget(MaterialApp(home: ReaderScreen(book: book)));
      // Let real worker isolate attempt file read and report error.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      expect(find.text('Không thể đọc nội dung trang 1.'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Provide a readable PDF and tap Retry.
      await tester.runAsync(() async {
        await File(pdfPath).writeAsBytes(
          _buildSimpleTextPdf(['BT /F1 12 Tf 72 720 Td (Loaded After Retry) Tj ET']),
          flush: true,
        );
      });

      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('Loaded After Retry'), findsOneWidget);
      expect(find.text('Không thể đọc nội dung trang 1.'), findsNothing);

      // Unmount widget and let dispose()->releaseDocument() settle before test invariants run.
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => PdfService.instance.releaseDocument());
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('continuous scroll starts at lastReadPage and loads surrounding text', (tester) async {
      SettingsService.instance.settings.value = const ReaderSettings(
        viewMode: ViewMode.reflow,
        isContinuousScroll: true,
      );
      final pdfPath = '${tempDir.path}${Platform.pathSeparator}multi.pdf';
      await tester.runAsync(() async {
        await File(pdfPath).writeAsBytes(
          _buildSimpleTextPdf([
            'BT /F1 12 Tf 72 720 Td (Chapter One Text) Tj ET',
            'BT /F1 12 Tf 72 720 Td (Chapter Two Resume Text) Tj ET',
            'BT /F1 12 Tf 72 720 Td (Chapter Three Text) Tj ET',
          ]),
          flush: true,
        );
      });

      final book = Book(
        id: 9102,
        title: 'Multi Page Book',
        filePath: pdfPath,
        pageCount: 3,
        lastReadPage: 1,
        lastReadTime: 0,
        fileSizeBytes: 200,
      );

      await tester.pumpWidget(MaterialApp(home: ReaderScreen(book: book)));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();

      // Opens anchored at page 2/3 rather than wrongly showing Trang 1/3 at the top.
      expect(find.text('─── Trang 2 / 3 ───'), findsOneWidget);
      expect(find.text('Chapter Two Resume Text'), findsOneWidget);
      expect(find.text('Trang 2 / 3'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => PdfService.instance.releaseDocument());
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
