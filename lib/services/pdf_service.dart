import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/outline_item.dart';
import '../models/pdf_page_content.dart';
import 'database_helper.dart';
import 'pdf_page_extractor.dart';
import 'pdf_safe_text_extractor.dart';

class PdfService {
  static final PdfService instance = PdfService._init();
  PdfService._init();

  static const Duration _pageExtractTimeout = Duration(seconds: 4);
  static const Duration _documentTimeout = Duration(seconds: 20);

  // Extracted pages per book id, for instant re-rendering.
  final Map<int, Map<int, PdfPageContent>> _memoryCache = {};

  // Page loads in flight, so the reader and TTS asking for the same page
  // share one extraction.
  final Map<(int, int), Future<PdfPageContent>> _pendingLoads = {};

  // Files where Syncfusion's extractor hung or timed out; subsequent pages skip
  // Syncfusion directly and use the bounded pure-Dart extractor.
  final Set<String> _preferSafeExtractor = {};

  // Serializes worker requests so one slow page doesn't freeze the UI and
  // timeouts can cleanly kill and respawn the worker isolate.
  _PdfIsolateWorker? _worker;
  Future<void> _workerLock = Future.value();

  void clearMemoryCache() {
    _memoryCache.clear();
  }

  /// Releases the document held open in the background worker to free memory.
  Future<void> releaseDocument() {
    final worker = _worker;
    if (worker != null && !worker.isDisposed) {
      return _runInWorker(
        (w) => w.release(),
        timeout: const Duration(seconds: 5),
      ).catchError((Object _) {});
    }
    return Future.value();
  }

  Future<T> _runInWorker<T>(
    Future<T> Function(_PdfIsolateWorker worker) action, {
    required Duration timeout,
  }) {
    final completer = Completer<T>();
    _workerLock = _workerLock.then((_) async {
      try {
        final worker = _worker ??= await _PdfIsolateWorker.spawn(timeout: timeout);
        final result = await action(worker).timeout(timeout);
        if (!completer.isCompleted) completer.complete(result);
      } catch (error, stackTrace) {
        if (error is TimeoutException || error is _WorkerCrashedException) {
          _worker?.kill();
          _worker = null;
        }
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  Future<int> getPageCount(String filePath) {
    return _runInWorker(
      (worker) => worker.getPageCount(filePath),
      timeout: _documentTimeout,
    );
  }

  Future<List<OutlineItem>> getOutline(String filePath) async {
    try {
      return await _runInWorker(
        (worker) => worker.getOutline(filePath),
        timeout: _documentTimeout,
      );
    } catch (_) {
      return const [];
    }
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
    ).whenComplete(() {
      // Block body avoids returning the removed Future (self-await deadlock).
      _pendingLoads.remove(key);
    });
  }

  Future<PdfPageContent> _loadUncached({
    required int bookId,
    required String filePath,
    required int pageIndex,
    required int totalPages,
  }) async {
    // 2. Database cache
    var paragraphs = await _readCachedParagraphs(bookId, pageIndex);

    // 3. Extract text from the PDF in the background worker
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

    if (paragraphs == null) {
      return PdfPageContent(
        pageIndex: pageIndex,
        paragraphs: const ['Không thể đọc nội dung trang này.'],
        isError: true,
      );
    }

    final content = PdfPageContent(
      pageIndex: pageIndex,
      paragraphs: paragraphs,
    );
    (_memoryCache[bookId] ??= {})[pageIndex] = content;
    return content;
  }

  Future<List<String>?> _readCachedParagraphs(int bookId, int pageIndex) async {
    try {
      final raw = await DatabaseHelper.instance.getCachedPage(bookId, pageIndex);
      if (raw == null) return null;
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
    final useSafeOnly = _preferSafeExtractor.contains(filePath);
    try {
      return await _runInWorker(
        (worker) => worker.extractPage(
          filePath,
          pageIndex,
          preferSafeOnly: useSafeOnly,
        ),
        timeout: _pageExtractTimeout,
      );
    } on TimeoutException {
      // Syncfusion hung (e.g. inline image / cyclic Form XObject). Remember this
      // file so subsequent pages skip straight to the bounded fallback.
      _preferSafeExtractor.add(filePath);
      try {
        return await _runInWorker(
          (worker) => worker.extractPage(
            filePath,
            pageIndex,
            preferSafeOnly: true,
          ),
          timeout: _pageExtractTimeout,
        );
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Persistent background worker isolate
// ---------------------------------------------------------------------------

class _WorkerTaskException implements Exception {
  final String message;
  _WorkerTaskException(this.message);
  @override
  String toString() => message;
}

class _WorkerCrashedException implements Exception {
  final String message;
  _WorkerCrashedException(this.message);
  @override
  String toString() => message;
}

class _PdfIsolateWorker {
  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _exitPort;
  final Set<ReceivePort> _openReplies = {};
  bool _disposed = false;

  bool get isDisposed => _disposed;

  _PdfIsolateWorker._(
    this._isolate,
    this._sendPort,
    this._exitPort, {
    bool initiallyDisposed = false,
  }) : _disposed = initiallyDisposed;

  void _markDisposed() {
    _disposed = true;
    for (final reply in _openReplies.toList()) {
      reply.close();
    }
    _openReplies.clear();
  }

  static Future<_PdfIsolateWorker> spawn({required Duration timeout}) async {
    final initPort = ReceivePort();
    final exitPort = ReceivePort();
    final errorPort = ReceivePort();
    final sendPortCompleter = Completer<SendPort>();
    var exited = false;
    _PdfIsolateWorker? worker;

    void failStart(Object error) {
      if (!sendPortCompleter.isCompleted) {
        sendPortCompleter.completeError(_WorkerCrashedException(error.toString()));
      }
    }

    initPort.listen((msg) {
      if (msg is SendPort && !sendPortCompleter.isCompleted) {
        sendPortCompleter.complete(msg);
      }
    });
    errorPort.listen((err) => failStart('PDF worker isolate error: $err'));
    exitPort.listen((_) {
      exited = true;
      failStart('PDF worker exited before initialization');
      worker?._markDisposed();
    });

    final isolate = await Isolate.spawn(
      _workerEntry,
      initPort.sendPort,
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
    );

    try {
      final sendPort = await sendPortCompleter.future.timeout(timeout);
      initPort.close();
      errorPort.close();
      worker = _PdfIsolateWorker._(
        isolate,
        sendPort,
        exitPort,
        initiallyDisposed: exited,
      );
      return worker;
    } catch (e) {
      initPort.close();
      errorPort.close();
      exitPort.close();
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  Future<Object?> _call(Map<String, Object?> payload) async {
    if (_disposed) {
      throw _WorkerCrashedException('PDF worker already terminated');
    }
    final reply = ReceivePort();
    _openReplies.add(reply);
    payload['reply'] = reply.sendPort;
    _sendPort.send(payload);
    try {
      final response = await reply.first;
      if (response is Map && response.containsKey('error')) {
        throw _WorkerTaskException(response['error'].toString());
      }
      return (response as Map)['result'];
    } on StateError catch (e) {
      throw _WorkerCrashedException(e.message);
    } finally {
      _openReplies.remove(reply);
      reply.close();
    }
  }

  Future<int> getPageCount(String filePath) async {
    final res = await _call({'op': 'pageCount', 'path': filePath});
    return res as int;
  }

  Future<List<OutlineItem>> getOutline(String filePath) async {
    final res = await _call({'op': 'outline', 'path': filePath}) as List;
    return [
      for (final item in res)
        OutlineItem(
          title: (item as List)[0] as String,
          pageIndex: item[1] as int,
        ),
    ];
  }

  Future<List<String>> extractPage(
    String filePath,
    int pageIndex, {
    required bool preferSafeOnly,
  }) async {
    final res = await _call({
      'op': 'extract',
      'path': filePath,
      'page': pageIndex,
      'safeOnly': preferSafeOnly,
    });
    return (res as List).cast<String>();
  }

  Future<void> release() async {
    if (_disposed) return;
    await _call({'op': 'release'});
  }

  void kill() {
    if (_disposed) return;
    _disposed = true;
    for (final reply in _openReplies.toList()) {
      reply.close();
    }
    _openReplies.clear();
    _isolate.kill(priority: Isolate.immediate);
    _exitPort.close();
  }
}

void _workerEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  String? openPath;
  Uint8List? openBytes;
  PdfDocument? openDoc;

  void closeOpenDoc() {
    try {
      openDoc?.dispose();
    } catch (_) {}
    openDoc = null;
    openBytes = null;
    openPath = null;
  }

  Future<Uint8List> loadBytes(String path) async {
    if (openPath == path && openBytes != null) return openBytes!;
    closeOpenDoc();
    final bytes = await File(path).readAsBytes();
    openPath = path;
    openBytes = bytes;
    return bytes;
  }

  Future<PdfDocument?> loadSyncfusionDoc(String path) async {
    final bytes = await loadBytes(path);
    if (openDoc != null) return openDoc;
    try {
      openDoc = PdfDocument(inputBytes: bytes);
      return openDoc;
    } catch (_) {
      return null;
    }
  }

  receivePort.listen((message) async {
    if (message is! Map) return;
    final op = message['op'] as String?;
    final reply = message['reply'] as SendPort;

    try {
      switch (op) {
        case 'release':
          closeOpenDoc();
          reply.send({'result': null});
        case 'pageCount':
          final path = message['path'] as String;
          final bytes = await loadBytes(path);
          final doc = await loadSyncfusionDoc(path);
          final count = doc != null
              ? doc.pages.count
              : (getPageCountSafe(bytes) ?? 0);
          reply.send({'result': count});
        case 'outline':
          final path = message['path'] as String;
          final doc = await loadSyncfusionDoc(path);
          final outline = <List<Object>>[];
          if (doc != null && doc.pages.count > 0) {
            final lastPage = doc.pages.count - 1;
            for (var i = 0; i < doc.bookmarks.count; i++) {
              final bookmark = doc.bookmarks[i];
              final destination = bookmark.destination;
              final pageIndex = destination == null
                  ? 0
                  : doc.pages.indexOf(destination.page);
              outline.add([bookmark.title, pageIndex.clamp(0, lastPage)]);
            }
          }
          reply.send({'result': outline});
        case 'extract':
          final path = message['path'] as String;
          final pageIndex = message['page'] as int;
          final safeOnly = message['safeOnly'] as bool? ?? false;
          final bytes = await loadBytes(path);

          List<String>? paragraphs;
          PdfDocument? doc;
          if (!safeOnly) {
            doc = await loadSyncfusionDoc(path);
            if (doc != null) {
              try {
                paragraphs = extractPageParagraphs(doc, pageIndex);
              } catch (_) {
                paragraphs = null;
              }
            }
          }

          if (paragraphs == null || paragraphs.isEmpty) {
            final safeCount = getPageCountSafe(bytes);
            if (doc == null && safeOnly && safeCount == null) {
              throw StateError('Unable to parse PDF document');
            }
            final fallback = extractPageParagraphsSafe(bytes, pageIndex);
            if (fallback.isNotEmpty) {
              paragraphs = fallback;
            } else if (paragraphs == null && safeCount == null && doc == null) {
              throw StateError('Unable to extract PDF page');
            }
          }

          reply.send({'result': paragraphs ?? const <String>[]});
        default:
          reply.send({'error': 'Unknown op: $op'});
      }
    } catch (e) {
      reply.send({'error': e.toString()});
    }
  });
}
