class PdfPageContent {
  final int pageIndex;
  final List<String> paragraphs;
  final bool isError;

  PdfPageContent({
    required this.pageIndex,
    required this.paragraphs,
    this.isError = false,
  });

  String get fullText => paragraphs.join('\n\n');
}
