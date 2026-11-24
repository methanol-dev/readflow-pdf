import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/services/pdf_text_layout.dart';

PdfLinePosition _at(String text, double top, {double left = 72}) =>
    PdfLinePosition(text: text, left: left, top: top, height: 14);

void main() {
  group('paragraphsFromPageText', () {
    test('returns no paragraphs for blank text', () {
      expect(paragraphsFromPageText(''), isEmpty);
      expect(paragraphsFromPageText(' \r\n\r\n '), isEmpty);
    });

    test('merges the wrapped lines of a paragraph', () {
      const text = 'Dong mot cua doan van nay keo dai\r\n'
          'dong hai cua doan van nay keo dai\r\n'
          'dong ba cua doan van nay.';
      expect(paragraphsFromPageText(text), [
        'Dong mot cua doan van nay keo dai dong hai cua doan van nay keo dai '
            'dong ba cua doan van nay.',
      ]);
    });

    test('splits on blank lines', () {
      const text = '\r\nDoan mot dai bang dong duoi\r\n\r\nDoan hai dai bang dong tren';
      expect(paragraphsFromPageText(text), [
        'Doan mot dai bang dong duoi',
        'Doan hai dai bang dong tren',
      ]);
    });

    test('ends a paragraph after a short line', () {
      const text = 'Tran chien cuoi cung, lai khong he cung Man Hoang dua kiem\r\n'
          'tro cuoi.\r\n'
          'truc To noi: nguoi tot nhat dung noi nhung loi nay truoc mat';
      expect(paragraphsFromPageText(text), [
        'Tran chien cuoi cung, lai khong he cung Man Hoang dua kiem tro cuoi.',
        'truc To noi: nguoi tot nhat dung noi nhung loi nay truoc mat',
      ]);
    });

    test('uses extra line spacing as a paragraph break', () {
      // The second line is nearly full width and the third starts lowercase,
      // so only the larger pitch reveals the break.
      const lines = [
        'ngu cua lao xa phu thanh mot phong mat tin, ngon tay vung len',
        'thanh truyen tin phi kiem, bay huong Bao Binh Chau ben kia',
        'to Kham hai tay phu sau, nghiem lay mat, choc lat sau, cuoi',
        'dua tay chop mot cai, dem thanh truyen tin phi kiem do xa xa',
      ];
      final paragraphs = paragraphsFromPageText(
        lines.join('\r\n'),
        positions: [
          _at(lines[0], 246.6),
          _at(lines[1], 264.8),
          _at(lines[2], 291.4),
          _at(lines[3], 309.7),
        ],
      );
      expect(paragraphs, [
        '${lines[0]} ${lines[1]}',
        '${lines[2]} ${lines[3]}',
      ]);
    });

    test('matches positions even when their text has stray spaces', () {
      const lines = [
        'Bọn hắn một đường kết bạn nam du này, náo nhiệt vô cùng',
        'trước đó bọn hắn đi ngang qua cửa thành của kinh thành',
      ];
      final paragraphs = paragraphsFromPageText(
        lines.join('\r\n'),
        positions: [
          _at('Bọn h ắn m ột đư ờng k ết b ạn nam du này, náo nhi ệt vô cùng', 99.9),
          _at('trước đó b ọn h ắn đi ngang qua c ửa thành c ủa kinh thành', 150.7),
        ],
      );
      // One pitch only, so nothing marks a break: the text stays joined and
      // keeps the spacing of the layout text, not of the positioned lines.
      expect(paragraphs, ['${lines[0]} ${lines[1]}']);
    });

    test('treats a first-line indent as a paragraph break', () {
      const lines = [
        'mot dong day du chieu rong cua trang sach nay day',
        'Hai dong day du chieu rong cua trang sach nay day',
        'ba dong day du chieu rong cua trang sach nay day',
      ];
      final paragraphs = paragraphsFromPageText(
        lines.join('\r\n'),
        positions: [
          _at(lines[0], 100),
          _at(lines[1], 118, left: 100),
          _at(lines[2], 136),
        ],
      );
      expect(paragraphs, [lines[0], '${lines[1]} ${lines[2]}']);
    });

    test('takes the text from positions when the layout text lost its spaces', () {
      final paragraphs = paragraphsFromPageText(
        'Chương83KimNhậtVôSự\r\nTrầnsơnchủcuốicùngcũnghiệnthân,dẫntheoTạCẩu',
        positions: [
          _at('Chương 83 Kim Nhật Vô Sự', 80),
          _at('Trần sơn chủ cuối cùng cũng hiện thân, dẫn theo Tạ Cẩu', 120),
        ],
      );
      expect(paragraphs, [
        'Chương 83 Kim Nhật Vô Sự',
        'Trần sơn chủ cuối cùng cũng hiện thân, dẫn theo Tạ Cẩu',
      ]);
    });

    test('keeps a superscript on the row it belongs to', () {
      final paragraphs = paragraphsFromPageText(
        'mộtdòngvănbảnkéodàicóchúthíchiivàphầncònlạicủadòng\r\ndòngtiếptheocủađoạnvănnàycũngdàinhưvậy',
        positions: [
          _at('một dòng văn bản kéo dài có chú thích', 100),
          PdfLinePosition(text: 'ii', left: 300, top: 97, height: 9),
          _at('và phần còn lại của dòng', 100, left: 310),
          _at('dòng tiếp theo của đoạn văn này cũng dài như vậy', 118),
        ],
      );
      expect(paragraphs, [
        'một dòng văn bản kéo dài có chú thích ii và phần còn lại của dòng '
            'dòng tiếp theo của đoạn văn này cũng dài như vậy',
      ]);
    });

    test('joinLineWords spaces runs by the gap between them', () {
      const words = [
        PdfWordBox('Tr', 72.0, 82.9),
        PdfWordBox('ậ', 82.6, 89.3),
        PdfWordBox('n', 89.3, 96.7),
        PdfWordBox(' ', 96.6, 99.8),
        PdfWordBox('chi', 99.7, 116.2),
        PdfWordBox('ế', 116.2, 123.2),
        PdfWordBox('n', 123.1, 130.5),
        // No space run here, only a gap.
        PdfWordBox('cùng', 133.7, 160.8),
      ];
      expect(joinLineWords(words, 14), 'Trận chiến cùng');
    });

    test('ignores positions that do not line up with the text', () {
      const lines = [
        'Cau thu nhat ket thuc o cuoi dong nay.',
        'Cau thu hai bat dau o dau dong nay roi.',
      ];
      final paragraphs = paragraphsFromPageText(
        lines.join('\r\n'),
        positions: [_at('mot dong khac han', 100)],
      );
      // Falls back to punctuation: sentence end followed by a capital.
      expect(paragraphs, lines);
    });

    test('starts a new paragraph at list markers', () {
      const text = 'Danh sach cac muc can lam hom nay\r\n'
          '- Muc thu nhat can lam hom nay day\r\n'
          '• Muc thu hai can lam hom nay day';
      expect(paragraphsFromPageText(text), [
        'Danh sach cac muc can lam hom nay',
        '- Muc thu nhat can lam hom nay day',
        '• Muc thu hai can lam hom nay day',
      ]);
    });

    test('re-joins a word hyphenated across a line break', () {
      const text = 'this line of text ends with an exam-\r\n'
          'ple that continues on the next line';
      expect(paragraphsFromPageText(text), [
        'this line of text ends with an example that continues on the next line',
      ]);
    });
  });
}
