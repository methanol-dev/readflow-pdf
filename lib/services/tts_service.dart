import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/book.dart';
import 'database_helper.dart';
import 'pdf_service.dart';

class TtsState {
  final bool isPlaying;
  final bool isPaused;
  final int? bookId;
  final int currentPage;
  final int currentParagraphIndex;
  final int totalPages;
  final double speechRate;
  final String currentText;

  const TtsState({
    this.isPlaying = false,
    this.isPaused = false,
    this.bookId,
    this.currentPage = 0,
    this.currentParagraphIndex = 0,
    this.totalPages = 1,
    this.speechRate = 1.0,
    this.currentText = '',
  });

  /// True while a reading session exists, playing or paused.
  bool get isActive => isPlaying || isPaused;

  TtsState copyWith({
    bool? isPlaying,
    bool? isPaused,
    int? bookId,
    int? currentPage,
    int? currentParagraphIndex,
    int? totalPages,
    double? speechRate,
    String? currentText,
  }) {
    return TtsState(
      isPlaying: isPlaying ?? this.isPlaying,
      isPaused: isPaused ?? this.isPaused,
      bookId: bookId ?? this.bookId,
      currentPage: currentPage ?? this.currentPage,
      currentParagraphIndex: currentParagraphIndex ?? this.currentParagraphIndex,
      totalPages: totalPages ?? this.totalPages,
      speechRate: speechRate ?? this.speechRate,
      currentText: currentText ?? this.currentText,
    );
  }
}

class TtsService {
  static final TtsService instance = TtsService._init();
  final FlutterTts _flutterTts = FlutterTts();
  final ValueNotifier<TtsState> state = ValueNotifier(const TtsState());

  Book? _currentBook;
  List<String> _currentParagraphs = [];
  Future<void>? _initialization;

  // Bumped whenever the reading position is replaced, so a page load that
  // finishes late does not overwrite a newer position.
  int _positionVersion = 0;

  TtsService._init();

  Future<void> _ensureInitialized() {
    return _initialization ??= _configureTts().catchError((Object error) {
      _initialization = null;
      throw error;
    });
  }

  Future<void> _configureTts() async {
    try {
      await _flutterTts.setLanguage('vi-VN');
    } catch (_) {
      try {
        await _flutterTts.setLanguage('vi');
      } catch (_) {}
    }

    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(_engineRate(state.value.speechRate));

    _flutterTts.setCompletionHandler(_onParagraphCompleted);
    _flutterTts.setErrorHandler((msg) {
      if (kDebugMode) print('TTS error: $msg');
    });
  }

  // flutter_tts treats 0.5 as normal speed, so the user-facing 1.0x maps to 0.5.
  double _engineRate(double userRate) => (userRate * 0.5).clamp(0.2, 1.0);

  Future<void> startReading({
    required Book book,
    required int startPage,
    int startParagraph = 0,
  }) async {
    await _ensureInitialized();

    _currentBook = book;
    state.value = state.value.copyWith(
      isPlaying: true,
      isPaused: false,
      bookId: book.id,
      currentPage: startPage,
      currentParagraphIndex: startParagraph,
      totalPages: book.pageCount,
    );

    await _goToPage(startPage, paragraph: startParagraph);
  }

  /// Moves the reading position to [page] and speaks from [paragraph].
  /// Pages without text (blank or image-only) are skipped forward; reaching
  /// the end of the book stops the session.
  Future<void> _goToPage(int page, {int paragraph = 0}) async {
    final book = _currentBook;
    if (book == null) return;
    final version = ++_positionVersion;
    final bookId = book.id ?? 0;

    var targetPage = page;
    var targetParagraph = paragraph;
    List<String> paragraphs;
    while (true) {
      if (targetPage >= book.pageCount) {
        await stop();
        return;
      }
      final content = await PdfService.instance.loadPageContent(
        bookId: bookId,
        filePath: book.filePath,
        pageIndex: targetPage,
        totalPages: book.pageCount,
      );
      if (version != _positionVersion) return;
      paragraphs = content.paragraphs;
      if (paragraphs.isNotEmpty) break;
      targetPage++;
      targetParagraph = 0;
    }

    final index = targetParagraph.clamp(0, paragraphs.length - 1);
    _currentParagraphs = paragraphs;
    state.value = state.value.copyWith(
      currentPage: targetPage,
      currentParagraphIndex: index,
      currentText: paragraphs[index],
    );
    unawaited(
      DatabaseHelper.instance
          .updateProgress(bookId, targetPage)
          .catchError((Object _) => 0),
    );

    await _speakCurrent();
  }

  void _goToParagraph(int index) {
    state.value = state.value.copyWith(
      currentParagraphIndex: index,
      currentText: _currentParagraphs[index],
    );
  }

  Future<void> _speakCurrent() async {
    if (!state.value.isPlaying) return;

    final index = state.value.currentParagraphIndex;
    if (index < 0 || index >= _currentParagraphs.length) return;
    await _flutterTts.speak(_currentParagraphs[index]);
  }

  void _onParagraphCompleted() {
    if (!state.value.isPlaying) return;

    if (_hasNext) {
      _advance();
    } else {
      // End of the whole book.
      stop();
    }
  }

  bool get _hasNext {
    final book = _currentBook;
    if (book == null) return false;
    return state.value.currentParagraphIndex + 1 < _currentParagraphs.length ||
        state.value.currentPage + 1 < book.pageCount;
  }

  bool get _hasPrevious =>
      _currentBook != null &&
      (state.value.currentParagraphIndex > 0 || state.value.currentPage > 0);

  /// Moves to the next paragraph, or to the next page after the last one.
  Future<void> _advance() async {
    final next = state.value.currentParagraphIndex + 1;
    if (next < _currentParagraphs.length) {
      _goToParagraph(next);
      await _speakCurrent();
    } else {
      await _goToPage(state.value.currentPage + 1);
    }
  }

  Future<void> pause() async {
    await _flutterTts.stop();
    state.value = state.value.copyWith(
      isPlaying: false,
      isPaused: true,
    );
  }

  Future<void> resume() async {
    if (_currentBook == null) return;
    state.value = state.value.copyWith(
      isPlaying: true,
      isPaused: false,
    );
    await _speakCurrent();
  }

  Future<void> stop() async {
    _positionVersion++;
    await _flutterTts.stop();
    state.value = state.value.copyWith(
      isPlaying: false,
      isPaused: false,
      currentText: '',
    );
  }

  Future<void> nextParagraph() async {
    if (!_hasNext) return;
    await _flutterTts.stop();
    await _advance();
  }

  Future<void> previousParagraph() async {
    if (!_hasPrevious) return;
    await _flutterTts.stop();
    final previous = state.value.currentParagraphIndex - 1;
    if (previous >= 0) {
      _goToParagraph(previous);
      await _speakCurrent();
    } else {
      await _goToPage(state.value.currentPage - 1);
    }
  }

  Future<void> setSpeechRate(double rate) async {
    state.value = state.value.copyWith(speechRate: rate);
    await _ensureInitialized();
    await _flutterTts.setSpeechRate(_engineRate(rate));
    if (state.value.isPlaying) {
      await _flutterTts.stop();
      await _speakCurrent();
    }
  }
}
