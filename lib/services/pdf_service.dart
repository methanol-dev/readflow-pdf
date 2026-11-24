import 'dart:convert';
import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/pdf_page_content.dart';
import 'database_helper.dart';

class PdfService {
  static final PdfService instance = PdfService._init();
  PdfService._init();

  // In-memory cache for fast instant rendering
  final Map<String, Map<int, PdfPageContent>> _memoryCache = {};

  void clearMemoryCache() {
    _memoryCache.clear();
  }

  Future<int> getPageCount(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    final count = document.pages.count;
    document.dispose();
    return count;
  }

  Future<List<Map<String, dynamic>>> getOutline(String filePath) async {
    final outlineList = <Map<String, dynamic>>[];
    try {
      final bytes = await File(filePath).readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      for (int i = 0; i < document.bookmarks.count; i++) {
        final bm = document.bookmarks[i];
        int pageIndex = 0;
        if (bm.destination != null) {
          pageIndex = document.pages.indexOf(bm.destination!.page);
        }
        outlineList.add({
          'title': bm.title,
          'pageIndex': pageIndex.clamp(0, document.pages.count - 1),
        });
      }
      document.dispose();
    } catch (_) {}
    return outlineList;
  }

  Future<PdfPageContent> loadPageContent({
    required int bookId,
    required String filePath,
    required int pageIndex,
    required int totalPages,
  }) async {
    final cacheKey = '$bookId';
    _memoryCache[cacheKey] ??= {};

    // 1. Check RAM cache
    if (_memoryCache[cacheKey]!.containsKey(pageIndex)) {
      return _memoryCache[cacheKey]![pageIndex]!;
    }

    // 2. Check Database cache
    final dbPages = await DatabaseHelper.instance.getAllCachedPages(bookId);
    if (dbPages.containsKey(pageIndex)) {
      final raw = dbPages[pageIndex]!;
      try {
        final decoded = List<String>.from(jsonDecode(raw) as List);
        final content = PdfPageContent(pageIndex: pageIndex, paragraphs: decoded);
        _memoryCache[cacheKey]![pageIndex] = content;
        return content;
      } catch (_) {}
    }

    // 3. Extract text from PDF via Syncfusion
    final paragraphs = await _extractAndNormalize(filePath, pageIndex, totalPages);
    final content = PdfPageContent(pageIndex: pageIndex, paragraphs: paragraphs);

    _memoryCache[cacheKey]![pageIndex] = content;

    // Save to Database cache asynchronously
    DatabaseHelper.instance.cachePage(bookId, pageIndex, jsonEncode(paragraphs));

    return content;
  }

  Future<List<String>> _extractAndNormalize(String filePath, int pageIndex, int totalPages) async {
    if (pageIndex < 0 || pageIndex >= totalPages) return [];
    try {
      final bytes = await File(filePath).readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      final textExtractor = PdfTextExtractor(document);
      final rawText = textExtractor.extractText(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      );
      document.dispose();

      return _normalizeText(rawText);
    } catch (e) {
      return ['Không thể đọc nội dung trang này.'];
    }
  }

  List<String> _normalizeText(String rawText) {
    if (rawText.trim().isEmpty) return [];

    // Replace Windows newlines
    String text = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Remove hyphenation at line breaks: e.g. "xinh đẹ-\np" -> "xinh đẹ-p" or "đan-\ng" -> "đang"
    text = text.replaceAllMapped(RegExp(r'(\w+)-\n(\w+)'), (m) => '${m[1]}${m[2]}');

    // Split paragraphs by double line breaks or single lines that look like paragraphs
    final lines = text.split('\n');
    final paragraphs = <String>[];
    StringBuffer currentPara = StringBuffer();

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (currentPara.isNotEmpty) {
          paragraphs.add(currentPara.toString().trim());
          currentPara.clear();
        }
      } else {
        if (currentPara.isNotEmpty) {
          // If previous ended with punctuation or line starts with indent/bullet/dialogue
          if (trimmed.startsWith('-') ||
              trimmed.startsWith('—') ||
              trimmed.startsWith('•') ||
              trimmed.startsWith('"') ||
              trimmed.startsWith('“')) {
            paragraphs.add(currentPara.toString().trim());
            currentPara.clear();
          } else {
            currentPara.write(' ');
          }
        }
        currentPara.write(trimmed);
      }
    }

    if (currentPara.isNotEmpty) {
      paragraphs.add(currentPara.toString().trim());
    }

    return paragraphs.where((p) => p.trim().isNotEmpty).toList();
  }
}
