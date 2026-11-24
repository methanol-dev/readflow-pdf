import 'package:flutter/material.dart';
import '../../models/book.dart';
import '../../models/bookmark.dart';
import '../../models/outline_item.dart';
import '../../models/pdf_page_content.dart';
import '../../models/reader_settings.dart';
import '../../services/database_helper.dart';
import '../../services/pdf_service.dart';
import '../../services/settings_service.dart';
import '../../services/tts_service.dart';
import '../common/tts_player_bar.dart';
import 'dialogs/table_of_contents_dialog.dart';
import 'widgets/original_pdf_view.dart';
import 'widgets/reader_bottom_bar.dart';
import 'widgets/reader_paragraph.dart';
import 'widgets/reader_top_bar.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;

  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _controlsAnimation = Duration(milliseconds: 200);

  late int _currentPage;
  bool _controlsVisible = true;
  final Map<int, PdfPageContent> _pages = {};
  final Set<int> _loadingPages = {};
  List<Bookmark> _bookmarks = [];
  List<OutlineItem> _outline = [];

  final ScrollController _singlePageScrollController = ScrollController();

  int get _bookId => widget.book.id ?? 0;
  int get _pageCount => widget.book.pageCount;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.book.lastReadPage.clamp(0, _pageCount - 1);
    _loadPage(_currentPage);
    _loadPage(_currentPage + 1);
    _loadBookmarksAndOutline();

    // Follow the page TTS is reading.
    TtsService.instance.state.addListener(_onTtsStateChanged);
  }

  @override
  void dispose() {
    final tts = TtsService.instance;
    tts.state.removeListener(_onTtsStateChanged);
    // The player controls only exist on this screen, so playback ends with it.
    if (tts.state.value.isActive && tts.state.value.bookId == widget.book.id) {
      tts.stop();
    }
    PdfService.instance.releaseDocument();
    _singlePageScrollController.dispose();
    super.dispose();
  }

  void _onTtsStateChanged() {
    final tts = TtsService.instance.state.value;
    if (tts.isActive && tts.bookId == widget.book.id && tts.currentPage != _currentPage) {
      // TtsService already persisted this position.
      _changePage(tts.currentPage, persist: false);
    }
  }

  Future<void> _loadBookmarksAndOutline() async {
    final bookmarksFuture = DatabaseHelper.instance.getBookmarks(_bookId);
    final outline = await PdfService.instance.getOutline(widget.book.filePath);
    final bookmarks = await bookmarksFuture;
    if (!mounted) return;
    setState(() {
      _bookmarks = bookmarks;
      _outline = outline;
    });
  }

  /// Loads a page's text unless it is already loaded or loading. Does not call
  /// setState synchronously, so it is safe to call while building.
  Future<void> _loadPage(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= _pageCount) return;
    if (_pages.containsKey(pageIndex) || !_loadingPages.add(pageIndex)) return;

    try {
      final content = await PdfService.instance.loadPageContent(
        bookId: _bookId,
        filePath: widget.book.filePath,
        pageIndex: pageIndex,
        totalPages: _pageCount,
      );
      if (mounted) setState(() => _pages[pageIndex] = content);
    } finally {
      _loadingPages.remove(pageIndex);
    }
  }

  void _changePage(int newPage, {bool persist = true}) {
    if (newPage < 0 || newPage >= _pageCount || newPage == _currentPage) return;
    setState(() => _currentPage = newPage);

    if (persist) DatabaseHelper.instance.updateProgress(_bookId, newPage);
    _loadPage(newPage);
    _loadPage(newPage + 1);

    if (_singlePageScrollController.hasClients) {
      _singlePageScrollController.jumpTo(0);
    }
  }

  Future<void> _reloadBookmarks() async {
    final bookmarks = await DatabaseHelper.instance.getBookmarks(_bookId);
    if (mounted) setState(() => _bookmarks = bookmarks);
  }

  Future<void> _toggleBookmark() async {
    final existing = _bookmarks.where((b) => b.pageIndex == _currentPage).toList();

    if (existing.isNotEmpty) {
      for (final bookmark in existing) {
        if (bookmark.id != null) await DatabaseHelper.instance.deleteBookmark(bookmark.id!);
      }
    } else {
      await DatabaseHelper.instance.insertBookmark(Bookmark(
        bookId: _bookId,
        pageIndex: _currentPage,
        title: 'Trang ${_currentPage + 1}',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }

    await _reloadBookmarks();
  }

  void _toggleTts() {
    final tts = TtsService.instance.state.value;
    if (tts.isPlaying) {
      TtsService.instance.pause();
    } else if (tts.isPaused && tts.bookId == widget.book.id) {
      TtsService.instance.resume();
    } else {
      TtsService.instance.startReading(
        book: widget.book,
        startPage: _currentPage,
        startParagraph: 0,
      );
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
  }

  void _toggleViewMode() {
    final settings = SettingsService.instance.settings.value;
    final next = settings.viewMode == ViewMode.reflow ? ViewMode.originalPage : ViewMode.reflow;
    SettingsService.instance.update(settings.copyWith(viewMode: next));
  }

  void _openContents() {
    showDialog(
      context: context,
      builder: (_) => TableOfContentsDialog(
        outline: _outline,
        bookmarks: _bookmarks,
        currentPage: _currentPage,
        totalPages: _pageCount,
        onSelectPage: _changePage,
        onDeleteBookmark: (id) async {
          await DatabaseHelper.instance.deleteBookmark(id);
          await _reloadBookmarks();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBookmarked = _bookmarks.any((b) => b.pageIndex == _currentPage);

    return ValueListenableBuilder<ReaderSettings>(
      valueListenable: SettingsService.instance.settings,
      builder: (context, settings, _) {
        return Scaffold(
          backgroundColor: settings.backgroundColor,
          body: Stack(
            children: [
              // 1. Reading canvas
              Positioned.fill(child: _buildCanvas(settings)),

              // 2. Top app bar
              AnimatedPositioned(
                duration: _controlsAnimation,
                top: _controlsVisible ? 0 : -100,
                left: 0,
                right: 0,
                child: ReaderTopBar(
                  title: widget.book.title,
                  viewMode: settings.viewMode,
                  isBookmarked: isBookmarked,
                  onBack: () {
                    // Stop now rather than after the pop transition finishes.
                    TtsService.instance.stop();
                    Navigator.pop(context);
                  },
                  onToggleViewMode: _toggleViewMode,
                  onToggleTts: _toggleTts,
                  onToggleBookmark: _toggleBookmark,
                  onOpenContents: _openContents,
                ),
              ),

              // 3. Bottom control bar, replaced by the player while TTS is active
              ValueListenableBuilder<TtsState>(
                valueListenable: TtsService.instance.state,
                builder: (context, tts, child) {
                  return AnimatedPositioned(
                    duration: _controlsAnimation,
                    bottom: (_controlsVisible && !tts.isActive) ? 0 : -140,
                    left: 0,
                    right: 0,
                    child: child!,
                  );
                },
                child: ReaderBottomBar(
                  currentPage: _currentPage,
                  pageCount: _pageCount,
                  settings: settings,
                  onToggleViewMode: _toggleViewMode,
                ),
              ),

              // 4. Floating TTS player bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<TtsState>(
                  valueListenable: TtsService.instance.state,
                  builder: (context, tts, _) {
                    return TtsPlayerBar(
                      state: tts,
                      onTogglePlay: _toggleTts,
                      onPrevious: TtsService.instance.previousParagraph,
                      onNext: TtsService.instance.nextParagraph,
                      onStop: TtsService.instance.stop,
                      onSetSpeed: TtsService.instance.setSpeechRate,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCanvas(ReaderSettings settings) {
    if (settings.viewMode == ViewMode.originalPage) {
      return GestureDetector(
        onTap: _toggleControls,
        child: OriginalPdfView(
          filePath: widget.book.filePath,
          currentPage: _currentPage,
          onPageChanged: _changePage,
        ),
      );
    }
    return settings.isContinuousScroll
        ? _buildContinuousReflowView(settings)
        : _buildSinglePageReflowView(settings);
  }

  // --- Single page: horizontal swipe, tap zones on the left and right edges ---
  Widget _buildSinglePageReflowView(ReaderSettings settings) {
    final paragraphs = _pages[_currentPage]?.paragraphs;
    final hintStyle = TextStyle(
      fontSize: 11,
      color: settings.textColor.withValues(alpha: 0.5),
    );

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity;
        if (velocity == null) return;
        if (velocity < -100) {
          _changePage(_currentPage + 1); // Swipe left -> next
        } else if (velocity > 100) {
          _changePage(_currentPage - 1); // Swipe right -> previous
        }
      },
      onTapUp: (details) {
        final screenWidth = MediaQuery.of(context).size.width;
        final x = details.globalPosition.dx;
        if (x < screenWidth * 0.22) {
          _changePage(_currentPage - 1);
        } else if (x > screenWidth * 0.78) {
          _changePage(_currentPage + 1);
        } else {
          _toggleControls();
        }
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: settings.horizontalPadding.toDouble()),
          child: Column(
            children: [
              const SizedBox(height: 56), // Space for the top bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Trang ${_currentPage + 1} / $_pageCount', style: hintStyle),
                  Text('Vuốt ngang để sang trang', style: hintStyle),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: paragraphs == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _singlePageScrollController,
                        itemCount: paragraphs.length + 1,
                        itemBuilder: (context, index) {
                          if (index == paragraphs.length) {
                            return _buildEndOfPageCard(settings.textColor);
                          }
                          return ReaderParagraph(
                            text: paragraphs[index],
                            bookId: widget.book.id,
                            pageIndex: _currentPage,
                            paragraphIndex: index,
                            settings: settings,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEndOfPageCard(Color textColor) {
    if (_currentPage >= _pageCount - 1) return const SizedBox(height: 80);

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 80),
      child: InkWell(
        onTap: () => _changePage(_currentPage + 1),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Hết trang ${_currentPage + 1} • Sang Trang ${_currentPage + 2}',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: textColor, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // --- Continuous vertical scroll: one list item per page, loaded lazily ---
  Widget _buildContinuousReflowView(ReaderSettings settings) {
    return GestureDetector(
      onTap: _toggleControls,
      child: SafeArea(
        child: ListView.builder(
          padding: EdgeInsets.symmetric(
            horizontal: settings.horizontalPadding.toDouble(),
            vertical: 60,
          ),
          itemCount: _pageCount,
          itemBuilder: (context, pageIndex) {
            final paragraphs = _pages[pageIndex]?.paragraphs;
            if (paragraphs == null) _loadPage(pageIndex);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      '─── Trang ${pageIndex + 1} / $_pageCount ───',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: settings.textColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                if (paragraphs == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  for (final (index, text) in paragraphs.indexed)
                    ReaderParagraph(
                      text: text,
                      bookId: widget.book.id,
                      pageIndex: pageIndex,
                      paragraphIndex: index,
                      settings: settings,
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
