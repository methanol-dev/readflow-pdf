/// Turns the text of a PDF page into paragraphs.
///
/// Two views of the same page are combined, because neither is reliable for
/// every PDF:
///
/// * Layout text (one visual line per text line) usually has correct word
///   spacing, but for some PDFs it comes back with every space missing.
/// * Positioned lines know where each line and text run sits. Their vertical
///   positions are reliable and reveal paragraph spacing; their horizontal
///   positions drift in some PDFs, which puts spaces inside words.
///
/// So the words come from the layout text unless it has lost its spaces, and
/// the positions are used to find paragraph breaks, which a PDF does not mark.
library;

/// A text run on a line, with its horizontal extent in page units.
class PdfWordBox {
  final String text;
  final double left;
  final double right;

  const PdfWordBox(this.text, this.left, this.right);
}

/// Where a visual line sits on the page, in page units (y grows downwards).
class PdfLinePosition {
  /// The line's text with spacing derived from run positions.
  final String text;
  final double left;
  final double top;
  final double height;

  const PdfLinePosition({
    required this.text,
    required this.left,
    required this.top,
    required this.height,
  });
}

class _Line {
  final String text;
  final bool blankBefore;
  final PdfLinePosition? position;

  const _Line(this.text, {this.blankBefore = false, this.position});
}

// A horizontal gap wider than this fraction of the line height is a space.
// Runs of one word touch or overlap; a space is around 0.2 or more.
const double _wordGapFactor = 0.12;

// A line pitch larger than the page's tightest pitch by this factor means
// extra spacing was inserted, i.e. a paragraph break.
const double _paragraphPitchFactor = 1.25;

// A line shorter than this fraction of the page's longest line is taken to be
// the last line of its paragraph.
const double _shortLineFactor = 0.75;

// Layout text whose words average more characters than this has lost its
// spaces. Real text averages 3 to 7 characters per word.
const double _maxAverageWordLength = 12;

// How far ahead to look for the positioned line matching a layout line.
const int _alignmentWindow = 4;

const List<String> _listMarkers = ['-', '—', '–', '•'];

final RegExp _whitespace = RegExp(r'\s+');
final RegExp _endsWithHyphenatedWord = RegExp(r'\w-$');
final RegExp _startsWithWordChar = RegExp(r'^\w');
final RegExp _endsSentence = RegExp(r'[.!?…”"’»]$');
final RegExp _startsSentence = RegExp(r'^[\p{Lu}0-9“"‘«]', unicode: true);

/// Joins the runs of one line, inserting spaces only where the page has one.
String joinLineWords(List<PdfWordBox> words, double lineHeight) {
  final gapLimit = lineHeight * _wordGapFactor;
  final buffer = StringBuffer();
  double? previousRight;
  var spacePending = false;

  for (final word in words) {
    if (word.text.trim().isEmpty) {
      spacePending = true;
      continue;
    }
    if (previousRight != null) {
      final gap = word.left - previousRight;
      // A large backwards jump is a new block on the same row, not a word part.
      if (spacePending || gap > gapLimit || gap < -lineHeight) {
        buffer.write(' ');
      }
    }
    buffer.write(word.text);
    previousRight = word.right;
    spacePending = false;
  }

  return buffer.toString().replaceAll(_whitespace, ' ').trim();
}

/// Splits a page into paragraphs.
///
/// [layoutText] has one visual line per text line. [positions] are the same
/// page's lines in reading order, when available.
List<String> paragraphsFromPageText(
  String layoutText, {
  List<PdfLinePosition>? positions,
}) {
  final placed = positions?.where((p) => p.text.trim().isNotEmpty).toList() ?? const [];
  final lines = _resolveLines(_parseLayoutLines(layoutText), placed);
  if (lines.isEmpty) return const [];

  final basePitch = _tightestPitch(lines);
  var bodyLeft = double.infinity;
  var longest = 0;
  for (final line in lines) {
    if (line.text.length > longest) longest = line.text.length;
    final left = line.position?.left;
    if (left != null && left < bodyLeft) bodyLeft = left;
  }

  final paragraphs = <String>[];
  final current = StringBuffer(lines.first.text);

  for (var i = 1; i < lines.length; i++) {
    final previous = lines[i - 1];
    final line = lines[i];

    final startsParagraph = line.blankBefore ||
        _listMarkers.any(line.text.startsWith) ||
        previous.text.length < longest * _shortLineFactor ||
        _breaksByPosition(previous, line, basePitch, bodyLeft);

    if (startsParagraph) {
      paragraphs.add(current.toString());
      current.clear();
      current.write(line.text);
      continue;
    }

    final soFar = current.toString();
    if (_endsWithHyphenatedWord.hasMatch(soFar) && _startsWithWordChar.hasMatch(line.text)) {
      // Re-join a word that was hyphenated across the line break.
      current.clear();
      current.write(soFar.substring(0, soFar.length - 1));
    } else {
      current.write(' ');
    }
    current.write(line.text);
  }
  paragraphs.add(current.toString());

  return paragraphs;
}

bool _breaksByPosition(_Line previous, _Line line, double? basePitch, double bodyLeft) {
  final position = line.position;
  final above = previous.position;
  if (position == null || above == null) {
    // No layout information for this pair: fall back to punctuation.
    return _endsSentence.hasMatch(previous.text) && _startsSentence.hasMatch(line.text);
  }

  final pitch = position.top - above.top;
  final movedUp = pitch < -position.height * 0.5;
  final extraSpacing = basePitch != null && pitch > basePitch * _paragraphPitchFactor;
  final indent = position.height * 0.8;
  final firstLineIndent =
      position.left - bodyLeft > indent && position.left - above.left > indent;
  return movedUp || extraSpacing || firstLineIndent;
}

List<_Line> _parseLayoutLines(String layoutText) {
  final lines = <_Line>[];
  var blankBefore = false;
  for (final raw in layoutText.split('\n')) {
    final text = raw.replaceAll(_whitespace, ' ').trim();
    if (text.isEmpty) {
      blankBefore = lines.isNotEmpty;
      continue;
    }
    lines.add(_Line(text, blankBefore: blankBefore));
    blankBefore = false;
  }
  return lines;
}

/// Picks the text source for the page and attaches positions to its lines.
List<_Line> _resolveLines(List<_Line> layoutLines, List<PdfLinePosition> placed) {
  if (placed.isNotEmpty && _hasLostSpaces(layoutLines)) {
    return [for (final row in _mergeSameRow(placed)) _Line(row.text, position: row)];
  }

  // Spacing differs between the two sources, so match lines without it.
  final resolved = <_Line>[];
  var next = 0;
  for (final line in layoutLines) {
    final key = _withoutSpaces(line.text);
    PdfLinePosition? match;
    final end = next + _alignmentWindow < placed.length ? next + _alignmentWindow : placed.length;
    for (var k = next; k < end; k++) {
      if (_withoutSpaces(placed[k].text) == key) {
        match = placed[k];
        next = k + 1;
        break;
      }
    }
    resolved.add(_Line(line.text, blankBefore: line.blankBefore, position: match));
  }
  return resolved;
}

/// Merges positioned lines that share a visual row. A superscript, such as a
/// footnote mark, is reported as a line of its own slightly above its row.
List<PdfLinePosition> _mergeSameRow(List<PdfLinePosition> placed) {
  final rows = <PdfLinePosition>[];
  for (final line in placed) {
    if (rows.isNotEmpty) {
      final row = rows.last;
      final tallest = row.height > line.height ? row : line;
      if ((line.top - row.top).abs() < tallest.height * 0.5) {
        rows[rows.length - 1] = PdfLinePosition(
          text: '${row.text} ${line.text}',
          left: row.left < line.left ? row.left : line.left,
          top: tallest.top,
          height: tallest.height,
        );
        continue;
      }
    }
    rows.add(line);
  }
  return rows;
}

bool _hasLostSpaces(List<_Line> lines) {
  var characters = 0;
  var words = 0;
  for (final line in lines) {
    for (final word in line.text.split(' ')) {
      if (word.isEmpty) continue;
      characters += word.length;
      words++;
    }
  }
  return words == 0 || characters / words > _maxAverageWordLength;
}

String _withoutSpaces(String text) => text.replaceAll(_whitespace, '');

/// The smallest distance between two consecutive lines: the pitch of lines
/// inside a paragraph.
double? _tightestPitch(List<_Line> lines) {
  double? tightest;
  for (var i = 1; i < lines.length; i++) {
    final position = lines[i].position;
    final above = lines[i - 1].position;
    if (position == null || above == null) continue;
    final pitch = position.top - above.top;
    if (pitch > position.height * 0.5 && (tightest == null || pitch < tightest)) {
      tightest = pitch;
    }
  }
  return tightest;
}
