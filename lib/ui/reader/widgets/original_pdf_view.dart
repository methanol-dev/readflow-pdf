import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as px;

/// Renders the original PDF pages with pinch zoom.
///
/// Owns its pdfx controller, so the native document is only opened while this
/// view is on screen. [currentPage] is 0-based; pdfx page numbers are 1-based.
class OriginalPdfView extends StatefulWidget {
  final String filePath;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  const OriginalPdfView({
    super.key,
    required this.filePath,
    required this.currentPage,
    required this.onPageChanged,
  });

  @override
  State<OriginalPdfView> createState() => _OriginalPdfViewState();
}

class _OriginalPdfViewState extends State<OriginalPdfView> {
  late final px.PdfControllerPinch _controller;

  // The page the view itself last reported, to tell an external page change
  // (TTS, table of contents) from one caused by the user scrolling.
  late int _shownPage;

  @override
  void initState() {
    super.initState();
    _shownPage = widget.currentPage;
    _controller = px.PdfControllerPinch(
      document: px.PdfDocument.openFile(widget.filePath),
      initialPage: widget.currentPage + 1,
    );
  }

  @override
  void didUpdateWidget(OriginalPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPage == _shownPage) return;
    _shownPage = widget.currentPage;
    if (_controller.loadingState.value != px.PdfLoadingState.success) return;
    try {
      _controller.animateToPage(
        pageNumber: widget.currentPage + 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } catch (_) {
      // The view has not been laid out yet; it will stay on its current page.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return px.PdfViewPinch(
      controller: _controller,
      onPageChanged: (page) {
        final pageIndex = page - 1;
        if (pageIndex == _shownPage) return;
        _shownPage = pageIndex;
        widget.onPageChanged(pageIndex);
      },
    );
  }
}
