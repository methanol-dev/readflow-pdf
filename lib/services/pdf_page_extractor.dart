import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'pdf_text_layout.dart';

/// Extracts the paragraphs of one page of [document].
///
/// Plain extraction returns one fragment per text run, which splits words
/// wherever the PDF switches font (common for Vietnamese diacritics). So the
/// page is read twice, as layout text and as positioned lines, and
/// [paragraphsFromPageText] combines the two.
///
/// If layout extraction throws or produces empty text (for example when a
/// stream uses 0pt fonts or triggers a layout math error), this falls back to
/// positioned lines or plain extraction instead of failing the page.
List<String> extractPageParagraphs(PdfDocument document, int pageIndex) {
  final extractor = PdfTextExtractor(document);

  var layoutText = '';
  var layoutFailed = false;
  try {
    layoutText = extractor.extractText(
      startPageIndex: pageIndex,
      endPageIndex: pageIndex,
      layoutText: true,
    );
  } catch (_) {
    layoutFailed = true;
  }

  List<PdfLinePosition>? positions;
  try {
    positions = [
      for (final line in extractor.extractTextLines(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      ))
        _toLinePosition(line),
    ];
  } catch (_) {
    // Paragraphs are then inferred from the text alone.
  }

  final combined = paragraphsFromPageText(layoutText, positions: positions);
  if (combined.isNotEmpty) return combined;

  if (layoutFailed || layoutText.trim().isEmpty) {
    try {
      final plainText = extractor.extractText(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
        layoutText: false,
      );
      if (plainText.trim().isNotEmpty) {
        return paragraphsFromPageText(plainText, positions: positions);
      }
    } catch (_) {}
  }

  return combined;
}

PdfLinePosition _toLinePosition(TextLine line) {
  final bounds = line.bounds;
  final height = bounds.height > 0 ? bounds.height : line.fontSize;
  return PdfLinePosition(
    text: joinLineWords(
      [
        for (final word in line.wordCollection)
          PdfWordBox(word.text, word.bounds.left, word.bounds.right),
      ],
      height,
    ),
    left: bounds.left,
    top: bounds.top,
    height: height,
  );
}
