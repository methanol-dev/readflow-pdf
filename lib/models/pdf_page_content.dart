class PdfPageContent {
  final int pageIndex;
  final List<String> paragraphs;

  PdfPageContent({
    required this.pageIndex,
    required this.paragraphs,
  });

  String get fullText => paragraphs.join('\n\n');
}
