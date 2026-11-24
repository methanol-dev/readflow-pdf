class Bookmark {
  final int? id;
  final int bookId;
  final int pageIndex;
  final String title;
  final int createdAt;

  Bookmark({
    this.id,
    required this.bookId,
    required this.pageIndex,
    required this.title,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'page_index': pageIndex,
      'title': title,
      'created_at': createdAt,
    };
  }

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      pageIndex: map['page_index'] as int,
      title: map['title'] as String,
      createdAt: map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
