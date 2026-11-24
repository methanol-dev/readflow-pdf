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
  bool _isInitialized = false;

  TtsService._init() {
    _initTts();
  }

  Future<void> _initTts() async {
    if (_isInitialized) return;

    try {
      await _flutterTts.setLanguage('vi-VN');
    } catch (_) {
      try {
        await _flutterTts.setLanguage('vi');
      } catch (_) {}
    }

    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5); // Flutter TTS 0.5 is standard 1.0x normal speech

    _flutterTts.setCompletionHandler(() {
      _onParagraphCompleted();
    });

    _flutterTts.setErrorHandler((msg) {
      if (kDebugMode) print('TTS error: $msg');
    });

    _isInitialized = true;
  }

  Future<void> startReading({
    required Book book,
    required int startPage,
    int startParagraph = 0,
  }) async {
    await _initTts();

    _currentBook = book;
    state.value = state.value.copyWith(
      isPlaying: true,
      isPaused: false,
      bookId: book.id,
      currentPage: startPage,
      currentParagraphIndex: startParagraph,
      totalPages: book.pageCount,
    );

    await _loadAndSpeakCurrentPage(startParagraph);
  }

  Future<void> _loadAndSpeakCurrentPage(int targetParagraph) async {
    final book = _currentBook;
    if (book == null || !state.value.isPlaying) return;

    final page = state.value.currentPage;
    final content = await PdfService.instance.loadPageContent(
      bookId: book.id ?? 0,
      filePath: book.filePath,
      pageIndex: page,
      totalPages: book.pageCount,
    );

    _currentParagraphs = content.paragraphs;

    if (_currentParagraphs.isEmpty) {
      // If page has no text (e.g. image/blank), advance to next page
      if (page < book.pageCount - 1) {
        state.value = state.value.copyWith(
          currentPage: page + 1,
          currentParagraphIndex: 0,
        );
        await DatabaseHelper.instance.updateProgress(book.id ?? 0, page + 1);
        await _loadAndSpeakCurrentPage(0);
      } else {
        stop();
      }
      return;
    }

    final pIdx = targetParagraph.clamp(0, _currentParagraphs.length - 1);
    state.value = state.value.copyWith(
      currentParagraphIndex: pIdx,
      currentText: _currentParagraphs[pIdx],
    );

    _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    if (!state.value.isPlaying || state.value.isPaused) return;

    final pIdx = state.value.currentParagraphIndex;
    if (pIdx >= 0 && pIdx < _currentParagraphs.length) {
      final text = _currentParagraphs[pIdx].trim();
      if (text.isNotEmpty) {
        state.value = state.value.copyWith(currentText: text);
        await _flutterTts.speak(text);
      } else {
        _onParagraphCompleted();
      }
    } else {
      _onParagraphCompleted();
    }
  }

  void _onParagraphCompleted() async {
    if (!state.value.isPlaying || state.value.isPaused) return;

    final nextP = state.value.currentParagraphIndex + 1;
    if (nextP < _currentParagraphs.length) {
      // Next paragraph on same page
      state.value = state.value.copyWith(
        currentParagraphIndex: nextP,
      );
      _speakCurrent();
    } else {
      // Completed all paragraphs of this page -> Auto Advance to Next Page!
      final nextPage = state.value.currentPage + 1;
      final book = _currentBook;
      if (book != null && nextPage < book.pageCount) {
        state.value = state.value.copyWith(
          currentPage: nextPage,
          currentParagraphIndex: 0,
        );
        // Persist reading progress
        await DatabaseHelper.instance.updateProgress(book.id ?? 0, nextPage);
        await _loadAndSpeakCurrentPage(0);
      } else {
        // End of whole book!
        stop();
      }
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
    _speakCurrent();
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    state.value = state.value.copyWith(
      isPlaying: false,
      isPaused: false,
      currentText: '',
    );
  }

  Future<void> nextParagraph() async {
    await _flutterTts.stop();
    final nextP = state.value.currentParagraphIndex + 1;
    if (nextP < _currentParagraphs.length) {
      state.value = state.value.copyWith(currentParagraphIndex: nextP);
      _speakCurrent();
    } else {
      final nextPage = state.value.currentPage + 1;
      final book = _currentBook;
      if (book != null && nextPage < book.pageCount) {
        state.value = state.value.copyWith(
          currentPage: nextPage,
          currentParagraphIndex: 0,
        );
        await _loadAndSpeakCurrentPage(0);
      }
    }
  }

  Future<void> previousParagraph() async {
    await _flutterTts.stop();
    final prevP = state.value.currentParagraphIndex - 1;
    if (prevP >= 0) {
      state.value = state.value.copyWith(currentParagraphIndex: prevP);
      _speakCurrent();
    } else {
      final prevPage = state.value.currentPage - 1;
      final book = _currentBook;
      if (book != null && prevPage >= 0) {
        state.value = state.value.copyWith(
          currentPage: prevPage,
          currentParagraphIndex: 0,
        );
        await _loadAndSpeakCurrentPage(0);
      }
    }
  }

  Future<void> setSpeechRate(double rate) async {
    state.value = state.value.copyWith(speechRate: rate);
    // In FlutterTTS: 0.5 is normal speed (1.0x). Scale accordingly.
    final flutterRate = (rate * 0.5).clamp(0.2, 1.0);
    await _flutterTts.setSpeechRate(flutterRate);
    if (state.value.isPlaying) {
      await _flutterTts.stop();
      _speakCurrent();
    }
  }
}
