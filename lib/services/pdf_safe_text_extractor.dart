import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:math' as math;
import 'dart:typed_data';

import 'pdf_text_layout.dart';

/// Pure-Dart, strictly bounded PDF text extractor used as a resilient fallback
/// when Syncfusion's extractor throws, times out (e.g. inline images or cyclic
/// Form XObjects), or skips inherited page resources.
///
/// Every loop advances its byte cursor strictly or enforces an explicit bound,
/// so malformed streams can never hang the isolate.
List<String> extractPageParagraphsSafe(Uint8List pdfBytes, int pageIndex) {
  final doc = _PdfRawDoc.parse(pdfBytes);
  if (doc == null) return const [];
  final pageRef = doc.pageAt(pageIndex);
  if (pageRef == null) return const [];

  final page = pageRef.dict;
  final resources = doc.resolvePageResources(pageRef);
  final fonts = _buildFontDecoders(doc, resources);
  final xObjects = doc.asDict(resources['XObject']);

  final collector = _TextRunCollector();
  _interpretPageContents(
    doc: doc,
    contentEntry: page['Contents'],
    fonts: fonts,
    xObjects: xObjects,
    collector: collector,
  );

  final positions = collector.toLinePositions();
  if (positions.isEmpty) return const [];
  return paragraphsFromPageText('', positions: positions);
}

/// Fast safe page count lookup from raw PDF bytes when Syncfusion fails.
int? getPageCountSafe(Uint8List pdfBytes) {
  final doc = _PdfRawDoc.parse(pdfBytes);
  if (doc == null) return null;
  final count = doc.pageCount;
  return count > 0 ? count : null;
}

// ---------------------------------------------------------------------------
// PDF object model & parser
// ---------------------------------------------------------------------------

class _PdfRef {
  final int objNum;
  final int genNum;
  const _PdfRef(this.objNum, this.genNum);

  @override
  bool operator ==(Object other) =>
      other is _PdfRef && other.objNum == objNum && other.genNum == genNum;

  @override
  int get hashCode => Object.hash(objNum, genNum);
}

class _PdfName {
  final String name;
  const _PdfName(this.name);
}

class _PdfStr {
  final Uint8List bytes;
  const _PdfStr(this.bytes);
}

class _PdfStream {
  final Map<String, Object?> dict;
  final Uint8List rawBytes;
  const _PdfStream(this.dict, this.rawBytes);
}

class _PageEntry {
  final Map<String, Object?> dict;
  final List<Map<String, Object?>> inheritedResources;
  const _PageEntry(this.dict, this.inheritedResources);
}

class _PdfRawDoc {
  final Uint8List bytes;
  final Map<int, int> _offsets = {};
  final Map<int, _CompressedEntry> _compressed = {};
  final Map<int, Object?> _objectCache = {};
  final Map<int, Map<int, Object?>> _objStmCache = {};
  Map<String, Object?>? _trailer;
  List<_PageEntry>? _pages;

  _PdfRawDoc._(this.bytes);

  static _PdfRawDoc? parse(Uint8List bytes) {
    if (bytes.length < 16) return null;
    final doc = _PdfRawDoc._(bytes);
    doc._loadXref();
    if (doc._trailer == null) {
      doc._scanLinearObjects();
    }
    return doc._trailer == null ? null : doc;
  }

  int get pageCount => _ensurePages().length;

  _PageEntry? pageAt(int index) {
    final pages = _ensurePages();
    if (index < 0 || index >= pages.length) return null;
    return pages[index];
  }

  List<_PageEntry> _ensurePages() {
    if (_pages != null) return _pages!;
    final result = <_PageEntry>[];
    final root = asDict(_trailer?['Root']);
    if (root == null) return _pages = result;
    final pagesRoot = deref(root['Pages']);
    if (pagesRoot is Map<String, Object?>) {
      final visited = <int>{};
      final rootRef = root['Pages'];
      if (rootRef is _PdfRef) visited.add(rootRef.objNum);
      _collectPages(pagesRoot, const [], result, visited, 0);
    }
    return _pages = result;
  }

  void _collectPages(
    Map<String, Object?> node,
    List<Map<String, Object?>> inheritedResources,
    List<_PageEntry> out,
    Set<int> visited,
    int depth,
  ) {
    if (depth > 64) return;
    final ownRes = asDict(node['Resources']);
    final nextResources = ownRes != null
        ? [...inheritedResources, ownRes]
        : inheritedResources;

    final kids = asList(node['Kids']);
    if (kids != null) {
      for (final kid in kids) {
        if (kid is _PdfRef && !visited.add(kid.objNum)) continue;
        final resolved = asDict(kid);
        if (resolved == null) continue;
        final type = asName(resolved['Type']);
        if (type == 'Page' || !resolved.containsKey('Kids')) {
          final pageOwnRes = asDict(resolved['Resources']);
          final pageResList = pageOwnRes != null
              ? [...nextResources, pageOwnRes]
              : nextResources;
          out.add(_PageEntry(resolved, pageResList));
        } else {
          _collectPages(resolved, nextResources, out, visited, depth + 1);
        }
      }
      return;
    }

    if (asName(node['Type']) == 'Page') {
      out.add(_PageEntry(node, nextResources));
    }
  }

  Map<String, Object?> resolvePageResources(_PageEntry entry) {
    final merged = <String, Object?>{};
    for (final res in entry.inheritedResources) {
      for (final category in const ['Font', 'XObject']) {
        final sub = asDict(res[category]);
        if (sub == null) continue;
        final target = (merged[category] as Map<String, Object?>?) ??
            (merged[category] = <String, Object?>{});
        target.addAll(sub);
      }
    }
    return merged;
  }

  Object? deref(Object? value, [int depth = 0]) {
    var current = value;
    var steps = depth;
    while (current is _PdfRef && steps < 16) {
      current = _readObject(current.objNum);
      steps++;
    }
    return current;
  }

  Map<String, Object?>? asDict(Object? value) {
    final resolved = deref(value);
    if (resolved is Map<String, Object?>) return resolved;
    if (resolved is _PdfStream) return resolved.dict;
    return null;
  }

  List<Object?>? asList(Object? value) {
    final resolved = deref(value);
    return resolved is List<Object?> ? resolved : null;
  }

  String? asName(Object? value) {
    final resolved = deref(value);
    return resolved is _PdfName ? resolved.name : null;
  }

  int? asInt(Object? value) {
    final resolved = deref(value);
    if (resolved is int) return resolved;
    if (resolved is double) return resolved.toInt();
    return null;
  }

  Uint8List? decodeStream(_PdfStream stream) {
    var data = stream.rawBytes;
    final filterRaw = deref(stream.dict['Filter']);
    final filters = <String>[];
    if (filterRaw is _PdfName) {
      filters.add(filterRaw.name);
    } else if (filterRaw is List<Object?>) {
      for (final f in filterRaw) {
        final name = asName(f);
        if (name != null) filters.add(name);
      }
    }
    if (filters.isEmpty) return data;

    final decodeParmsRaw = deref(stream.dict['DecodeParms']);
    for (var i = 0; i < filters.length; i++) {
      final filter = filters[i];
      Map<String, Object?>? parms;
      if (decodeParmsRaw is Map<String, Object?>) {
        parms = decodeParmsRaw;
      } else if (decodeParmsRaw is List<Object?> && i < decodeParmsRaw.length) {
        parms = asDict(decodeParmsRaw[i]);
      }

      if (filter == 'FlateDecode' || filter == 'Fl') {
        final decoded = _inflateBytes(data);
        if (decoded == null) return null;
        data = _applyPredictor(decoded, parms);
      } else if (filter == 'ASCIIHexDecode' || filter == 'AHx') {
        data = _decodeAsciiHex(data);
      } else if (filter == 'ASCII85Decode' || filter == 'A85') {
        data = _decodeAscii85(data);
      } else {
        // Unsupported filter (e.g. LZW/JBIG2/DCT); skip gracefully.
        return null;
      }
    }
    return data;
  }

  void _loadXref() {
    final startXrefOffset = _findStartXref();
    if (startXrefOffset == null) return;

    var currentOffset = startXrefOffset;
    final visitedOffsets = <int>{};
    while (currentOffset >= 0 &&
        currentOffset < bytes.length &&
        visitedOffsets.add(currentOffset)) {
      final reader = _PdfReader(bytes, currentOffset);
      reader.skipWhitespaceAndComments();
      if (reader.matchesKeyword('xref')) {
        reader.pos += 4;
        final trailer = _parseClassicXrefSection(reader);
        if (trailer == null) break;
        _trailer ??= trailer;
        final prev = trailer['Prev'];
        if (prev is int) {
          currentOffset = prev;
        } else {
          break;
        }
      } else {
        // Might be an XRef stream object (`N G obj << /Type /XRef ... >>`).
        final parsed = _parseIndirectObjectAt(currentOffset);
        if (parsed is _PdfStream && asName(parsed.dict['Type']) == 'XRef') {
          _trailer ??= parsed.dict;
          _parseXrefStream(parsed);
          final prev = parsed.dict['Prev'];
          if (prev is int) {
            currentOffset = prev;
          } else {
            break;
          }
        } else {
          break;
        }
      }
    }
  }

  int? _findStartXref() {
    final searchStart = math.max(0, bytes.length - 2048);
    final tail = latin1.decode(bytes.sublist(searchStart), allowInvalid: true);
    final idx = tail.lastIndexOf('startxref');
    if (idx < 0) return null;
    final after = tail.substring(idx + 9).trim();
    final match = RegExp(r'^(\d+)').firstMatch(after);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Map<String, Object?>? _parseClassicXrefSection(_PdfReader reader) {
    while (reader.pos < bytes.length) {
      reader.skipWhitespaceAndComments();
      if (reader.matchesKeyword('trailer')) {
        reader.pos += 7;
        final trailerObj = reader.readObject();
        return trailerObj is Map<String, Object?> ? trailerObj : null;
      }
      final startObj = reader.readIntToken();
      final count = reader.readIntToken();
      if (startObj == null || count == null || count < 0 || count > 2000000) {
        return null;
      }
      for (var i = 0; i < count; i++) {
        final offset = reader.readIntToken();
        final gen = reader.readIntToken();
        final flag = reader.readSingleWordToken();
        if (offset == null || gen == null || flag == null) return null;
        if (flag == 'n' && offset > 0) {
          _offsets.putIfAbsent(startObj + i, () => offset);
        }
      }
    }
    return null;
  }

  void _parseXrefStream(_PdfStream stream) {
    final wList = asList(stream.dict['W']);
    if (wList == null || wList.length < 3) return;
    final w0 = asInt(wList[0]) ?? 0;
    final w1 = asInt(wList[1]) ?? 0;
    final w2 = asInt(wList[2]) ?? 0;
    final entrySize = w0 + w1 + w2;
    if (entrySize <= 0) return;

    final decoded = decodeStream(stream);
    if (decoded == null) return;

    final size = asInt(stream.dict['Size']) ?? 0;
    final indexList = asList(stream.dict['Index']);
    final ranges = <(int, int)>[];
    if (indexList != null && indexList.length >= 2) {
      for (var i = 0; i + 1 < indexList.length; i += 2) {
        final first = asInt(indexList[i]) ?? 0;
        final count = asInt(indexList[i + 1]) ?? 0;
        if (count > 0) ranges.add((first, count));
      }
    } else if (size > 0) {
      ranges.add((0, size));
    }

    var cursor = 0;
    for (final (firstObj, count) in ranges) {
      for (var i = 0; i < count; i++) {
        if (cursor + entrySize > decoded.length) return;
        final type = w0 == 0 ? 1 : _readBigEndianInt(decoded, cursor, w0);
        final field2 = _readBigEndianInt(decoded, cursor + w0, w1);
        final field3 = _readBigEndianInt(decoded, cursor + w0 + w1, w2);
        cursor += entrySize;

        final objNum = firstObj + i;
        if (type == 1 && field2 > 0) {
          _offsets.putIfAbsent(objNum, () => field2);
        } else if (type == 2) {
          _compressed.putIfAbsent(
            objNum,
            () => _CompressedEntry(field2, field3),
          );
        }
      }
    }
  }

  void _scanLinearObjects() {
    final text = latin1.decode(bytes, allowInvalid: true);
    for (final match in RegExp(r'(?:^|[\r\n])\s*(\d+)\s+\d+\s+obj\b')
        .allMatches(text)) {
      final objNum = int.tryParse(match.group(1)!);
      if (objNum != null) {
        final objPos = text.indexOf(RegExp(r'\d'), match.start);
        if (objPos >= 0) _offsets.putIfAbsent(objNum, () => objPos);
      }
    }
    final trailerIdx = text.lastIndexOf('trailer');
    if (trailerIdx >= 0) {
      final reader = _PdfReader(bytes, trailerIdx + 7);
      final obj = reader.readObject();
      if (obj is Map<String, Object?>) _trailer = obj;
    }
  }

  Object? _readObject(int objNum) {
    if (_objectCache.containsKey(objNum)) return _objectCache[objNum];
    // Sentinel prevents circular reference infinite recursion.
    _objectCache[objNum] = null;

    Object? result;
    final offset = _offsets[objNum];
    if (offset != null) {
      result = _parseIndirectObjectAt(offset);
    } else {
      final comp = _compressed[objNum];
      if (comp != null) {
        result = _readFromObjectStream(comp.streamObjNum, objNum);
      }
    }
    _objectCache[objNum] = result;
    return result;
  }

  Object? _parseIndirectObjectAt(int offset) {
    if (offset < 0 || offset >= bytes.length) return null;
    final reader = _PdfReader(bytes, offset);
    final objNum = reader.readIntToken();
    final genNum = reader.readIntToken();
    if (objNum == null || genNum == null) return null;
    reader.skipWhitespaceAndComments();
    if (!reader.matchesKeyword('obj')) return null;
    reader.pos += 3;
    return reader.readObject(allowStream: true);
  }

  Object? _readFromObjectStream(int stmObjNum, int targetObjNum) {
    final table = _objStmCache[stmObjNum] ??= _loadObjectStream(stmObjNum);
    return table[targetObjNum];
  }

  Map<int, Object?> _loadObjectStream(int stmObjNum) {
    final map = <int, Object?>{};
    final offset = _offsets[stmObjNum];
    if (offset == null) return map;
    final stm = _parseIndirectObjectAt(offset);
    if (stm is! _PdfStream) return map;
    final n = asInt(stm.dict['N']) ?? 0;
    final first = asInt(stm.dict['First']) ?? 0;
    final decoded = decodeStream(stm);
    if (decoded == null || n <= 0 || first <= 0 || first > decoded.length) {
      return map;
    }

    final headerReader = _PdfReader(decoded, 0);
    final pairs = <(int, int)>[];
    for (var i = 0; i < n; i++) {
      final num = headerReader.readIntToken();
      final relOffset = headerReader.readIntToken();
      if (num == null || relOffset == null) break;
      pairs.add((num, first + relOffset));
    }

    for (final (num, absOffset) in pairs) {
      if (absOffset >= 0 && absOffset < decoded.length) {
        map[num] = _PdfReader(decoded, absOffset).readObject();
      }
    }
    return map;
  }
}

class _CompressedEntry {
  final int streamObjNum;
  final int index;
  const _CompressedEntry(this.streamObjNum, this.index);
}

int _readBigEndianInt(Uint8List bytes, int start, int length) {
  var value = 0;
  for (var i = 0; i < length; i++) {
    value = (value << 8) | bytes[start + i];
  }
  return value;
}

Uint8List? _inflateBytes(Uint8List data) {
  try {
    return Uint8List.fromList(zlib.decode(data));
  } catch (_) {
    return null;
  }
}

Uint8List _applyPredictor(Uint8List data, Map<String, Object?>? parms) {
  if (parms == null) return data;
  final predictor = parms['Predictor'] is int ? parms['Predictor'] as int : 1;
  if (predictor < 10) return data;
  final columns = parms['Columns'] is int ? parms['Columns'] as int : 1;
  final colors = parms['Colors'] is int ? parms['Colors'] as int : 1;
  final bpc = parms['BitsPerComponent'] is int
      ? parms['BitsPerComponent'] as int
      : 8;
  final bytesPerPixel = math.max(1, (colors * bpc + 7) ~/ 8);
  final rowBytes = (columns * colors * bpc + 7) ~/ 8;
  final stride = rowBytes + 1;
  if (stride <= 1 || data.length < stride) return data;

  final rows = data.length ~/ stride;
  final out = Uint8List(rows * rowBytes);
  for (var r = 0; r < rows; r++) {
    final srcRow = r * stride;
    final dstRow = r * rowBytes;
    final filterType = data[srcRow];
    for (var c = 0; c < rowBytes; c++) {
      final raw = data[srcRow + 1 + c];
      final left = c >= bytesPerPixel ? out[dstRow + c - bytesPerPixel] : 0;
      final up = r > 0 ? out[dstRow - rowBytes + c] : 0;
      final upLeft = (r > 0 && c >= bytesPerPixel)
          ? out[dstRow - rowBytes + c - bytesPerPixel]
          : 0;
      final recon = switch (filterType) {
        0 => raw,
        1 => (raw + left) & 0xFF,
        2 => (raw + up) & 0xFF,
        3 => (raw + ((left + up) >> 1)) & 0xFF,
        4 => (raw + _paeth(left, up, upLeft)) & 0xFF,
        _ => raw,
      };
      out[dstRow + c] = recon;
    }
  }
  return out;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

Uint8List _decodeAsciiHex(Uint8List data) {
  final out = <int>[];
  var high = -1;
  for (final b in data) {
    if (b == 0x3E) break; // '>'
    final nibble = _hexNibble(b);
    if (nibble < 0) continue;
    if (high < 0) {
      high = nibble;
    } else {
      out.add((high << 4) | nibble);
      high = -1;
    }
  }
  if (high >= 0) out.add(high << 4);
  return Uint8List.fromList(out);
}

Uint8List _decodeAscii85(Uint8List data) {
  final out = <int>[];
  final group = <int>[];
  var i = 0;
  while (i < data.length) {
    final b = data[i++];
    if (b == 0x7E) break; // '~>'
    if (b <= 0x20) continue;
    if (b == 0x7A && group.isEmpty) {
      // 'z'
      out.addAll(const [0, 0, 0, 0]);
      continue;
    }
    if (b < 0x21 || b > 0x75) continue;
    group.add(b - 0x21);
    if (group.length == 5) {
      var val = 0;
      for (final d in group) {
        val = val * 85 + d;
      }
      out.add((val >> 24) & 0xFF);
      out.add((val >> 16) & 0xFF);
      out.add((val >> 8) & 0xFF);
      out.add(val & 0xFF);
      group.clear();
    }
  }
  if (group.length > 1) {
    final origLen = group.length;
    while (group.length < 5) {
      group.add(84);
    }
    var val = 0;
    for (final d in group) {
      val = val * 85 + d;
    }
    for (var k = 0; k < origLen - 1; k++) {
      out.add((val >> (24 - k * 8)) & 0xFF);
    }
  }
  return Uint8List.fromList(out);
}

int _hexNibble(int b) {
  if (b >= 0x30 && b <= 0x39) return b - 0x30;
  if (b >= 0x41 && b <= 0x46) return b - 0x41 + 10;
  if (b >= 0x61 && b <= 0x66) return b - 0x61 + 10;
  return -1;
}

class _PdfReader {
  final Uint8List bytes;
  int pos;

  _PdfReader(this.bytes, [this.pos = 0]);

  void skipWhitespaceAndComments() {
    while (pos < bytes.length) {
      final b = bytes[pos];
      if (_isWs(b)) {
        pos++;
      } else if (b == 0x25) {
        // '%'
        while (pos < bytes.length && bytes[pos] != 0x0A && bytes[pos] != 0x0D) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  bool matchesKeyword(String kw) {
    if (pos + kw.length > bytes.length) return false;
    for (var i = 0; i < kw.length; i++) {
      if (bytes[pos + i] != kw.codeUnitAt(i)) return false;
    }
    if (pos + kw.length < bytes.length) {
      final next = bytes[pos + kw.length];
      if (!_isWs(next) && !_isDelimiter(next)) return false;
    }
    return true;
  }

  int? readIntToken() {
    skipWhitespaceAndComments();
    if (pos >= bytes.length) return null;
    final start = pos;
    if (bytes[pos] == 0x2B || bytes[pos] == 0x2D) pos++;
    while (pos < bytes.length && bytes[pos] >= 0x30 && bytes[pos] <= 0x39) {
      pos++;
    }
    if (pos == start) return null;
    return int.tryParse(latin1.decode(bytes.sublist(start, pos)));
  }

  String? readSingleWordToken() {
    skipWhitespaceAndComments();
    if (pos >= bytes.length) return null;
    final start = pos;
    while (pos < bytes.length && !_isWs(bytes[pos]) && !_isDelimiter(bytes[pos])) {
      pos++;
    }
    if (pos == start) return null;
    return latin1.decode(bytes.sublist(start, pos));
  }

  Object? readObject({bool allowStream = false, int depth = 0}) {
    if (depth > 32) return null;
    skipWhitespaceAndComments();
    if (pos >= bytes.length) return null;

    final b = bytes[pos];
    if (b == 0x2F) return _PdfName(_readName()); // '/'
    if (b == 0x28) return _PdfStr(_readLiteralString()); // '('
    if (b == 0x3C) {
      if (pos + 1 < bytes.length && bytes[pos + 1] == 0x3C) {
        final dict = _readDict(depth + 1);
        if (allowStream) {
          final saved = pos;
          skipWhitespaceAndComments();
          if (matchesKeyword('stream')) {
            pos += 6;
            if (pos < bytes.length && bytes[pos] == 0x0D) pos++;
            if (pos < bytes.length && bytes[pos] == 0x0A) pos++;
            final rawData = _readStreamBytes(dict['Length']);
            return _PdfStream(dict, rawData);
          }
          pos = saved;
        }
        return dict;
      }
      return _PdfStr(_readHexString());
    }
    if (b == 0x5B) return _readArray(depth + 1); // '['

    // Numbers or `objNum genNum R` or booleans/null.
    final tok = readSingleWordToken();
    if (tok == null) {
      pos++;
      return null;
    }
    if (tok == 'true') return true;
    if (tok == 'false') return false;
    if (tok == 'null') return null;

    final intVal = int.tryParse(tok);
    if (intVal != null) {
      final saved1 = pos;
      final gen = readIntToken();
      if (gen != null) {
        skipWhitespaceAndComments();
        if (matchesKeyword('R')) {
          pos += 1;
          return _PdfRef(intVal, gen);
        }
      }
      pos = saved1;
      return intVal;
    }
    return double.tryParse(tok);
  }

  Uint8List _readStreamBytes(Object? lengthObj) {
    final streamStart = pos;
    if (lengthObj is int && lengthObj >= 0 && streamStart + lengthObj <= bytes.length) {
      pos = streamStart + lengthObj;
      return Uint8List.sublistView(bytes, streamStart, pos);
    }
    // Search for `endstream` strictly forward.
    var cursor = streamStart;
    while (cursor + 9 <= bytes.length) {
      if (bytes[cursor] == 0x65 && // 'e'
          bytes[cursor + 1] == 0x6E &&
          bytes[cursor + 2] == 0x64 &&
          bytes[cursor + 3] == 0x73 &&
          bytes[cursor + 4] == 0x74 &&
          bytes[cursor + 5] == 0x72 &&
          bytes[cursor + 6] == 0x65 &&
          bytes[cursor + 7] == 0x61 &&
          bytes[cursor + 8] == 0x6D) {
        var end = cursor;
        if (end > streamStart && bytes[end - 1] == 0x0A) end--;
        if (end > streamStart && bytes[end - 1] == 0x0D) end--;
        pos = cursor + 9;
        return Uint8List.sublistView(bytes, streamStart, end);
      }
      cursor++;
    }
    pos = bytes.length;
    return Uint8List.sublistView(bytes, streamStart, bytes.length);
  }

  Map<String, Object?> _readDict(int depth) {
    pos += 2; // '<<'
    final dict = <String, Object?>{};
    while (pos < bytes.length) {
      skipWhitespaceAndComments();
      if (pos + 1 < bytes.length &&
          bytes[pos] == 0x3E &&
          bytes[pos + 1] == 0x3E) {
        pos += 2;
        break;
      }
      if (pos >= bytes.length || bytes[pos] != 0x2F) {
        pos++;
        continue;
      }
      final key = _readName();
      final value = readObject(depth: depth + 1);
      dict[key] = value;
    }
    return dict;
  }

  List<Object?> _readArray(int depth) {
    pos++; // '['
    final list = <Object?>[];
    while (pos < bytes.length) {
      skipWhitespaceAndComments();
      if (pos >= bytes.length) break;
      if (bytes[pos] == 0x5D) {
        pos++;
        break;
      }
      final before = pos;
      final item = readObject(depth: depth + 1);
      if (pos == before) {
        pos++;
      } else {
        list.add(item);
      }
    }
    return list;
  }

  String _readName() {
    pos++; // '/'
    final out = <int>[];
    while (pos < bytes.length) {
      final b = bytes[pos];
      if (_isWs(b) || _isDelimiter(b)) break;
      if (b == 0x23 && pos + 2 < bytes.length) {
        final h1 = _hexNibble(bytes[pos + 1]);
        final h2 = _hexNibble(bytes[pos + 2]);
        if (h1 >= 0 && h2 >= 0) {
          out.add((h1 << 4) | h2);
          pos += 3;
          continue;
        }
      }
      out.add(b);
      pos++;
    }
    return utf8.decode(out, allowMalformed: true);
  }

  Uint8List _readLiteralString() {
    pos++; // '('
    final out = <int>[];
    var parenDepth = 0;
    while (pos < bytes.length) {
      final b = bytes[pos++];
      if (b == 0x28) {
        parenDepth++;
        out.add(b);
      } else if (b == 0x29) {
        if (parenDepth == 0) break;
        parenDepth--;
        out.add(b);
      } else if (b == 0x5C) {
        // '\'
        if (pos >= bytes.length) break;
        final esc = bytes[pos++];
        switch (esc) {
          case 0x6E:
            out.add(0x0A); // \n
          case 0x72:
            out.add(0x0D); // \r
          case 0x74:
            out.add(0x09); // \t
          case 0x62:
            out.add(0x08); // \b
          case 0x66:
            out.add(0x0C); // \f
          case 0x0D:
            if (pos < bytes.length && bytes[pos] == 0x0A) pos++;
          case 0x0A:
            break;
          default:
            if (esc >= 0x30 && esc <= 0x37) {
              var oct = esc - 0x30;
              for (var k = 0; k < 2 && pos < bytes.length; k++) {
                final d = bytes[pos];
                if (d >= 0x30 && d <= 0x37) {
                  oct = (oct << 3) | (d - 0x30);
                  pos++;
                } else {
                  break;
                }
              }
              out.add(oct & 0xFF);
            } else {
              out.add(esc);
            }
        }
      } else {
        out.add(b);
      }
    }
    return Uint8List.fromList(out);
  }

  Uint8List _readHexString() {
    pos++; // '<'
    final out = <int>[];
    var high = -1;
    while (pos < bytes.length) {
      final b = bytes[pos++];
      if (b == 0x3E) break; // '>'
      final nibble = _hexNibble(b);
      if (nibble < 0) continue;
      if (high < 0) {
        high = nibble;
      } else {
        out.add((high << 4) | nibble);
        high = -1;
      }
    }
    if (high >= 0) out.add(high << 4);
    return Uint8List.fromList(out);
  }
}

bool _isWs(int b) =>
    b == 0x00 || b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D || b == 0x20;

bool _isDelimiter(int b) =>
    b == 0x28 ||
    b == 0x29 ||
    b == 0x3C ||
    b == 0x3E ||
    b == 0x5B ||
    b == 0x5D ||
    b == 0x7B ||
    b == 0x7D ||
    b == 0x2F ||
    b == 0x25;

// ---------------------------------------------------------------------------
// Font & CMap decoding
// ---------------------------------------------------------------------------

Map<String, _FontDecoder> _buildFontDecoders(
  _PdfRawDoc doc,
  Map<String, Object?> resources,
) {
  final fontDict = doc.asDict(resources['Font']);
  if (fontDict == null) return const {};
  final decoders = <String, _FontDecoder>{};
  for (final entry in fontDict.entries) {
    final dict = doc.asDict(entry.value);
    if (dict != null) {
      decoders[entry.key] = _FontDecoder.fromDict(doc, dict);
    }
  }
  return decoders;
}

class _FontDecoder {
  final Map<int, String> toUnicode;
  final Map<int, String> differences;
  final int defaultCodeBytes;
  final bool isIdentityEncoding;
  final String baseEncoding;

  const _FontDecoder({
    required this.toUnicode,
    required this.differences,
    required this.defaultCodeBytes,
    required this.isIdentityEncoding,
    required this.baseEncoding,
  });

  factory _FontDecoder.fromDict(_PdfRawDoc doc, Map<String, Object?> dict) {
    final subtype = doc.asName(dict['Subtype']) ?? '';
    final encObj = doc.deref(dict['Encoding']);
    var baseEncoding = '';
    final differences = <int, String>{};

    if (encObj is _PdfName) {
      baseEncoding = encObj.name;
    } else if (encObj is Map<String, Object?>) {
      baseEncoding = doc.asName(encObj['BaseEncoding']) ?? '';
      final diffList = doc.asList(encObj['Differences']);
      if (diffList != null) {
        var code = 0;
        for (final item in diffList) {
          final resolved = doc.deref(item);
          if (resolved is int) {
            code = resolved;
          } else if (resolved is _PdfName) {
            final glyphStr = _glyphNameToUnicode(resolved.name);
            if (glyphStr != null) differences[code] = glyphStr;
            code++;
          }
        }
      }
    }

    final isIdentity =
        baseEncoding == 'Identity-H' || baseEncoding == 'Identity-V';
    final toUnicodeMap = <int, String>{};
    var codeBytes = (subtype == 'Type0' || isIdentity) ? 2 : 1;

    final toUniStream = doc.deref(dict['ToUnicode']);
    if (toUniStream is _PdfStream) {
      final decoded = doc.decodeStream(toUniStream);
      if (decoded != null) {
        final parsedBytes = _parseToUnicodeCMap(
          latin1.decode(decoded, allowInvalid: true),
          toUnicodeMap,
        );
        if (parsedBytes != null) codeBytes = parsedBytes;
      }
    }

    return _FontDecoder(
      toUnicode: toUnicodeMap,
      differences: differences,
      defaultCodeBytes: codeBytes,
      isIdentityEncoding: isIdentity,
      baseEncoding: baseEncoding,
    );
  }

  String decode(Uint8List rawBytes) {
    if (rawBytes.isEmpty) return '';
    if (toUnicode.isNotEmpty) {
      final step = (defaultCodeBytes == 2 && rawBytes.length >= 2) ? 2 : 1;
      final buf = StringBuffer();
      for (var i = 0; i < rawBytes.length;) {
        if (step == 2 && i + 1 < rawBytes.length) {
          final code2 = (rawBytes[i] << 8) | rawBytes[i + 1];
          final mapped2 = toUnicode[code2];
          if (mapped2 != null) {
            buf.write(mapped2);
            i += 2;
            continue;
          }
        }
        final code1 = rawBytes[i];
        final mapped1 = toUnicode[code1];
        if (mapped1 != null) {
          buf.write(mapped1);
          i += 1;
          continue;
        }
        if (step == 2 && i + 1 < rawBytes.length) {
          final code2 = (rawBytes[i] << 8) | rawBytes[i + 1];
          if (code2 >= 0x20 && code2 < 0xD800) {
            buf.writeCharCode(code2);
          }
          i += 2;
        } else {
          buf.write(_decodeSingleByte(code1));
          i += 1;
        }
      }
      return buf.toString();
    }

    if (isIdentityEncoding && rawBytes.length.isEven) {
      final buf = StringBuffer();
      for (var i = 0; i + 1 < rawBytes.length; i += 2) {
        final cp = (rawBytes[i] << 8) | rawBytes[i + 1];
        if (cp >= 0x20) buf.writeCharCode(cp);
      }
      return buf.toString();
    }

    final buf = StringBuffer();
    for (final b in rawBytes) {
      final diff = differences[b];
      if (diff != null) {
        buf.write(diff);
      } else {
        buf.write(_decodeSingleByte(b));
      }
    }
    return buf.toString();
  }

  String _decodeSingleByte(int b) {
    if (baseEncoding == 'MacRomanEncoding') {
      return _macRomanChar(b);
    }
    if (b >= 0x80 && b <= 0x9F) {
      return _win1252Extra[b - 0x80];
    }
    return String.fromCharCode(b);
  }
}

int? _parseToUnicodeCMap(String cmapText, Map<int, String> out) {
  int? codeBytes;
  final csMatch = RegExp(
    r'begincodespacerange\s*(.*?)\s*endcodespacerange',
    dotAll: true,
  ).firstMatch(cmapText);
  if (csMatch != null) {
    final hexMatch = RegExp(r'<([0-9A-Fa-f]+)>').firstMatch(csMatch.group(1)!);
    if (hexMatch != null) {
      final len = hexMatch.group(1)!.length;
      if (len <= 2) codeBytes = 1;
      if (len >= 4) codeBytes = 2;
    }
  }

  for (final sec in RegExp(
    r'beginbfchar\s*(.*?)\s*endbfchar',
    dotAll: true,
  ).allMatches(cmapText)) {
    final tokens = RegExp(r'<([0-9A-Fa-f\s]+)>')
        .allMatches(sec.group(1)!)
        .map((m) => m.group(1)!.replaceAll(RegExp(r'\s+'), ''))
        .toList();
    for (var i = 0; i + 1 < tokens.length; i += 2) {
      final src = int.tryParse(tokens[i], radix: 16);
      final dst = _decodeUtf16Hex(tokens[i + 1]);
      if (src != null && dst.isNotEmpty) {
        out[src] = dst;
      }
    }
  }

  for (final sec in RegExp(
    r'beginbfrange\s*(.*?)\s*endbfrange',
    dotAll: true,
  ).allMatches(cmapText)) {
    final body = sec.group(1)!;
    final lineRegex = RegExp(
      r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(\[[^\]]*\]|<[0-9A-Fa-f\s]+>)',
      dotAll: true,
    );
    for (final m in lineRegex.allMatches(body)) {
      final start = int.tryParse(m.group(1)!, radix: 16);
      final end = int.tryParse(m.group(2)!, radix: 16);
      if (start == null || end == null || end < start || end - start > 65536) {
        continue;
      }
      final target = m.group(3)!;
      if (target.startsWith('[')) {
        final arrHex = RegExp(r'<([0-9A-Fa-f\s]+)>')
            .allMatches(target)
            .map((e) => e.group(1)!.replaceAll(RegExp(r'\s+'), ''))
            .toList();
        for (var k = 0; k < arrHex.length && start + k <= end; k++) {
          final dst = _decodeUtf16Hex(arrHex[k]);
          if (dst.isNotEmpty) out[start + k] = dst;
        }
      } else {
        final hex = target.substring(1, target.length - 1).replaceAll(RegExp(r'\s+'), '');
        if (hex.length <= 4) {
          final base = int.tryParse(hex, radix: 16);
          if (base != null) {
            for (var c = start; c <= end; c++) {
              out[c] = String.fromCharCode(base + (c - start));
            }
          }
        } else {
          final prefix = _decodeUtf16Hex(hex.substring(0, hex.length - 4));
          final tail = int.tryParse(hex.substring(hex.length - 4), radix: 16);
          if (tail != null) {
            for (var c = start; c <= end; c++) {
              out[c] = '$prefix${String.fromCharCode(tail + (c - start))}';
            }
          }
        }
      }
    }
  }
  return codeBytes;
}

String _decodeUtf16Hex(String hex) {
  if (hex.isEmpty) return '';
  if (hex.length <= 4) {
    final val = int.tryParse(hex, radix: 16);
    if (val == null || val == 0) return '';
    return String.fromCharCode(val);
  }
  final buf = StringBuffer();
  for (var i = 0; i + 4 <= hex.length; i += 4) {
    final val = int.tryParse(hex.substring(i, i + 4), radix: 16);
    if (val != null && val != 0) buf.writeCharCode(val);
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Content stream interpreter
// ---------------------------------------------------------------------------

void _interpretPageContents({
  required _PdfRawDoc doc,
  required Object? contentEntry,
  required Map<String, _FontDecoder> fonts,
  required Map<String, Object?>? xObjects,
  required _TextRunCollector collector,
  Set<int>? visitedXObjects,
  int depth = 0,
}) {
  if (depth > 8 || contentEntry == null) return;
  final streamBytes = <int>[];

  final resolved = doc.deref(contentEntry);
  if (resolved is _PdfStream) {
    final decoded = doc.decodeStream(resolved);
    if (decoded != null) streamBytes.addAll(decoded);
  } else if (resolved is List<Object?>) {
    for (final item in resolved) {
      final stm = doc.deref(item);
      if (stm is _PdfStream) {
        final decoded = doc.decodeStream(stm);
        if (decoded != null) {
          streamBytes.addAll(decoded);
          streamBytes.add(0x0A);
        }
      }
    }
  }
  if (streamBytes.isEmpty) return;

  final data = Uint8List.fromList(streamBytes);
  final visited = visitedXObjects ?? <int>{};
  final operands = <Object?>[];
  final stateStack = <_TextState>[];
  var state = _TextState();
  var inText = false;
  var tm = _Mat.identity();
  var tlm = _Mat.identity();
  String? actualText;

  var pos = 0;
  final len = data.length;

  while (pos < len) {
    pos = _skipContentWsAndComments(data, pos);
    if (pos >= len) break;

    final b = data[pos];
    if (b == 0x2F) {
      final res = _readContentName(data, pos);
      operands.add(_PdfName(res.$1));
      pos = res.$2;
    } else if (b == 0x28) {
      final res = _readContentLiteral(data, pos);
      operands.add(_PdfStr(res.$1));
      pos = res.$2;
    } else if (b == 0x3C) {
      if (pos + 1 < len && data[pos + 1] == 0x3C) {
        final res = _skipContentDict(data, pos);
        operands.add(res.$1);
        pos = res.$2;
      } else {
        final res = _readContentHex(data, pos);
        operands.add(_PdfStr(res.$1));
        pos = res.$2;
      }
    } else if (b == 0x5B) {
      final res = _readContentArray(data, pos);
      operands.add(res.$1);
      pos = res.$2;
    } else if (b == 0x5D || b == 0x3E) {
      pos++;
    } else {
      final res = _readContentWord(data, pos);
      final word = res.$1;
      pos = res.$2;
      if (word.isEmpty) {
        pos++;
        continue;
      }
      final numVal = double.tryParse(word);
      if (numVal != null) {
        operands.add(numVal);
        continue;
      }
      if (word == 'true' || word == 'false' || word == 'null') {
        operands.add(word);
        continue;
      }

      // PDF operator
      switch (word) {
        case 'BI':
          pos = _skipInlineImage(data, pos);
        case 'q':
          stateStack.add(state.clone());
        case 'Q':
          if (stateStack.isNotEmpty) state = stateStack.removeLast();
        case 'cm':
          if (operands.length >= 6) {
            final m = _matFromOperands(operands);
            if (m != null) state.ctm = m.multiply(state.ctm);
          }
        case 'BT':
          inText = true;
          tm = _Mat.identity();
          tlm = _Mat.identity();
        case 'ET':
          inText = false;
        case 'Tf':
          if (operands.length >= 2) {
            final nameObj = operands[operands.length - 2];
            final sizeObj = operands.last;
            if (nameObj is _PdfName) state.fontName = nameObj.name;
            if (sizeObj is num) state.fontSize = sizeObj.toDouble();
          }
        case 'TL':
          if (operands.isNotEmpty && operands.last is num) {
            state.leading = (operands.last as num).toDouble();
          }
        case 'Tc':
          if (operands.isNotEmpty && operands.last is num) {
            state.charSpacing = (operands.last as num).toDouble();
          }
        case 'Tw':
          if (operands.isNotEmpty && operands.last is num) {
            state.wordSpacing = (operands.last as num).toDouble();
          }
        case 'Tz':
          if (operands.isNotEmpty && operands.last is num) {
            state.horizScaling = (operands.last as num).toDouble();
          }
        case 'Tm':
          if (operands.length >= 6) {
            final m = _matFromOperands(operands);
            if (m != null) {
              tm = m;
              tlm = m;
            }
          }
        case 'Td':
        case 'TD':
          if (operands.length >= 2 &&
              operands[operands.length - 2] is num &&
              operands.last is num) {
            final tx = (operands[operands.length - 2] as num).toDouble();
            final ty = (operands.last as num).toDouble();
            if (word == 'TD') state.leading = -ty;
            tlm = _Mat(1, 0, 0, 1, tx, ty).multiply(tlm);
            tm = tlm;
          }
        case 'T*':
          tlm = _Mat(1, 0, 0, 1, 0, -state.leading).multiply(tlm);
          tm = tlm;
        case 'BDC':
          if (operands.length >= 2 && operands.last is String) {
            final props = operands.last as String;
            final extracted = _extractActualText(props);
            if (extracted != null) actualText = extracted;
          }
        case 'EMC':
          actualText = null;
        case 'Tj':
          if (inText && operands.isNotEmpty && operands.last is _PdfStr) {
            final text = actualText ??
                _decodeFontString(fonts, state.fontName, operands.last as _PdfStr);
            tm = _emitTextRun(collector, text, tm, state);
          }
        case "'":
          tlm = _Mat(1, 0, 0, 1, 0, -state.leading).multiply(tlm);
          tm = tlm;
          if (inText && operands.isNotEmpty && operands.last is _PdfStr) {
            final text = actualText ??
                _decodeFontString(fonts, state.fontName, operands.last as _PdfStr);
            tm = _emitTextRun(collector, text, tm, state);
          }
        case '"':
          if (operands.length >= 3) {
            if (operands[operands.length - 3] is num) {
              state.wordSpacing =
                  (operands[operands.length - 3] as num).toDouble();
            }
            if (operands[operands.length - 2] is num) {
              state.charSpacing =
                  (operands[operands.length - 2] as num).toDouble();
            }
            tlm = _Mat(1, 0, 0, 1, 0, -state.leading).multiply(tlm);
            tm = tlm;
            if (inText && operands.last is _PdfStr) {
              final text = actualText ??
                  _decodeFontString(fonts, state.fontName, operands.last as _PdfStr);
              tm = _emitTextRun(collector, text, tm, state);
            }
          }
        case 'TJ':
          if (inText && operands.isNotEmpty && operands.last is List<Object?>) {
            final arr = operands.last as List<Object?>;
            if (actualText != null) {
              tm = _emitTextRun(collector, actualText, tm, state);
            } else {
              for (final item in arr) {
                if (item is _PdfStr) {
                  final text = _decodeFontString(fonts, state.fontName, item);
                  tm = _emitTextRun(collector, text, tm, state);
                } else if (item is num) {
                  final shift = -item.toDouble() *
                      0.001 *
                      state.fontSize.abs() *
                      (state.horizScaling / 100.0);
                  tm = _Mat(1, 0, 0, 1, shift, 0).multiply(tm);
                }
              }
            }
          }
        case 'Do':
          if (operands.isNotEmpty && operands.last is _PdfName && xObjects != null) {
            final name = (operands.last as _PdfName).name;
            final xObjRef = xObjects[name];
            if (xObjRef is _PdfRef && !visited.add(xObjRef.objNum)) {
              break;
            }
            final xObj = doc.deref(xObjRef);
            if (xObj is _PdfStream && doc.asName(xObj.dict['Subtype']) == 'Form') {
              final formRes = doc.asDict(xObj.dict['Resources']);
              final formFonts = formRes != null
                  ? {...fonts, ..._buildFontDecoders(doc, formRes)}
                  : fonts;
              final formXObjs = formRes != null
                  ? doc.asDict(formRes['XObject']) ?? xObjects
                  : xObjects;
              _interpretPageContents(
                doc: doc,
                contentEntry: xObj,
                fonts: formFonts,
                xObjects: formXObjs,
                collector: collector,
                visitedXObjects: visited,
                depth: depth + 1,
              );
            }
          }
        default:
          break;
      }
      operands.clear();
    }
  }
}

String _decodeFontString(
  Map<String, _FontDecoder> fonts,
  String? fontName,
  _PdfStr str,
) {
  final decoder = fontName == null
      ? null
      : (fonts[fontName] ?? fonts[fontName.replaceAll('-', '#2D')]);
  if (decoder != null) return decoder.decode(str.bytes);
  return latin1.decode(str.bytes, allowInvalid: true);
}

_Mat _emitTextRun(
  _TextRunCollector collector,
  String text,
  _Mat tm,
  _TextState state,
) {
  final fontSize = state.fontSize.abs() > 0 ? state.fontSize.abs() : 12.0;
  final full = tm.multiply(state.ctm);
  final x = full.e;
  // Negate PDF upward Y so top grows downwards (matching PdfLinePosition).
  final y = -full.f;
  final scaleX = math.sqrt(full.a * full.a + full.b * full.b);
  final scaleY = math.sqrt(full.c * full.c + full.d * full.d);
  final scale = (scaleX > 0 ? scaleX : 1.0) * (state.horizScaling / 100.0);
  final height = fontSize * (scaleY > 0 ? scaleY : 1.0);
  final approxWidth = text.length * fontSize * 0.48 * scale;

  if (text.isNotEmpty) {
    collector.add(
      text: text,
      left: x,
      right: x + approxWidth,
      top: y,
      height: height > 0 ? height : 12.0,
    );
  }
  final advance = (text.length * fontSize * 0.48 + state.charSpacing * text.length) *
      (state.horizScaling / 100.0);
  return _Mat(1, 0, 0, 1, advance, 0).multiply(tm);
}

String? _extractActualText(String dictText) {
  final idx = dictText.indexOf('/ActualText');
  if (idx < 0) return null;
  final paren = dictText.indexOf('(', idx);
  if (paren < 0) return null;
  final end = dictText.lastIndexOf(')');
  if (end <= paren) return null;
  return dictText.substring(paren + 1, end);
}

class _TextState {
  _Mat ctm = _Mat.identity();
  String? fontName;
  double fontSize = 12;
  double leading = 14;
  double charSpacing = 0;
  double wordSpacing = 0;
  double horizScaling = 100;

  _TextState clone() {
    return _TextState()
      ..ctm = ctm
      ..fontName = fontName
      ..fontSize = fontSize
      ..leading = leading
      ..charSpacing = charSpacing
      ..wordSpacing = wordSpacing
      ..horizScaling = horizScaling;
  }
}

class _Mat {
  final double a, b, c, d, e, f;
  const _Mat(this.a, this.b, this.c, this.d, this.e, this.f);
  factory _Mat.identity() => const _Mat(1, 0, 0, 1, 0, 0);

  _Mat multiply(_Mat other) {
    return _Mat(
      a * other.a + b * other.c,
      a * other.b + b * other.d,
      c * other.a + d * other.c,
      c * other.b + d * other.d,
      e * other.a + f * other.c + other.e,
      e * other.b + f * other.d + other.f,
    );
  }
}

_Mat? _matFromOperands(List<Object?> ops) {
  final start = ops.length - 6;
  final vals = <double>[];
  for (var i = 0; i < 6; i++) {
    final v = ops[start + i];
    if (v is! num) return null;
    vals.add(v.toDouble());
  }
  return _Mat(vals[0], vals[1], vals[2], vals[3], vals[4], vals[5]);
}

class _TextRunCollector {
  final List<_RawRun> _runs = [];

  void add({
    required String text,
    required double left,
    required double right,
    required double top,
    required double height,
  }) {
    _runs.add(_RawRun(text, left, right, top, height));
  }

  List<PdfLinePosition> toLinePositions() {
    if (_runs.isEmpty) return const [];
    // Group runs sharing the same visual row (within 0.45 * height), keeping
    // PDF reading order for vertical progression across blocks/columns.
    final rows = <List<_RawRun>>[];
    for (final run in _runs) {
      if (rows.isNotEmpty) {
        final lastRow = rows.last;
        final refTop = lastRow.first.top;
        final refHeight = math.max(lastRow.first.height, run.height);
        if ((run.top - refTop).abs() < refHeight * 0.45) {
          lastRow.add(run);
          continue;
        }
      }
      rows.add([run]);
    }

    final result = <PdfLinePosition>[];
    for (final row in rows) {
      row.sort((a, b) => a.left.compareTo(b.left));
      final height = row.fold<double>(0, (m, r) => math.max(m, r.height));
      final text = joinLineWords(
        [for (final r in row) PdfWordBox(r.text, r.left, r.right)],
        height,
      );
      if (text.isEmpty) continue;
      result.add(PdfLinePosition(
        text: text,
        left: row.first.left,
        top: row.first.top,
        height: height,
      ));
    }
    return result;
  }
}

class _RawRun {
  final String text;
  final double left;
  final double right;
  final double top;
  final double height;
  const _RawRun(this.text, this.left, this.right, this.top, this.height);
}

// ---------------------------------------------------------------------------
// Bounded content-stream scanner helpers
// ---------------------------------------------------------------------------

int _skipContentWsAndComments(Uint8List data, int pos) {
  while (pos < data.length) {
    final b = data[pos];
    if (_isWs(b)) {
      pos++;
    } else if (b == 0x25) {
      while (pos < data.length && data[pos] != 0x0A && data[pos] != 0x0D) {
        pos++;
      }
    } else {
      break;
    }
  }
  return pos;
}

(String, int) _readContentName(Uint8List data, int pos) {
  pos++; // '/'
  final out = <int>[];
  while (pos < data.length) {
    final b = data[pos];
    if (_isWs(b) || _isDelimiter(b)) break;
    if (b == 0x23 && pos + 2 < data.length) {
      final h1 = _hexNibble(data[pos + 1]);
      final h2 = _hexNibble(data[pos + 2]);
      if (h1 >= 0 && h2 >= 0) {
        out.add((h1 << 4) | h2);
        pos += 3;
        continue;
      }
    }
    out.add(b);
    pos++;
  }
  return (utf8.decode(out, allowMalformed: true), pos);
}

(Uint8List, int) _readContentLiteral(Uint8List data, int pos) {
  pos++; // '('
  final out = <int>[];
  var depth = 0;
  while (pos < data.length) {
    final b = data[pos++];
    if (b == 0x28) {
      depth++;
      out.add(b);
    } else if (b == 0x29) {
      if (depth == 0) break;
      depth--;
      out.add(b);
    } else if (b == 0x5C) {
      if (pos >= data.length) break;
      final esc = data[pos++];
      switch (esc) {
        case 0x6E:
          out.add(0x0A);
        case 0x72:
          out.add(0x0D);
        case 0x74:
          out.add(0x09);
        case 0x62:
          out.add(0x08);
        case 0x66:
          out.add(0x0C);
        case 0x0D:
          if (pos < data.length && data[pos] == 0x0A) pos++;
        case 0x0A:
          break;
        default:
          if (esc >= 0x30 && esc <= 0x37) {
            var oct = esc - 0x30;
            for (var k = 0; k < 2 && pos < data.length; k++) {
              final d = data[pos];
              if (d >= 0x30 && d <= 0x37) {
                oct = (oct << 3) | (d - 0x30);
                pos++;
              } else {
                break;
              }
            }
            out.add(oct & 0xFF);
          } else {
            out.add(esc);
          }
      }
    } else {
      out.add(b);
    }
  }
  return (Uint8List.fromList(out), pos);
}

(Uint8List, int) _readContentHex(Uint8List data, int pos) {
  pos++; // '<'
  final out = <int>[];
  var high = -1;
  while (pos < data.length) {
    final b = data[pos++];
    if (b == 0x3E) break;
    final nibble = _hexNibble(b);
    if (nibble < 0) continue;
    if (high < 0) {
      high = nibble;
    } else {
      out.add((high << 4) | nibble);
      high = -1;
    }
  }
  if (high >= 0) out.add(high << 4);
  return (Uint8List.fromList(out), pos);
}

(List<Object?>, int) _readContentArray(Uint8List data, int pos) {
  pos++; // '['
  final list = <Object?>[];
  while (pos < data.length) {
    pos = _skipContentWsAndComments(data, pos);
    if (pos >= data.length) break;
    final b = data[pos];
    if (b == 0x5D) {
      pos++;
      break;
    }
    if (b == 0x28) {
      final res = _readContentLiteral(data, pos);
      list.add(_PdfStr(res.$1));
      pos = res.$2;
    } else if (b == 0x3C) {
      final res = _readContentHex(data, pos);
      list.add(_PdfStr(res.$1));
      pos = res.$2;
    } else {
      final res = _readContentWord(data, pos);
      if (res.$1.isEmpty) {
        pos++;
      } else {
        final numVal = double.tryParse(res.$1);
        if (numVal != null) list.add(numVal);
        pos = res.$2;
      }
    }
  }
  return (list, pos);
}

(String, int) _skipContentDict(Uint8List data, int pos) {
  final start = pos;
  pos += 2;
  var depth = 1;
  while (pos < data.length && depth > 0) {
    if (data[pos] == 0x28) {
      pos = _readContentLiteral(data, pos).$2;
    } else if (pos + 1 < data.length && data[pos] == 0x3C && data[pos + 1] == 0x3C) {
      depth++;
      pos += 2;
    } else if (pos + 1 < data.length && data[pos] == 0x3E && data[pos + 1] == 0x3E) {
      depth--;
      pos += 2;
    } else {
      pos++;
    }
  }
  return (latin1.decode(data.sublist(start, pos), allowInvalid: true), pos);
}

(String, int) _readContentWord(Uint8List data, int pos) {
  final start = pos;
  while (pos < data.length && !_isWs(data[pos]) && !_isDelimiter(data[pos])) {
    pos++;
  }
  return (latin1.decode(data.sublist(start, pos), allowInvalid: true), pos);
}

int _skipInlineImage(Uint8List data, int pos) {
  // Read key/value pairs until `ID`, then skip one whitespace byte and binary
  // image bytes until `EI` surrounded by whitespace/EOF.
  while (pos < data.length) {
    pos = _skipContentWsAndComments(data, pos);
    if (pos >= data.length) return pos;
    final b = data[pos];
    if (b == 0x28) {
      pos = _readContentLiteral(data, pos).$2;
    } else if (b == 0x3C) {
      pos = _readContentHex(data, pos).$2;
    } else if (b == 0x5B) {
      pos = _readContentArray(data, pos).$2;
    } else if (b == 0x2F) {
      pos = _readContentName(data, pos).$2;
    } else {
      final word = _readContentWord(data, pos);
      pos = word.$2;
      if (word.$1 == 'ID') {
        if (pos < data.length && _isWs(data[pos])) pos++;
        while (pos + 1 < data.length) {
          if (data[pos] == 0x45 && data[pos + 1] == 0x49) {
            // 'EI'
            final beforeOk = pos == 0 || _isWs(data[pos - 1]);
            final afterOk = pos + 2 >= data.length ||
                _isWs(data[pos + 2]) ||
                _isDelimiter(data[pos + 2]);
            if (beforeOk && afterOk) {
              return pos + 2;
            }
          }
          pos++;
        }
        return data.length;
      }
      if (word.$1.isEmpty) pos++;
    }
  }
  return pos;
}

// ---------------------------------------------------------------------------
// Glyph & encoding tables
// ---------------------------------------------------------------------------

const List<String> _win1252Extra = [
  '€', '\u0081', '‚', 'ƒ', '„', '…', '†', '‡',
  'ˆ', '‰', 'Š', '‹', 'Œ', '\u008D', 'Ž', '\u008F',
  '\u0090', '‘', '’', '“', '”', '•', '–', '—',
  '˜', '™', 'š', '›', 'œ', '\u009D', 'ž', 'Ÿ',
];

String _macRomanChar(int b) {
  if (b < 0x80) return String.fromCharCode(b);
  const table = <int, int>{
    0x80: 0x00C4, 0x81: 0x00C5, 0x82: 0x00C7, 0x83: 0x00C9, 0x84: 0x00D1,
    0x85: 0x00D6, 0x86: 0x00DC, 0x87: 0x00E1, 0x88: 0x00E0, 0x89: 0x00E2,
    0x8A: 0x00E4, 0x8B: 0x00E3, 0x8C: 0x00E5, 0x8D: 0x00E7, 0x8E: 0x00E9,
    0x8F: 0x00E8, 0x90: 0x00EA, 0x91: 0x00EB, 0x92: 0x00ED, 0x93: 0x00EC,
    0x94: 0x00EE, 0x95: 0x00EF, 0x96: 0x00F1, 0x97: 0x00F3, 0x98: 0x00F2,
    0x99: 0x00F4, 0x9A: 0x00F6, 0x9B: 0x00F5, 0x9C: 0x00FA, 0x9D: 0x00F9,
    0x9E: 0x00FB, 0x9F: 0x00FC, 0xA5: 0x2022, 0xD0: 0x2013, 0xD1: 0x2014,
    0xD2: 0x201C, 0xD3: 0x201D, 0xD4: 0x2018, 0xD5: 0x2019, 0xC7: 0x00AB,
    0xC8: 0x00BB, 0xC9: 0x2026,
  };
  return String.fromCharCode(table[b] ?? b);
}

String? _glyphNameToUnicode(String name) {
  final direct = _glyphTable[name];
  if (direct != null) return direct;
  if (name.length == 1) return name;
  if (name.startsWith('uni') && name.length >= 7) {
    final buf = StringBuffer();
    for (var i = 3; i + 4 <= name.length; i += 4) {
      final cp = int.tryParse(name.substring(i, i + 4), radix: 16);
      if (cp == null) return null;
      buf.writeCharCode(cp);
    }
    return buf.isEmpty ? null : buf.toString();
  }
  if (name.startsWith('u') && name.length >= 5 && name.length <= 7) {
    final cp = int.tryParse(name.substring(1), radix: 16);
    if (cp != null) return String.fromCharCode(cp);
  }
  return null;
}

const Map<String, String> _glyphTable = {
  'space': ' ', 'exclam': '!', 'quotedbl': '"', 'numbersign': '#',
  'dollar': r'$', 'percent': '%', 'ampersand': '&', 'quotesingle': "'",
  'parenleft': '(', 'parenright': ')', 'asterisk': '*', 'plus': '+',
  'comma': ',', 'hyphen': '-', 'period': '.', 'slash': '/',
  'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
  'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
  'colon': ':', 'semicolon': ';', 'less': '<', 'equal': '=', 'greater': '>',
  'question': '?', 'at': '@', 'bracketleft': '[', 'backslash': r'\',
  'bracketright': ']', 'asciicircum': '^', 'underscore': '_', 'grave': '`',
  'braceleft': '{', 'bar': '|', 'braceright': '}', 'asciitilde': '~',
  'bullet': '•', 'ellipsis': '…', 'endash': '–', 'emdash': '—',
  'quoteleft': '‘', 'quoteright': '’', 'quotedblleft': '“',
  'quotedblright': '”', 'guillemotleft': '«', 'guillemotright': '»',
  'fi': 'fi', 'fl': 'fl',
  // Latin + Vietnamese accented glyphs
  'Agrave': 'À', 'Aacute': 'Á', 'Acircumflex': 'Â', 'Atilde': 'Ã',
  'Abreve': 'Ă', 'Adieresis': 'Ä', 'Aring': 'Å', 'Ahookabove': 'Ả',
  'Adotbelow': 'Ạ', 'Acircumflexacute': 'Ấ', 'Acircumflexgrave': 'Ầ',
  'Acircumflexhookabove': 'Ẩ', 'Acircumflextilde': 'Ẫ', 'Acircumflexdotbelow': 'Ậ',
  'Abreveacute': 'Ắ', 'Abrevegrave': 'Ằ', 'Abrevehookabove': 'Ẳ',
  'Abrevetilde': 'Ẵ', 'Abrevedotbelow': 'Ặ',
  'agrave': 'à', 'aacute': 'á', 'acircumflex': 'â', 'atilde': 'ã',
  'abreve': 'ă', 'adieresis': 'ä', 'aring': 'å', 'ahookabove': 'ả',
  'adotbelow': 'ạ', 'acircumflexacute': 'ấ', 'acircumflexgrave': 'ầ',
  'acircumflexhookabove': 'ẩ', 'acircumflextilde': 'ẫ', 'acircumflexdotbelow': 'ậ',
  'abreveacute': 'ắ', 'abrevegrave': 'ằ', 'abrevehookabove': 'ẳ',
  'abrevetilde': 'ẵ', 'abrevedotbelow': 'ặ',
  'Ccedilla': 'Ç', 'ccedilla': 'ç',
  'Dcroat': 'Đ', 'dcroat': 'đ', 'Dslash': 'Đ', 'dslash': 'đ', 'Eth': 'Đ', 'eth': 'đ',
  'Egrave': 'È', 'Eacute': 'É', 'Ecircumflex': 'Ê', 'Edieresis': 'Ë',
  'Ehookabove': 'Ẻ', 'Etilde': 'Ẽ', 'Edotbelow': 'Ẹ',
  'Ecircumflexacute': 'Ế', 'Ecircumflexgrave': 'Ề', 'Ecircumflexhookabove': 'Ể',
  'Ecircumflextilde': 'Ễ', 'Ecircumflexdotbelow': 'Ệ',
  'egrave': 'è', 'eacute': 'é', 'ecircumflex': 'ê', 'edieresis': 'ë',
  'ehookabove': 'ẻ', 'etilde': 'ẽ', 'edotbelow': 'ẹ',
  'ecircumflexacute': 'ế', 'ecircumflexgrave': 'ề', 'ecircumflexhookabove': 'ể',
  'ecircumflextilde': 'ễ', 'ecircumflexdotbelow': 'ệ',
  'Igrave': 'Ì', 'Iacute': 'Í', 'Icircumflex': 'Î', 'Idieresis': 'Ï',
  'Ihookabove': 'Ỉ', 'Itilde': 'Ĩ', 'Idotbelow': 'Ị',
  'igrave': 'ì', 'iacute': 'í', 'icircumflex': 'î', 'idieresis': 'ï',
  'ihookabove': 'ỉ', 'itilde': 'ĩ', 'idotbelow': 'ị',
  'Ograve': 'Ò', 'Oacute': 'Ó', 'Ocircumflex': 'Ô', 'Otilde': 'Õ',
  'Odieresis': 'Ö', 'Ohorn': 'Ơ', 'Ohookabove': 'Ỏ', 'Odotbelow': 'Ọ',
  'Ocircumflexacute': 'Ố', 'Ocircumflexgrave': 'Ồ', 'Ocircumflexhookabove': 'Ổ',
  'Ocircumflextilde': 'Ỗ', 'Ocircumflexdotbelow': 'Ộ',
  'Ohornacute': 'Ớ', 'Ohorngrave': 'Ờ', 'Ohornhookabove': 'Ở',
  'Ohorntilde': 'Ỡ', 'Ohorndotbelow': 'Ợ',
  'ograve': 'ò', 'oacute': 'ó', 'ocircumflex': 'ô', 'otilde': 'õ',
  'odieresis': 'ö', 'ohorn': 'ơ', 'ohookabove': 'ỏ', 'odotbelow': 'ọ',
  'ocircumflexacute': 'ố', 'ocircumflexgrave': 'ồ', 'ocircumflexhookabove': 'ổ',
  'ocircumflextilde': 'ỗ', 'ocircumflexdotbelow': 'ộ',
  'ohornacute': 'ớ', 'ohorngrave': 'ờ', 'ohornhookabove': 'ở',
  'ohorntilde': 'ỡ', 'ohorndotbelow': 'ợ',
  'Ugrave': 'Ù', 'Uacute': 'Ú', 'Ucircumflex': 'Û', 'Udieresis': 'Ü',
  'Uhorn': 'Ư', 'Uhookabove': 'Ủ', 'Utilde': 'Ũ', 'Udotbelow': 'Ụ',
  'Uhornacute': 'Ứ', 'Uhorngrave': 'Ừ', 'Uhornhookabove': 'Ử',
  'Uhorntilde': 'Ữ', 'Uhorndotbelow': 'Ự',
  'ugrave': 'ù', 'uacute': 'ú', 'ucircumflex': 'û', 'udieresis': 'ü',
  'uhorn': 'ư', 'uhookabove': 'ủ', 'utilde': 'ũ', 'udotbelow': 'ụ',
  'uhornacute': 'ứ', 'uhorngrave': 'ừ', 'uhornhookabove': 'ử',
  'uhorntilde': 'ữ', 'uhorndotbelow': 'ự',
  'Ygrave': 'Ỳ', 'Yacute': 'Ý', 'Yhookabove': 'Ỷ', 'Ytilde': 'Ỹ', 'Ydotbelow': 'Ỵ',
  'ygrave': 'ỳ', 'yacute': 'ý', 'yhookabove': 'ỷ', 'ytilde': 'ỹ', 'ydotbelow': 'ỵ',
};
