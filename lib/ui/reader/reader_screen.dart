import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as px;
import '../../models/book.dart';
import '../../models/bookmark.dart';
import '../../models/pdf_page_content.dart';
import '../../models/reader_settings.dart';
import '../../services/database_helper.dart';
import '../../services/pdf_service.dart';
import '../../services/settings_service.dart';
import '../../services/tts_service.dart';
import '../common/tts_player_bar.dart';
import 'dialogs/table_of_contents_dialog.dart';
import 'sheets/theme_sheet.dart';
import 'sheets/typography_sheet.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;

  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late int _currentPage;
  bool _controlsVisible = true;
  bool _isLoadingPage = false;
  final Map<int, PdfPageContent> _pages = {};
  List<Bookmark> _bookmarks = [];
  List<Map<String, dynamic>> _outline = [];

  // Scroll controllers for auto-scrolling to active TTS paragraph
  final ScrollController _singlePageScrollController = ScrollController();
  final ScrollController _continuousScrollController = ScrollController();
  px.PdfControllerPinch? _pdfxController;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.book.lastReadPage.clamp(0, widget.book.pageCount - 1);
    _loadInitialData();

    // Listen to TTS updates to sync visual page & scroll to speaking paragraph
    TtsService.instance.state.addListener(_onTtsStateChanged);
  }

  void _onTtsStateChanged() {
    final tts = TtsService.instance.state.value;
    if (tts.isPlaying && tts.bookId == widget.book.id && tts.currentPage != _currentPage) {
      _changePage(tts.currentPage);
    }
  }

  @override
  void dispose() {
    TtsService.instance.state.removeListener(_onTtsStateChanged);
    _singlePageScrollController.dispose();
    _continuousScrollController.dispose();
    _pdfxController?.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    // 1. Load bookmarks & outline
    _bookmarks = await DatabaseHelper.instance.getBookmarks(widget.book.id ?? 0);
    _outline = await PdfService.instance.getOutline(widget.book.filePath);

    // 2. Load current and next pages
    _loadPage(_currentPage);
    if (_currentPage + 1 < widget.book.pageCount) {
      _loadPage(_currentPage + 1);
    }

    // 3. Init pdfx for original page mode
    try {
      _pdfxController = px.PdfControllerPinch(
        document: px.PdfDocument.openFile(widget.book.filePath),
        initialPage: _currentPage + 1,
      );
    } catch (_) {}

    if (mounted) setState(() {});
  }

  Future<void> _loadPage(int pageIndex) async {
    if (_pages.containsKey(pageIndex)) return;
    setState(() => _isLoadingPage = true);

    final content = await PdfService.instance.loadPageContent(
      bookId: widget.book.id ?? 0,
      filePath: widget.book.filePath,
      pageIndex: pageIndex,
      totalPages: widget.book.pageCount,
    );

    if (mounted) {
      setState(() {
        _pages[pageIndex] = content;
        _isLoadingPage = false;
      });
    }
  }

  void _changePage(int newPage) {
    if (newPage < 0 || newPage >= widget.book.pageCount) return;
    setState(() {
      _currentPage = newPage;
    });

    DatabaseHelper.instance.updateProgress(widget.book.id ?? 0, newPage);
    _loadPage(newPage);
    if (newPage + 1 < widget.book.pageCount) _loadPage(newPage + 1);

    if (_pdfxController != null && _pdfxController!.page != newPage + 1) {
      _pdfxController?.animateToPage(
        pageNumber: newPage + 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }

    if (_singlePageScrollController.hasClients) {
      _singlePageScrollController.jumpTo(0);
    }
  }

  void _toggleBookmark() async {
    final bookId = widget.book.id ?? 0;
    final existing = _bookmarks.where((b) => b.pageIndex == _currentPage).toList();

    if (existing.isNotEmpty) {
      for (var b in existing) {
        if (b.id != null) await DatabaseHelper.instance.deleteBookmark(b.id!);
      }
    } else {
      final newBm = Bookmark(
        bookId: bookId,
        pageIndex: _currentPage,
        title: 'Trang ${_currentPage + 1}',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await DatabaseHelper.instance.insertBookmark(newBm);
    }

    _bookmarks = await DatabaseHelper.instance.getBookmarks(bookId);
    if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final isBookmarked = _bookmarks.any((b) => b.pageIndex == _currentPage);

    return ValueListenableBuilder<ReaderSettings>(
      valueListenable: SettingsService.instance.settings,
      builder: (context, settings, _) {
        final bgColor = settings.backgroundColor;
        final textColor = settings.textColor;

        return Scaffold(
          backgroundColor: bgColor,
          body: Stack(
            children: [
              // 1. Reading Canvas
              Positioned.fill(
                child: settings.viewMode == ViewMode.reflow
                    ? (settings.isContinuousScroll
                        ? _buildContinuousReflowView(settings, textColor)
                        : _buildSinglePageReflowView(settings, textColor))
                    : _buildOriginalPageView(),
              ),

              // 2. Animated Top App Bar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                top: _controlsVisible ? 0 : -100,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.98),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () {
                            TtsService.instance.stop();
                            Navigator.pop(context);
                          },
                          tooltip: 'Trở về thư viện',
                        ),
                        Expanded(
                          child: Text(
                            widget.book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        // View mode toggle
                        IconButton(
                          icon: Icon(
                            settings.viewMode == ViewMode.reflow
                                ? Icons.picture_as_pdf_rounded
                                : Icons.menu_book_rounded,
                          ),
                          onPressed: () {
                            final next = settings.viewMode == ViewMode.reflow
                                ? ViewMode.originalPage
                                : ViewMode.reflow;
                            SettingsService.instance.update(settings.copyWith(viewMode: next));
                          },
                          tooltip: settings.viewMode == ViewMode.reflow
                              ? 'Xem trang gốc PDF'
                              : 'Chế độ đọc chữ (Reflow)',
                        ),
                        // TTS Headphones icon
                        ValueListenableBuilder<TtsState>(
                          valueListenable: TtsService.instance.state,
                          builder: (context, tts, _) {
                            final isTtsActive = tts.isPlaying || tts.isPaused;
                            return IconButton(
                              icon: Icon(
                                Icons.headphones_rounded,
                                color: isTtsActive ? Theme.of(context).colorScheme.primary : null,
                              ),
                              onPressed: _toggleTts,
                              tooltip: 'Sách nói (TTS)',
                            );
                          },
                        ),
                        // Bookmark icon
                        IconButton(
                          icon: Icon(
                            isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                            color: isBookmarked ? Theme.of(context).colorScheme.primary : null,
                          ),
                          onPressed: _toggleBookmark,
                          tooltip: 'Đánh dấu trang',
                        ),
                        // Table of Contents
                        IconButton(
                          icon: const Icon(Icons.list_rounded),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => TableOfContentsDialog(
                                outline: _outline,
                                bookmarks: _bookmarks,
                                currentPage: _currentPage,
                                totalPages: widget.book.pageCount,
                                onSelectPage: _changePage,
                                onDeleteBookmark: (id) async {
                                  await DatabaseHelper.instance.deleteBookmark(id);
                                  _bookmarks = await DatabaseHelper.instance.getBookmarks(widget.book.id ?? 0);
                                  if (mounted) setState(() {});
                                },
                              ),
                            );
                          },
                          tooltip: 'Mục lục & Đánh dấu',
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Animated Bottom Control Bar
              ValueListenableBuilder<TtsState>(
                valueListenable: TtsService.instance.state,
                builder: (context, tts, _) {
                  final isTtsActive = tts.isPlaying || tts.isPaused;
                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    bottom: (_controlsVisible && !isTtsActive) ? 0 : -140,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.98),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress info
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Trang ${_currentPage + 1} / ${widget.book.pageCount}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  Text(
                                    '${((_currentPage + 1) * 100 / widget.book.pageCount).toInt()}%',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Action buttons row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.format_size_rounded),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (_) => const TypographyBottomSheet(),
                                      );
                                    },
                                    tooltip: 'Cỡ chữ & Font',
                                  ),
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.color_lens_rounded),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (_) => const ThemeBottomSheet(),
                                      );
                                    },
                                    tooltip: 'Màu nền & Theme',
                                  ),
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.layers_rounded),
                                    onPressed: () {
                                      final next = settings.viewMode == ViewMode.reflow
                                          ? ViewMode.originalPage
                                          : ViewMode.reflow;
                                      SettingsService.instance.update(settings.copyWith(viewMode: next));
                                    },
                                    tooltip: 'Đổi chế độ xem',
                                  ),
                                  IconButton.filledTonal(
                                    icon: Icon(
                                      settings.isContinuousScroll
                                          ? Icons.swap_vert_rounded
                                          : Icons.swap_horiz_rounded,
                                    ),
                                    onPressed: () {
                                      SettingsService.instance.update(
                                        settings.copyWith(isContinuousScroll: !settings.isContinuousScroll),
                                      );
                                    },
                                    tooltip: settings.isContinuousScroll ? 'Đang cuộn dọc' : 'Đang lật trang',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // 4. Floating TTS Player Bar
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
                      onPrevious: () => TtsService.instance.previousParagraph(),
                      onNext: () => TtsService.instance.nextParagraph(),
                      onStop: () => TtsService.instance.stop(),
                      onSetSpeed: (speed) => TtsService.instance.setSpeechRate(speed),
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

  // --- Single Page View with Horizontal Swipe, Tap Zones & TTS Highlighting ---
  Widget _buildSinglePageReflowView(ReaderSettings settings, Color textColor) {
    final pageContent = _pages[_currentPage];

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -100) {
            _changePage(_currentPage + 1); // Swipe left -> Next
          } else if (details.primaryVelocity! > 100) {
            _changePage(_currentPage - 1); // Swipe right -> Prev
          }
        }
      },
      onTapUp: (details) {
        final screenWidth = MediaQuery.of(context).size.width;
        final x = details.globalPosition.dx;
        if (x < screenWidth * 0.22) {
          _changePage(_currentPage - 1); // Tap left 22% -> Prev
        } else if (x > screenWidth * 0.78) {
          _changePage(_currentPage + 1); // Tap right 22% -> Next
        } else {
          setState(() => _controlsVisible = !_controlsVisible); // Center -> Toggle
        }
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: settings.horizontalPadding.toDouble()),
          child: Column(
            children: [
              const SizedBox(height: 56), // Header space
              // Page header indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Trang ${_currentPage + 1} / ${widget.book.pageCount}',
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    'Vuốt ngang để sang trang',
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoadingPage && pageContent == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _singlePageScrollController,
                        itemCount: (pageContent?.paragraphs.length ?? 0) + 1,
                        itemBuilder: (context, index) {
                          if (index < (pageContent?.paragraphs.length ?? 0)) {
                            final paragraph = pageContent!.paragraphs[index];

                            return ValueListenableBuilder<TtsState>(
                              valueListenable: TtsService.instance.state,
                              builder: (context, tts, _) {
                                final isSpeaking = (tts.isPlaying || tts.isPaused) &&
                                    tts.bookId == widget.book.id &&
                                    tts.currentPage == _currentPage &&
                                    tts.currentParagraphIndex == index;

                                return Container(
                                  margin: EdgeInsets.only(bottom: settings.fontSize * 0.7),
                                  padding: isSpeaking
                                      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                                      : EdgeInsets.zero,
                                  decoration: isSpeaking
                                      ? BoxDecoration(
                                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        )
                                      : null,
                                  child: Text(
                                    paragraph,
                                    textAlign: settings.isJustified ? TextAlign.justify : TextAlign.start,
                                    style: TextStyle(
                                      color: isSpeaking ? Theme.of(context).colorScheme.primary : textColor,
                                      fontSize: settings.fontSize,
                                      height: settings.lineHeightMultiplier,
                                      fontFamily: settings.fontFamilyName,
                                      fontWeight: isSpeaking ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                );
                              },
                            );
                          } else {
                            // End of page card
                            if (_currentPage < widget.book.pageCount - 1) {
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
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(Icons.arrow_forward_rounded, color: textColor, size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox(height: 80);
                          }
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Continuous Vertical Scroll Mode ---
  Widget _buildContinuousReflowView(ReaderSettings settings, Color textColor) {
    return GestureDetector(
      onTap: () => setState(() => _controlsVisible = !_controlsVisible),
      child: SafeArea(
        child: ListView.builder(
          controller: _continuousScrollController,
          padding: EdgeInsets.symmetric(
            horizontal: settings.horizontalPadding.toDouble(),
            vertical: 60,
          ),
          itemCount: widget.book.pageCount,
          itemBuilder: (context, pageIdx) {
            final page = _pages[pageIdx];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Page divider
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      '─── Trang ${pageIdx + 1} / ${widget.book.pageCount} ───',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                if (page != null)
                  ...page.paragraphs.asMap().entries.map((entry) {
                    final pIdx = entry.key;
                    final text = entry.value;

                    return ValueListenableBuilder<TtsState>(
                      valueListenable: TtsService.instance.state,
                      builder: (context, tts, _) {
                        final isSpeaking = (tts.isPlaying || tts.isPaused) &&
                            tts.bookId == widget.book.id &&
                            tts.currentPage == pageIdx &&
                            tts.currentParagraphIndex == pIdx;

                        return Container(
                          margin: EdgeInsets.only(bottom: settings.fontSize * 0.7),
                          padding: isSpeaking
                              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                              : EdgeInsets.zero,
                          decoration: isSpeaking
                              ? BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                )
                              : null,
                          child: Text(
                            text,
                            textAlign: settings.isJustified ? TextAlign.justify : TextAlign.start,
                            style: TextStyle(
                              color: isSpeaking ? Theme.of(context).colorScheme.primary : textColor,
                              fontSize: settings.fontSize,
                              height: settings.lineHeightMultiplier,
                              fontFamily: settings.fontFamilyName,
                              fontWeight: isSpeaking ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    );
                  })
                else
                  FutureBuilder(
                    future: _loadPage(pageIdx),
                    builder: (_, _) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- Original Page View via PDFX ---
  Widget _buildOriginalPageView() {
    if (_pdfxController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onTap: () => setState(() => _controlsVisible = !_controlsVisible),
      child: px.PdfViewPinch(
        controller: _pdfxController!,
        onPageChanged: (page) {
          final newIdx = page - 1;
          if (newIdx != _currentPage) {
            _changePage(newIdx);
          }
        },
      ),
    );
  }
}
