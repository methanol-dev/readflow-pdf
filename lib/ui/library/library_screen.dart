import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/book.dart';
import '../../services/database_helper.dart';
import '../../services/pdf_service.dart';
import '../reader/reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Book> _books = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  // The spinner is only shown for the first load; later refreshes swap the
  // list in place.
  Future<void> _loadBooks() async {
    final books = await DatabaseHelper.instance.getBooks();
    if (mounted) {
      setState(() {
        _books = books;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndOpenPdf() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (files.isEmpty || files.first.path == null) {
        return;
      }

      final path = files.first.path!;
      final file = File(path);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể tìm thấy file PDF đã chọn')),
          );
        }
        return;
      }

      final existing = await DatabaseHelper.instance.getBookByPath(path);
      if (existing != null) {
        _openReader(existing);
        return;
      }

      // Calculate title and page count
      final rawName = files.first.name;
      final title = rawName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final pageCount = await PdfService.instance.getPageCount(path);
      final sizeBytes = await file.length();

      final newBook = Book(
        title: title,
        filePath: path,
        pageCount: pageCount > 0 ? pageCount : 1,
        lastReadPage: 0,
        lastReadTime: DateTime.now().millisecondsSinceEpoch,
        fileSizeBytes: sizeBytes,
      );

      final id = await DatabaseHelper.instance.insertBook(newBook);
      final savedBook = newBook.copyWith(id: id);

      await _loadBooks();
      _openReader(savedBook);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi mở file: $e')),
        );
      }
    }
  }

  void _openReader(Book book) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
    _loadBooks();
  }

  void _confirmDelete(Book book) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc chắn muốn xóa "${book.title}" khỏi thư viện?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (book.id != null) {
                await DatabaseHelper.instance.deleteBook(book.id!);
                _loadBooks();
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ReadFlow',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            Text(
              'Đọc truyện & Sách nói PDF Đa nền tảng',
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? _buildEmptyState()
              : _buildBookList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndOpenPdf,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Mở file PDF'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            const Text(
              'Thư viện của bạn đang trống',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nhấn nút "Mở file PDF" bên dưới để chọn sách từ điện thoại và bắt đầu trải nghiệm đọc thông minh hoặc nghe sách nói.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookList() {
    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 90),
      itemCount: _books.length,
      itemBuilder: (context, index) {
        final book = _books[index];
        final percent = ((book.lastReadPage + 1) * 100 / book.pageCount).clamp(0, 100).toInt();

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: () => _openReader(book),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Book icon / badge
                  Container(
                    width: 50,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      size: 28,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Book details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              'Đang đọc trang ${book.lastReadPage + 1} / ${book.pageCount}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const Spacer(),
                            Text(
                              '$percent%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (book.lastReadPage + 1) / book.pageCount,
                          borderRadius: BorderRadius.circular(4),
                          minHeight: 4,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'delete') {
                        _confirmDelete(book);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            SizedBox(width: 8),
                            Text('Xóa khỏi thư viện', style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
