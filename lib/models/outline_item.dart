/// One entry of a PDF's built-in table of contents.
class OutlineItem {
  final String title;

  /// 0-based index of the page this entry points to.
  final int pageIndex;

  const OutlineItem({required this.title, required this.pageIndex});
}
