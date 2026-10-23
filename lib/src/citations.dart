// In-text citations (APA author-date, MLA author-page) and reference list entries.
import 'js.dart';
import 'text.dart';

const styles = ['apa', 'mla'];

/// An in-text citation. [key] is the first word of the author text in lowercase; [year] is null for MLA.
class Citation {
  const Citation(this.text, this.start, this.end, this.author, this.key, this.year);
  final String text;
  final int start;
  final int end;
  final String author;
  final String key;
  final String? year;

  Map<String, Object?> toJson() => {'text': text, 'start': start, 'end': end, 'author': author, 'key': key, 'year': year};
}

/// A reference list entry with its key and year.
class Entry extends Span {
  Entry(super.text, super.start, super.end, this.key, this.year);
  final String key;
  final String? year;
}

const _year = r'(?:\d{4}[a-z]?|n\.d\.)';
const _name = "\\p{Lu}[\\p{L}'\\u2019-]+";
const _notAuthors = {
  'appendix', 'chapter', 'chapters', 'fig', 'figure', 'figures', 'line', 'lines', 'p', 'page', 'pages', 'part', //
  'phase', 'pp', 'section', 'see', 'step', 'table', 'tables', 'version', 'vol', 'volume',
};

final _wordRe = RegExp(r"\p{L}[\p{L}'’-]*", unicode: true);
final _lead = RegExp(r'^\s+');
final _apaParen = RegExp('\\(([^()]*?$_year[^()]*)\\)', unicode: true);
final _apaPrefix = RegExp(r'^(?:e\.g\.|see also|see|cf\.),?\s+', caseSensitive: false);
final _apaAuthor = RegExp('^(.*?\\p{L}.*?),?\\s+($_year(?:,\\s*$_year)*)(?=\$|,)', unicode: true);
final _yearSplit = RegExp(r',\s*');
final _upperStart = RegExp(r'^\p{Lu}', unicode: true);
final _narrative =
    RegExp('((?:$_name\\s+){0,4}$_name(?:\\s+(?:and|&)\\s+$_name|\\s+et\\.?\\s*al\\.*)?)\\s+\\(($_year)(?:,[^()]*)?\\)', unicode: true);
final _mlaParen = RegExp(r'\(([^()]+)\)');
final _mlaPart = RegExp(r"^(\p{Lu}[\p{L}'’.\- &,]*?),?\s+(\d+(?:\s*[-–]\s*\d+)?)$", unicode: true);
final _fourDigits = RegExp(r'^\d{4}$');
final _entryMarker = RegExp(r'^(?:\[\d+\]|\d+\.|[-*•])\s+');
final _entryYear = RegExp('\\(($_year)');

String _lowerKey(String s) => jsLower(s).replaceAll('’', "'");

String _firstWord(String s) {
  final m = _wordRe.firstMatch(s);
  return m == null ? '' : _lowerKey(m.group(0)!);
}

Iterable<(String, int)> _parts(String inner, int offset) sync* {
  for (final part in inner.split(';')) {
    final lead = part.length - part.replaceFirst(_lead, '').length;
    yield (jsTrim(part), offset + lead);
    offset += part.length + 1;
  }
}

List<Citation> _apa(String text) {
  final out = <Citation>[];
  // Parenthetical: (Smith, 2020), (Smith & Lee, 2020, p. 4; Brown, 2018a)
  for (final m in _apaParen.allMatches(text)) {
    for (final (trimmed, pStart) in _parts(m.group(1)!, m.start + 1)) {
      final px = _apaPrefix.firstMatch(trimmed);
      final skip = px == null ? 0 : px.end;
      final rest = trimmed.substring(skip);
      final am = _apaAuthor.firstMatch(rest);
      if (am == null) continue;
      final author = am.group(1)!;
      if (!_upperStart.hasMatch(author) || _notAuthors.contains(_firstWord(author))) continue;
      for (final year in am.group(2)!.split(_yearSplit)) {
        out.add(Citation(rest, pStart + skip, pStart + trimmed.length, author, _firstWord(author), year.toLowerCase()));
      }
    }
  }
  // Narrative: Smith (2020), Smith and Lee (2020, p. 4), Smith et al. (2020)
  for (final m in _narrative.allMatches(text)) {
    out.add(Citation(m.group(0)!, m.start, m.end, m.group(1)!, _firstWord(m.group(1)!), m.group(2)!.toLowerCase()));
  }
  return out;
}

List<Citation> _mla(String text) {
  final out = <Citation>[];
  // (Smith 50), (Smith and Lee 50-52), (Smith et al. 12; Brown 7)
  for (final m in _mlaParen.allMatches(text)) {
    for (final (trimmed, pStart) in _parts(m.group(1)!, m.start + 1)) {
      final pm = _mlaPart.firstMatch(trimmed);
      if (pm == null || _notAuthors.contains(_firstWord(pm.group(1)!)) || _fourDigits.hasMatch(pm.group(2)!)) continue;
      out.add(Citation(trimmed, pStart, pStart + trimmed.length, pm.group(1)!, _firstWord(pm.group(1)!), null));
    }
  }
  return out;
}

/// In-text citations with UTF-16 offsets, sorted by position.
List<Citation> findCitations(String text, [String style = 'apa']) {
  if (!styles.contains(style)) throw ArgumentError('Unknown style "$style". Use: ${styles.join(', ')}');
  final list = style == 'apa' ? _apa(text) : _mla(text);
  stableSort<Citation>(list, (a, b) => a.start != b.start ? a.start - b.start : a.end - b.end);
  return list;
}

/// Whether a citation points at a reference entry.
bool citationMatches(Citation c, Entry e) {
  if (c.year != null && c.year != e.year) return false;
  return _wordRe.allMatches(c.author).any((w) => _lowerKey(w.group(0)!) == e.key);
}

Entry parseEntry(Span part) {
  final body = part.text.replaceFirst(_entryMarker, '');
  final y = _entryYear.firstMatch(body);
  return Entry(part.text, part.start, part.end, _firstWord(body), y?.group(1)!.toLowerCase());
}
