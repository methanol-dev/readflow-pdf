import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/outline_item.dart';
import '../models/pdf_page_content.dart';
import 'database_helper.dart';
import 'pdf_page_extractor.dart';

class PdfService {
  static final PdfService instance = PdfService._init();
  PdfService._init();

  // Extracted pages per book id, for instant re-rendering.
  final Map<int, Map<int, PdfPageContent>> _memoryCache = {};

  // Page loads in flight, so the reader and TTS asking for the same page
  // share one extraction.
  final Map<(int, int), Future<PdfPageContent>> _pendingLoads = {};

  // The most recently opened document. Parsing a PDF is the expensive part,
  // so it is kept open and reused across page count, outline and text calls.
  String? _openPath;
  Future<PdfDocument>? _openDocument;

  void clearMemoryCache() {
    _memoryCache.clear();
  }

  Future<PdfDocument> _document(String filePath) {
    final cached = _openDocument;
    if (cached != null && _openPath == filePath) return cached;

    releaseDocument();
    final opening = File(filePath)
        .readAsBytes()
        .then((bytes) => PdfDocument(inputBytes: bytes));
    _openPath = filePath;
    _openDocument = opening;
    // Do not keep a failed open around, so the next call retries.
    opening.then<void>((_) {}, onError: (Object _) {
      if (identical(_openDocument, opening)) {
        _openPath = null;
        _openDocument = null;
      }
    });
    return opening;
  }

  /// Closes the document kept open by previous calls and frees its memory.
  void releaseDocument() {
    final open = _openDocument;
    _openPath = null;
    _openDocument = null;
    open?.then<void>((document) => document.dispose(), onError: (Object _) {});
  }

  Future<int> getPageCount(String filePath) async {
    final document = await _document(filePath);
    return document.pages.count;
  }

  Future<List<OutlineItem>> getOutline(String filePath) async {
    final outline = <OutlineItem>[];
    try {
      final document = await _document(filePath);
      final lastPage = document.pages.count - 1;
      for (int i = 0; i < document.bookmarks.count; i++) {
        final bookmark = document.bookmarks[i];
        final destination = bookmark.destination;
        final pageIndex =
            destination == null ? 0 : document.pages.indexOf(destination.page);
        outline.add(OutlineItem(
          title: bookmark.title,
          pageIndex: pageIndex.clamp(0, lastPage),
        ));
      }
    } catch (_) {}
    return outline;
  }

  Future<PdfPageContent> loadPageContent({
    required int bookId,
    required String filePath,
    required int pageIndex,
    required int totalPages,
  }) {
    // 1. RAM cache
    final cached = _memoryCache[bookId]?[pageIndex];
    if (cached != null) return Future.value(cached);

    final key = (bookId, pageIndex);
    return _pendingLoads[key] ??= _loadUncached(
      bookId: bookId,
      filePath: filePath,
      pageIndex: pageIndex,
      totalPages: totalPages,
    ).whenComplete(() => _pendingLoads.remove(key));
  }

  Future<PdfPageContent> _loadUncached({
    required int bookId,
    required String filePath,
    required int pageIndex,
    required int totalPages,
  }) async {
    // 2. Database cache
    var paragraphs = await _readCachedParagraphs(bookId, pageIndex);

    // 3. Extract text from the PDF
    if (paragraphs == null) {
      paragraphs = await _extractParagraphs(filePath, pageIndex, totalPages);
      if (paragraphs != null) {
        unawaited(
          DatabaseHelper.instance
              .cachePage(bookId, pageIndex, jsonEncode(paragraphs))
              .catchError((Object _) {}),
        );
      }
    }

    final content = PdfPageContent(
      pageIndex: pageIndex,
      paragraphs: paragraphs ?? const ['Không thể đọc nội dung trang này.'],
    );
    (_memoryCache[bookId] ??= {})[pageIndex] = content;
    return content;
  }

  Future<List<String>?> _readCachedParagraphs(int bookId, int pageIndex) async {
    final raw = await DatabaseHelper.instance.getCachedPage(bookId, pageIndex);
    if (raw == null) return null;
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return null;
    }
  }

  /// Returns null when the page could not be read.
  Future<List<String>?> _extractParagraphs(
    String filePath,
    int pageIndex,
    int totalPages,
  ) async {
    if (pageIndex < 0 || pageIndex >= totalPages) return const [];
    try {
      final document = await _document(filePath);
      return extractPageParagraphs(document, pageIndex);
    } catch (_) {
      return null;
    }
  }
}
