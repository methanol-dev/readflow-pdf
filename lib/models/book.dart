class Book {
  final int? id;
  final String title;
  final String filePath;
  final int pageCount;
  final int lastReadPage;
  final int lastReadTime;
  final int fileSizeBytes;
  final String? coverPath;

  Book({
    this.id,
    required this.title,
    required this.filePath,
    required this.pageCount,
    this.lastReadPage = 0,
    required this.lastReadTime,
    this.fileSizeBytes = 0,
    this.coverPath,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'file_path': filePath,
      'page_count': pageCount,
      'last_read_page': lastReadPage,
      'last_read_time': lastReadTime,
      'file_size_bytes': fileSizeBytes,
      'cover_path': coverPath,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as int?,
      title: map['title'] as String,
      filePath: map['file_path'] as String,
      pageCount: map['page_count'] as int,
      lastReadPage: map['last_read_page'] as int? ?? 0,
      lastReadTime: map['last_read_time'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      fileSizeBytes: map['file_size_bytes'] as int? ?? 0,
      coverPath: map['cover_path'] as String?,
    );
  }

  Book copyWith({
    int? id,
    String? title,
    String? filePath,
    int? pageCount,
    int? lastReadPage,
    int? lastReadTime,
    int? fileSizeBytes,
    String? coverPath,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      pageCount: pageCount ?? this.pageCount,
      lastReadPage: lastReadPage ?? this.lastReadPage,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      coverPath: coverPath ?? this.coverPath,
    );
  }
}
